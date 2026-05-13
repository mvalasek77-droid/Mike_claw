"""Restore-fork + memory-aware resume + workspace cap + cross-build
artifact recall tests."""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from genie_swarm.llm import LLMResponse
from genie_swarm.memory import Memory
from genie_swarm.models import AppSpec, BuildJob, ToolCall
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.session import Session
from genie_swarm.streaming import EventBus
from genie_swarm.tools import ToolRegistry
from genie_swarm.tools.base import ToolContext
from genie_swarm.tools.recall import FindArtifact, RecallArtifact


# --------------------------------------------------------------------------- #
# Workspace size ceiling
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_workspace_cap_emits_event_and_prunes_disk(tmp_path: Path, recorded_llm):
    """When the snapshot dir grows past `max_snapshot_bytes`, the
    on-disk slice for the new checkpoint is pruned and a workspace.full
    event fires. The in-memory checkpoint label still lands so resume()
    knows the stage completed."""
    # Architect writes a big-ish file, so the checkpoint exceeds the cap.
    big_body = "x" * 10_000
    recorded_llm.script = [
        LLMResponse(
            text="",
            tool_calls=[ToolCall(name="write_file", arguments={"path": "huge.txt", "body": big_body})],
            stop_reason="tool_use",
        ),
        LLMResponse(text="done", tool_calls=[], stop_reason="end_turn"),
        # remaining build agents (2) + integrator (1) — minimal
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn"),
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn"),
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn"),
    ]

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0, max_crash_recoveries=0,
        max_snapshot_bytes=512,   # tiny cap to guarantee the limit is hit
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="BigBuild", prompt="x"))

    events_seen: list[str] = []
    async def collect():
        stream = await bus.stream_for(job.id)
        async for ev in stream.subscribe():
            events_seen.append(ev.type)
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert "workspace.full" in events_seen
    # Stage still recorded in-memory, so resume() would skip it.
    labels = [cp.label for cp in session.checkpoints]
    assert "after-architect" in labels
    # ...but the on-disk slice was pruned.
    slug_path = session._snapshots_dir / "after-architect"
    if slug_path.exists():
        # If it still exists, it must be at-or-under cap.
        assert sum(p.stat().st_size for p in slug_path.rglob("*") if p.is_file()) <= 512


# --------------------------------------------------------------------------- #
# Memory-aware resume
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_resume_injects_prior_decisions_into_system_prompt(tmp_path: Path, recorded_llm):
    """Decisions logged on the first run should appear in the system
    prompt of every agent on the resumed run."""
    workspace = tmp_path / "ws"
    job = BuildJob(spec=AppSpec(title="WithMemory", prompt="x"))

    # Seed a partial session: after-architect checkpoint + one decision.
    session = Session.open(job, workspace)
    session.checkpoint("after-architect")
    session.save()
    mem = Memory(workspace)
    mem.note_decision(job.id, "third-party SDKs", "no analytics in v1")

    recorded_llm.script = [
        LLMResponse(text=f"#{i}", tool_calls=[], stop_reason="end_turn")
        for i in range(7)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    await orch.resume(job)

    # The first LLM call after resume is the Coder's; its system prompt
    # should contain the decision text.
    first_resumed_call = recorded_llm.calls[0]
    system_prompt = first_resumed_call["system"]
    assert "Decisions already made" in system_prompt
    assert "no analytics in v1" in system_prompt


# --------------------------------------------------------------------------- #
# Cross-build artifact recall
# --------------------------------------------------------------------------- #

@pytest.fixture
def recall_registry() -> ToolRegistry:
    r = ToolRegistry()
    r.register(FindArtifact())
    r.register(RecallArtifact())
    return r


@pytest.mark.asyncio
async def test_find_artifact_returns_matches_from_past_projects(
    tmp_path: Path, recall_registry, sandbox
):
    """A previously successful project's file shows up in find_artifact
    results when its workspace lives under the same root."""
    # The fixture `sandbox` lives at tmp_path/ws — siblings under tmp_path
    # are other jobs. Seed one.
    other_id = "job_other"
    other_ws = sandbox.policy.workspace.parent / other_id
    other_ws.mkdir(parents=True)
    (other_ws / "Theme").mkdir()
    (other_ws / "Theme" / "Tokens.swift").write_text("public enum Tokens {}")

    # Memory needs to know about the other project as succeeded.
    mem = Memory(sandbox.policy.workspace.parent)
    mem.record_project(other_id, "OtherApp", {}, succeeded=True, summary="shipped")

    ctx = ToolContext(
        job_id="job_current",
        agent="tester",
        workspace=str(sandbox.policy.workspace),
    )
    result = await recall_registry.invoke(
        ToolCall(name="find_artifact", arguments={"query": "Tokens"}),
        sandbox, ctx,
    )
    assert result.ok
    assert other_id in result.content
    assert "Theme/Tokens.swift" in result.content


@pytest.mark.asyncio
async def test_recall_artifact_reads_other_jobs_file(
    tmp_path: Path, recall_registry, sandbox
):
    other_id = "job_other2"
    other_ws = sandbox.policy.workspace.parent / other_id
    other_ws.mkdir(parents=True)
    (other_ws / "Theme.swift").write_text("// borrowed bytes")

    mem = Memory(sandbox.policy.workspace.parent)
    mem.record_project(other_id, "OtherApp", {}, succeeded=True, summary="ok")

    ctx = ToolContext(
        job_id="job_current", agent="tester",
        workspace=str(sandbox.policy.workspace),
    )
    result = await recall_registry.invoke(
        ToolCall(name="recall_artifact", arguments={"job_id": other_id, "path": "Theme.swift"}),
        sandbox, ctx,
    )
    assert result.ok
    assert "borrowed bytes" in result.content


@pytest.mark.asyncio
async def test_recall_artifact_rejects_escape(
    tmp_path: Path, recall_registry, sandbox
):
    """Path traversal in either job_id or path stays inside the
    workspace root."""
    ctx = ToolContext(
        job_id="job_current", agent="tester",
        workspace=str(sandbox.policy.workspace),
    )
    # job_id pointing at parent — should resolve outside the root.
    result = await recall_registry.invoke(
        ToolCall(name="recall_artifact", arguments={"job_id": "../..", "path": "etc/passwd"}),
        sandbox, ctx,
    )
    assert not result.ok


# --------------------------------------------------------------------------- #
# Restore-with-fork primitive
# --------------------------------------------------------------------------- #

def test_fork_seeds_new_workspace_from_snapshot(tmp_path: Path):
    """Forking a snapshot creates a new workspace with the snapshot's
    files in it and the same transcript starting point."""
    job = BuildJob(spec=AppSpec(title="Source", prompt="x"))
    session = Session.open(job, tmp_path)
    session.sandbox.write_text("src/App.swift", "import SwiftUI")
    cp = session.checkpoint("after-architect")
    session.save()

    # Mimic what the /fork endpoint does inline.
    new_job = BuildJob(spec=AppSpec(title="Fork", prompt="x"))
    forked = Session.open(new_job, tmp_path)
    for rel, content in cp.files_snapshot.items():
        target = forked.workspace / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
    forked.transcript = list(cp.transcript)
    forked.checkpoint("after-architect")
    forked.save()

    # Original workspace untouched.
    assert (session.workspace / "src" / "App.swift").read_text() == "import SwiftUI"
    # Forked workspace seeded with the same content.
    assert (forked.workspace / "src" / "App.swift").read_text() == "import SwiftUI"
    # Fork carries the seed checkpoint label.
    reloaded = Session.load(tmp_path, new_job.id)
    assert any(c.label == "after-architect" for c in reloaded.checkpoints)
