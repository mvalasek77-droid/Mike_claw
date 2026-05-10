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
import json
from pathlib import Path
from typing import Any

from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from fastapi.responses import JSONResponse, StreamingResponse

from .llm import AnthropicClient, LLMClient
from .models import AppSpec, BuildJob, BuildRequest, JobState
from .orchestrator import SwarmConfig, SwarmOrchestrator
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


state = SwarmState()
router = APIRouter(prefix="/api/coding/swarm", tags=["genie-swarm"])


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/build")
async def start_build(req: BuildRequest, bg: BackgroundTasks):
    job = BuildJob(spec=req.spec)
    state.jobs[job.id] = job

    cfg = state.config
    if req.workspace_root or req.model_overrides or req.skip_tests or not req.parallel:
        cfg = SwarmConfig(
            workspace_root=Path(req.workspace_root) if req.workspace_root else cfg.workspace_root,
            parallel_build=req.parallel,
            skip_tests=req.skip_tests,
            runtime=cfg.runtime,
            model_overrides=req.model_overrides,
        )

    orch = SwarmOrchestrator(llm=state.llm, bus=state.bus, config=cfg)
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


@router.get("/health")
async def health():
    return {"ok": True, "active_jobs": len(state.tasks)}
