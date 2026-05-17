"""FastAPI routes for the Genie Swarm.

Mounted at `/api/coding/swarm` by the parent app.

  POST /build              → start a job, returns {job_id}
  GET  /{job_id}/status    → JSON snapshot of current job
  GET  /{job_id}/stream    → text/event-stream of SwarmEvents
  POST /{job_id}/cancel    → cancel a running job
  GET  /{job_id}/files     → list workspace files
  GET  /{job_id}/file?path=…  → fetch a single file (text)
"""
from __future__ import annotations

import asyncio
import dataclasses
import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from fastapi.responses import JSONResponse, StreamingResponse

from .llm import AnthropicClient, LLMClient, ProviderRoutingLLMClient
from .github_sync import GitHubSyncError, sync_workspace_to_github
from .icon_gen import IconGenError, generate_app_icon
from .runner import MacRunner
from .screenshot_capture import (
    ScreenshotCaptureError,
    capture_app_store_set,
)
from .models import (
    AppSpec,
    BugReportRequest,
    BuildJob,
    BuildRequest,
    GitHubSyncRequest,
    IconGenerateRequest,
    JobState,
    ReleaseReadinessRequest,
    ShipRequest,
)
from .orchestrator import ShipConfig, SwarmConfig, SwarmOrchestrator
from .perfection import run_perfection_matrix
from .release_readiness import run_release_readiness
from .session import Session
from .streaming import EventBus


# ---------------------------------------------------------------------------
# Process-wide singletons. The parent app can swap these by importing
# `state` and re-assigning before mounting the router.
# ---------------------------------------------------------------------------

class SwarmState:
    def __init__(self) -> None:
        self.bus = EventBus()
        self.llm: LLMClient = AnthropicClient()
        self.config = SwarmConfig()
        self.jobs: dict[str, BuildJob] = {}
        self.tasks: dict[str, asyncio.Task[Any]] = {}
        # Per-job map of path -> "accept"|"reject" filed by the iOS UI.
        # The orchestrator drains this between runs to decide which
        # proposed file changes to actually apply.
        self.decisions: dict[str, dict[str, str]] = {}
        # Per-job pause gate. The orchestrator awaits the event between
        # agent runs; /pause clears it, /continue sets it. The default
        # is "set" (running) — we lazy-construct on first /pause.
        self.pause_events: dict[str, asyncio.Event] = {}


state = SwarmState()
router = APIRouter(prefix="/api/coding/swarm", tags=["genie-swarm"])


def _pause_gate_for_state(job_id: str) -> asyncio.Event:
    """Per-job pause event. New jobs start *running* (event set).
    `/pause` clears it; `/continue` sets it again."""
    event = state.pause_events.get(job_id)
    if event is None:
        event = asyncio.Event()
        event.set()
        state.pause_events[job_id] = event
    return event


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/build")
async def start_build(req: BuildRequest, bg: BackgroundTasks):
    job = BuildJob(spec=req.spec)
    state.jobs[job.id] = job

    cfg = state.config
    ship_cfg = _to_ship_config(req.ship) if req.ship else None
    model_overrides = dict(req.model_overrides)
    if req.preferred_model:
        for role in (
            "architect", "coder", "designer", "integrator",
            "unit_tester", "ui_tester", "reviewer", "security",
        ):
            model_overrides.setdefault(role, req.preferred_model)

    if (req.workspace_root or model_overrides or req.skip_tests
            or not req.parallel or ship_cfg or req.cost_cap_usd is not None
            or req.custom_agents or req.max_snapshot_bytes is not None):
        cfg = SwarmConfig(
            workspace_root=Path(req.workspace_root) if req.workspace_root else cfg.workspace_root,
            parallel_build=req.parallel,
            skip_tests=req.skip_tests,
            runtime=cfg.runtime,
            model_overrides=model_overrides,
            ship=ship_cfg,
            cost_cap_usd=req.cost_cap_usd,
            custom_agents=req.custom_agents,
            pause_gate=_pause_gate_for_state,
            max_snapshot_bytes=req.max_snapshot_bytes or cfg.max_snapshot_bytes,
        )
    else:
        # Default config also gets the pause gate wired in.
        cfg = dataclasses.replace(cfg, pause_gate=_pause_gate_for_state)

    llm = state.llm
    if isinstance(state.llm, AnthropicClient):
        keys = req.provider_keys
        llm = ProviderRoutingLLMClient(
            anthropic_key=keys.anthropic if keys else None,
            openai_key=keys.openai if keys else None,
            fallback=state.llm,
        )
    orch = SwarmOrchestrator(llm=llm, bus=state.bus, config=cfg)
    state.tasks[job.id] = asyncio.create_task(_drive(orch, job))
    return {"job_id": job.id, "state": job.state.value}


async def _drive(orch: SwarmOrchestrator, job: BuildJob) -> None:
    try:
        await orch.execute(job)
    except Exception:
        # The orchestrator already emitted error events. Swallow here so
        # the background task doesn't crash the event loop.
        pass


@router.get("/{job_id}/status")
async def job_status(job_id: str):
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    return JSONResponse(job.model_dump())


@router.post("/{job_id}/cancel")
async def cancel_job(job_id: str):
    task = state.tasks.get(job_id)
    if not task:
        raise HTTPException(404, "unknown job")
    task.cancel()
    return {"ok": True}


@router.get("/{job_id}/stream")
async def stream(job_id: str):
    if job_id not in state.jobs:
        raise HTTPException(404, "unknown job")

    async def gen():
        stream = await state.bus.stream_for(job_id)
        async for event in stream.subscribe():
            line = "event: " + event.type + "\n"
            line += "data: " + json.dumps(event.model_dump()) + "\n\n"
            yield line.encode()

    headers = {"Cache-Control": "no-cache", "X-Accel-Buffering": "no"}
    return StreamingResponse(gen(), media_type="text/event-stream", headers=headers)


@router.get("/{job_id}/files")
async def list_files(job_id: str):
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    ws = state.config.workspace_root / job_id
    if not ws.exists():
        return {"files": []}
    files = sorted(
        str(p.relative_to(ws))
        for p in ws.rglob("*")
        if p.is_file() and ".git" not in p.parts
    )
    return {"files": files}


@router.get("/{job_id}/file")
async def get_file(job_id: str, path: str = Query(...)):
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    target = (state.config.workspace_root / job_id / path).resolve()
    base = (state.config.workspace_root / job_id).resolve()
    if base not in target.parents and target != base:
        raise HTTPException(403, "path escapes workspace")
    if not target.exists() or not target.is_file():
        raise HTTPException(404, "file not found")
    return {"path": path, "body": target.read_text(encoding="utf-8", errors="replace")}


@router.post("/{job_id}/decisions")
async def post_decisions(job_id: str, body: dict):
    """The user's accept/reject calls from DiffPreviewView land here.

    Wire shape:
        { "decisions": [ {"path": "...", "status": "accept|reject"} ] }

    Paths not present in the list are treated as rejected. The
    orchestrator polls `state.decisions[job_id]` between agent runs.
    """
    if job_id not in state.jobs:
        raise HTTPException(404, "unknown job")
    incoming = body.get("decisions") or []
    state.decisions.setdefault(job_id, {})
    for entry in incoming:
        path = entry.get("path")
        status = entry.get("status", "reject")
        if path:
            state.decisions[job_id][path] = status
    return {"ok": True, "applied": len(incoming)}


@router.get("/{job_id}/decisions")
async def get_decisions(job_id: str):
    return {"decisions": state.decisions.get(job_id, {})}


@router.post("/{job_id}/ship")
async def ship_now(job_id: str, req: ShipRequest):
    """Promote an already-built job to TestFlight without rebuilding.

    The iOS app calls this when the user taps "Submit to App Store" on
    a green build's success screen. We run only the ship stage against
    the existing workspace and stream the same testflight.upload +
    testflight.status events the build flow uses."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    if job.state not in {JobState.succeeded, JobState.testing, JobState.reviewing}:
        raise HTTPException(409, f"job is in state {job.state.value}; not shippable")

    orch = SwarmOrchestrator(llm=state.llm, bus=state.bus, config=state.config)
    state.tasks[job_id] = asyncio.create_task(orch.ship_only(job, _to_ship_config(req)))
    return {"ok": True, "job_id": job_id}


@router.post("/{job_id}/release-readiness")
async def release_readiness(job_id: str, req: ReleaseReadinessRequest | None = None):
    """Audit launch automation before TestFlight/App Store handoff.

    This gives iOS one deterministic answer for Xcode archive state,
    Apple credentials, privacy/terms artifacts, screenshots, metadata,
    GitHub readiness, and the Apple-required final confirmation.
    """
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    result = run_release_readiness(
        spec=job.spec,
        workspace=state.config.workspace_root / job_id,
        ship=req.ship if req else None,
        github=req.github if req else None,
    )

    from .memory import Memory
    Memory(state.config.workspace_root).note_decision(
        job_id,
        "release readiness",
        f"{result['release_gate']} at {result['score']}/100: {result['summary']}",
    )
    return result


@router.post("/{job_id}/screenshots/capture")
async def screenshots_capture(job_id: str):
    """Drive `xcrun simctl io booted screenshot` on the paired Mac
    (or the local sandbox on a dev Mac) once per required App Store
    device size, writing PNGs into `<workspace>/Screenshots/`.

    Closes the "Auto-generate screenshots" promise from ASC step 4.
    Returns the list of paths the iOS surface can render."""
    from .sandbox import Sandbox, SandboxPolicy
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    workspace.mkdir(parents=True, exist_ok=True)
    sandbox = Sandbox(SandboxPolicy(workspace=workspace))
    runner = MacRunner.resolve(job_id=job_id, companion_paired=False)
    try:
        captured = await capture_app_store_set(
            runner=runner,
            sandbox=sandbox,
            workspace=workspace,
        )
    except ScreenshotCaptureError as exc:
        raise HTTPException(400, str(exc))

    events = await state.bus.stream_for(job_id)
    await events.emit(
        "log",
        message=f"Captured {len(captured)} App Store screenshots",
    )
    return {
        "ok": True,
        "screenshots": [
            {
                "device_id": shot.device.id,
                "device_label": shot.device.label,
                "path": str(shot.path.relative_to(workspace)),
                "bytes_written": shot.bytes_written,
            }
            for shot in captured
        ],
    }


@router.post("/{job_id}/icon/generate")
async def icon_generate(job_id: str, req: IconGenerateRequest):
    """Generate a 1024×1024 App Store icon via OpenAI's image API
    and drop it into the job's `Assets.xcassets/AppIcon.appiconset`.

    Closes the "icon forged with ChatGPT" promise from onboarding —
    previously a placeholder, now wired end-to-end."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    workspace.mkdir(parents=True, exist_ok=True)
    try:
        result = await generate_app_icon(
            title=req.title,
            description=req.description,
            workspace=workspace,
            prompt_override=req.prompt_override,
        )
    except IconGenError as exc:
        raise HTTPException(400, str(exc))

    events = await state.bus.stream_for(job_id)
    await events.emit(
        "log",
        message=f"Generated app icon ({result.bytes_written} bytes, "
                f"alpha_stripped={result.alpha_stripped})",
        path=str(result.path.relative_to(workspace)),
    )
    return {
        "ok": True,
        "path": str(result.path.relative_to(workspace)),
        "bytes_written": result.bytes_written,
        "alpha_stripped": result.alpha_stripped,
        "prompt_used": result.prompt_used,
    }


@router.post("/{job_id}/github/sync")
async def github_sync(job_id: str, req: GitHubSyncRequest):
    """Push the generated workspace to the user's GitHub repository."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    try:
        result = await sync_workspace_to_github(workspace, req)
    except GitHubSyncError as exc:
        raise HTTPException(400, str(exc))

    events = await state.bus.stream_for(job_id)
    await events.emit(
        "log",
        message=f"Synced workspace to GitHub branch {result['branch']}",
        remote=result["remote"],
    )
    return result


@router.post("/{job_id}/restore")
async def restore_snapshot(job_id: str, body: dict):
    """Roll the workspace back to a named snapshot.

    Body: { "label": "before accepting the icon redesign" }

    The user picks a snapshot from the iOS picker; we re-write every
    file the snapshot captured and truncate the in-memory transcript
    to where that snapshot was taken. The orchestrator is not running
    when this is called — `cancel` first if it is."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    label = (body or {}).get("label")
    if not label:
        raise HTTPException(400, "label required")

    from .session import Session
    try:
        session = Session.load(state.config.workspace_root, job_id)
    except FileNotFoundError:
        raise HTTPException(404, "no saved session")

    match = next((c for c in session.checkpoints if c.label == label), None)
    if match is None:
        raise HTTPException(404, f"no snapshot labeled {label!r}")

    # Real rollback: re-hydrate the snapshot's files onto disk and
    # remove anything newer. `Session.load` already loaded the file
    # contents from `.codegenie/snapshots/<slug>/`.
    session.restore(match)
    session.save()
    return {
        "ok": True,
        "label": label,
        "transcript_truncated": True,
        "files_restored": len(match.files_snapshot),
    }


@router.post("/{job_id}/pause")
async def pause_job(job_id: str):
    """Soft-pause the orchestrator between agents. The current LLM
    call finishes; the next agent waits for /continue. Idempotent."""
    if job_id not in state.jobs:
        raise HTTPException(404, "unknown job")
    state.pause_events.setdefault(job_id, asyncio.Event()).clear()
    return {"ok": True, "paused": True}


@router.post("/{job_id}/continue")
async def continue_job(job_id: str):
    """Resume a paused orchestrator. Idempotent."""
    if job_id not in state.jobs:
        raise HTTPException(404, "unknown job")
    event = state.pause_events.setdefault(job_id, asyncio.Event())
    event.set()
    return {"ok": True, "paused": False}


@router.post("/{job_id}/resume")
async def resume_job(job_id: str):
    """Pick up an interrupted build from the latest checkpoint.

    Use cases:
      * The user cancelled mid-build and now wants to continue.
      * A cost cap was hit; the user lifted it and wants to resume.
      * The process restarted between agent runs.

    The orchestrator decides which stages to skip based on what was
    checkpointed; the body is empty by design — the workspace and
    saved session are the only inputs needed."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    if job.state in {JobState.queued, JobState.planning, JobState.building, JobState.testing}:
        raise HTTPException(409, f"job is already running (state={job.state.value})")

    orch = SwarmOrchestrator(llm=state.llm, bus=state.bus, config=state.config)
    state.tasks[job_id] = asyncio.create_task(orch.resume(job))
    return {"ok": True, "job_id": job_id}


@router.post("/{job_id}/fork")
async def fork_snapshot(job_id: str, body: dict):
    """Branch a snapshot into a brand-new job. The live build stays
    untouched; the fork gets its own workspace seeded from the
    snapshot's files + transcript.

    Body: { "label": "after-architect", "title": "Optional new name" }

    Returns the new job_id so the iOS UI can open it as a fresh run.
    """
    original = state.jobs.get(job_id)
    if not original:
        raise HTTPException(404, "unknown job")
    label = (body or {}).get("label")
    if not label:
        raise HTTPException(400, "label required")
    new_title = (body or {}).get("title")

    from .session import Session
    try:
        source = Session.load(state.config.workspace_root, job_id)
    except FileNotFoundError:
        raise HTTPException(404, "no saved session")

    match = next((c for c in source.checkpoints if c.label == label), None)
    if match is None:
        raise HTTPException(404, f"no snapshot labeled {label!r}")

    # Build a new job with a fresh ID and (optionally) a new title.
    forked_spec = original.spec.model_copy(update={"title": new_title} if new_title else {})
    forked_job = BuildJob(spec=forked_spec)
    state.jobs[forked_job.id] = forked_job

    # Open a session at the new workspace and seed it from the snapshot.
    forked = Session.open(forked_job, state.config.workspace_root)
    for rel, content in match.files_snapshot.items():
        target = forked.workspace / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        try:
            target.write_text(content, encoding="utf-8")
        except OSError:
            pass
    forked.transcript = list(match.transcript)
    # Carry the "after-X" checkpoint label forward so the fork knows
    # which stage it's been seeded past — `resume()` can then run only
    # what's downstream of that point.
    forked.checkpoint(label)
    forked.save()

    return {
        "ok": True,
        "job_id": forked_job.id,
        "from": {"job_id": job_id, "label": label},
        "files_seeded": len(match.files_snapshot),
    }


@router.post("/{job_id}/snapshot")
async def take_snapshot(job_id: str, body: dict | None = None):
    """User-initiated checkpoint. Useful before a risky diff batch — if
    the next agent goes sideways the iOS UI can ask the orchestrator
    to restore from this label.

    Body: { "label": "before accepting the icon redesign" } — optional.
    Reuses `Session.checkpoint` so snapshots and orchestrator-internal
    checkpoints share storage and replay paths.
    """
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    if not workspace.exists():
        raise HTTPException(404, "workspace not found")

    from .session import Session
    session = Session.open(job, state.config.workspace_root)
    label = (body or {}).get("label") or f"manual {len(session.checkpoints) + 1}"
    cp = session.checkpoint(label)
    session.save()
    return {
        "ok": True,
        "label": cp.label,
        "at": cp.at,
        "files": len(cp.files_snapshot),
    }


@router.get("/{job_id}/snapshots")
async def list_snapshots(job_id: str):
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    if not workspace.exists():
        return {"snapshots": []}
    try:
        from .session import Session
        session = Session.load(state.config.workspace_root, job_id)
    except FileNotFoundError:
        return {"snapshots": []}
    return {
        "snapshots": [
            {"label": c.label, "at": c.at, "files": len(c.files_snapshot)}
            for c in session.checkpoints
        ]
    }


@router.post("/{job_id}/perfection")
async def run_perfection(job_id: str, body: dict | None = None):
    """Run the deterministic 10,000-probe release matrix.

    This is the "always automated" gate the iOS app can trigger before
    TestFlight: no token spend, no real simulator required, just a fast
    senior-review pass over the generated workspace. Critical/error
    findings block release; warnings ask for polish and a rerun.
    """
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")

    raw_probes = (body or {}).get("probes", 10_000)
    try:
        requested = int(raw_probes)
    except (TypeError, ValueError):
        requested = 10_000
    workspace = state.config.workspace_root / job_id
    result = run_perfection_matrix(
        spec=job.spec,
        workspace=workspace,
        requested_probes=requested,
    )

    from .memory import Memory
    Memory(state.config.workspace_root).note_decision(
        job_id,
        "perfection matrix",
        f"{result['release_gate']} at {result['score']}/100: {result['summary']}",
    )

    # Surface the highest-severity findings into any live transcript so
    # the build screen does not need to poll a second channel.
    events = await state.bus.stream_for(job_id)
    for finding in result["findings"][:8]:
        await events.emit("review.finding", **finding)
    return result


@router.get("/{job_id}/export")
async def export_workspace(job_id: str):
    """Stream the job's workspace as a zip so the iOS Apps tab can let
    the user keep a copy after the cloud workspace is reaped."""
    job = state.jobs.get(job_id)
    if not job:
        raise HTTPException(404, "unknown job")
    workspace = state.config.workspace_root / job_id
    if not workspace.exists():
        raise HTTPException(404, "workspace not found")

    def _stream():
        import io
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in workspace.rglob("*"):
                if not path.is_file():
                    continue
                # Skip our own metadata + anything inside .codegenie
                # so secrets in Memory don't leak with the export.
                rel = path.relative_to(workspace)
                if rel.parts and rel.parts[0] in {".codegenie", ".genie-session.json"}:
                    continue
                if ".git" in rel.parts:
                    continue
                zf.write(path, arcname=str(rel))
        buf.seek(0)
        while chunk := buf.read(64 * 1024):
            yield chunk

    filename = f"{job.spec.title.replace(' ', '_')}.zip"
    return StreamingResponse(
        _stream(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/memory/projects")
async def list_memory_projects(limit: int = Query(20, ge=1, le=200), only_failed: bool = False):
    """Recent project records from CodeGenie's persistent memory.

    Powers the iOS "Recent build failures" view. By default returns
    the last `limit` projects (success + failure). Pass
    `only_failed=true` to filter — useful for the crash log."""
    from .memory import Memory
    mem = Memory(state.config.workspace_root)
    rows = mem.recent_projects(limit=limit)
    if only_failed:
        rows = [r for r in rows if not r.succeeded]
    return {
        "projects": [
            {
                "job_id": r.job_id,
                "title": r.title,
                "succeeded": r.succeeded,
                "summary": r.summary,
                "ts": r.ts,
            }
            for r in rows
        ]
    }


@router.get("/memory/decisions/search")
async def search_memory_decisions(
    q: str = Query(..., min_length=1),
    job_id: str | None = None,
    limit: int = Query(30, ge=1, le=100),
):
    """Search reasoning decisions across every job.

    This powers the iOS searchable decisions panel: a user can ask
    "why did we choose RevenueCat?" or "where did offline fail?" and
    jump back to the runs that made those calls.
    """
    from .memory import Memory
    mem = Memory(state.config.workspace_root)
    rows = mem.search_decisions(q, job_id=job_id, limit=limit)
    return {
        "decisions": [
            {
                "job_id": d.job_id,
                "context": d.context,
                "decision": d.decision,
                "ts": d.ts,
            }
            for d in rows
        ]
    }


@router.get("/memory/decisions/{job_id}")
async def list_memory_decisions(job_id: str):
    """Reasoning decisions the swarm logged for a specific job."""
    from .memory import Memory
    mem = Memory(state.config.workspace_root)
    rows = mem.decisions_for(job_id)
    return {
        "decisions": [
            {"context": d.context, "decision": d.decision, "ts": d.ts}
            for d in rows
        ]
    }


@router.get("/admin/archives")
async def list_archives():
    """List `.archives/*.zip` files with size + mtime + parsed
    `(job_id, archived_at)` from the filename pattern
    `<job_id>-<unix_ts>.zip`."""
    archives_dir = state.config.workspace_root / ".archives"
    if not archives_dir.is_dir():
        return {"archives": []}
    out: list[dict[str, Any]] = []
    for p in archives_dir.iterdir():
        if not p.is_file() or p.suffix != ".zip":
            continue
        try:
            stat = p.stat()
        except OSError:
            continue
        stem = p.stem
        job_id, archived_at = stem, None
        if "-" in stem:
            job_id, _, ts = stem.rpartition("-")
            if ts.isdigit():
                archived_at = int(ts)
        out.append({
            "filename": p.name,
            "job_id": job_id,
            "archived_at": archived_at,
            "size_bytes": stat.st_size,
            "mtime": stat.st_mtime,
        })
    out.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    return {"archives": out}


@router.post("/admin/archives/{filename}/extract")
async def extract_archive(filename: str):
    """Restore an archived workspace back into `workspace_root`. The
    extracted job id is parsed from the filename's stem. We refuse to
    overwrite an existing live job dir — the user has to cancel +
    archive that one first."""
    archives_dir = state.config.workspace_root / ".archives"
    archive = (archives_dir / filename).resolve()
    try:
        archive.relative_to(archives_dir.resolve())
    except ValueError:
        raise HTTPException(400, "path escapes archive dir")
    if not archive.is_file() or archive.suffix != ".zip":
        raise HTTPException(404, "not an archive")
    stem = archive.stem
    job_id = stem.rpartition("-")[0] if "-" in stem else stem
    target = state.config.workspace_root / job_id
    if target.exists():
        raise HTTPException(409, f"live workspace already exists at {target.name}")

    import zipfile
    target.mkdir(parents=True, exist_ok=True)
    files_extracted = 0
    with zipfile.ZipFile(archive) as zf:
        for member in zf.namelist():
            # Defensive: zip member paths that resolve outside `target`
            # are skipped (zip-slip protection).
            dest = (target / member).resolve()
            try:
                dest.relative_to(target.resolve())
            except ValueError:
                continue
            zf.extract(member, target)
            files_extracted += 1
    return {"ok": True, "job_id": job_id, "files_extracted": files_extracted}


@router.post("/admin/archive")
async def archive_old_jobs(body: dict | None = None):
    """Zip + remove job workspaces older than `older_than_days`
    (default 30). Active jobs are skipped. Returns one summary per
    archive."""
    from .archive import archive_old_workspaces
    days = float((body or {}).get("older_than_days", 30))
    active = {job_id for job_id, task in state.tasks.items() if not task.done()}
    summaries = archive_old_workspaces(
        state.config.workspace_root,
        older_than_seconds=days * 24 * 60 * 60,
        active_job_ids=active,
    )
    return {
        "archived": [
            {
                "job_id": s.job_id,
                "archive_path": s.archive_path,
                "bytes_written": s.bytes_written,
                "files_archived": s.files_archived,
            }
            for s in summaries
        ]
    }


@router.get("/health")
async def health():
    return {"ok": True, "active_jobs": len(state.tasks)}


@router.post("/bug-reports")
async def submit_bug_report(req: BugReportRequest):
    """Accept an in-app bug report from the iOS Settings sheet.

    Stored as a JSON file under `<workspace_root>/.bug_reports/`. The
    iOS mailto fallback still works for users who don't trust posting
    privately — this endpoint is the additive in-app channel.
    """
    import json
    import secrets
    import time
    from datetime import datetime, timezone

    reports_dir = state.config.workspace_root / ".bug_reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    report_id = f"{int(time.time())}-{secrets.token_hex(4)}"
    payload = {
        "id": report_id,
        "received_at": datetime.now(timezone.utc).isoformat(),
        "details": req.details,
        "diagnostics": req.diagnostics,
        "client_version": req.client_version,
        "client_build": req.client_build,
        "device": req.device,
        "os_version": req.os_version,
    }
    (reports_dir / f"{report_id}.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True)
    )
    return {"ok": True, "id": report_id}


def _to_ship_config(req: ShipRequest) -> ShipConfig:
    return ShipConfig(
        ipa_path=req.ipa_path,
        bundle_id=req.bundle_id,
        apple_id=req.apple_id,
        app_specific_password=req.app_specific_password,
        asc_api_key_id=req.asc_api_key_id,
        asc_api_issuer_id=req.asc_api_issuer_id,
        asc_api_key_path=req.asc_api_key_path,
        poll_after_upload=req.poll_after_upload,
    )
