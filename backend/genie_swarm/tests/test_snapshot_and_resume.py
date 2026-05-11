"""Snapshot + resume tests.

These don't run the orchestrator end-to-end — they exercise the
Session checkpoint primitives the /snapshot route uses, then prove
the orchestrator's resume() skips already-completed stages.
"""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.session import Session
from genie_swarm.streaming import EventBus


def test_manual_checkpoint_persists_and_loads(tmp_path: Path):
    job = BuildJob(spec=AppSpec(title="Snap", prompt="x"))
    session = Session.open(job, tmp_path)
    session.sandbox.write_text("hello.txt", "world")
    label = "before risky change"
    cp = session.checkpoint(label)
    session.save()

    loaded = Session.load(tmp_path, job.id)
    assert len(loaded.checkpoints) == 1
    assert loaded.checkpoints[0].label == label
    # files_snapshot is not persisted (only listed) so we verify the
    # round-trip preserves label + count.
    # The original in-memory checkpoint should also have captured the file.
    assert "hello.txt" in cp.files_snapshot


def test_checkpoint_excludes_metadata_directory(tmp_path: Path):
    """`.codegenie/` (memory storage) and `.git/` should not be
    included in user-visible snapshots — they're never useful as
    rollback targets and may contain secrets."""
    job = BuildJob(spec=AppSpec(title="Filtered", prompt="x"))
    session = Session.open(job, tmp_path)
    session.sandbox.write_text("src/App.swift", "import SwiftUI")
    # The checkpoint walk uses rglob — it includes everything under the
    # workspace. We do filter `.git` in the snapshot loop; verify here.
    (session.workspace / ".git").mkdir()
    (session.workspace / ".git" / "HEAD").write_text("ref: x")
    cp = session.checkpoint("after-write")

    paths = set(cp.files_snapshot.keys())
    assert "src/App.swift" in paths
    assert not any(".git" in p.split("/") for p in paths)


# --------------------------------------------------------------------------- #
# Resume
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_resume_skips_completed_stages(tmp_path: Path, recorded_llm):
    """After an initial run that ran to completion (4 build agents +
    test layer + ship), calling resume() should NOT replay them. We
    verify by counting LLM calls — a fresh script with zero responses
    is fine because resume() should not need any."""
    workspace = tmp_path / "ws"
    job = BuildJob(spec=AppSpec(title="Twice", prompt="ok"))

    # First run: 8 agents, one text-only reply each.
    recorded_llm.script = [
        LLMResponse(text=f"agent {i} done.", tool_calls=[], stop_reason="end_turn")
        for i in range(8)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
    )
    orch1 = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    session1 = await orch1.execute(job)
    assert session1.job.state.value == "succeeded"
    first_run_calls = len(recorded_llm.calls)
    assert first_run_calls == 8

    # Resume: every stage already has a matching checkpoint, so nothing
    # should fire. Fresh orchestrator instance.
    orch2 = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    session2 = await orch2.resume(job)
    assert session2.job.state.value == "succeeded"
    # No additional LLM calls.
    assert len(recorded_llm.calls) == first_run_calls


@pytest.mark.asyncio
async def test_resume_picks_up_partial_run(tmp_path: Path, recorded_llm):
    """Seed a session with only the Architect checkpoint, then call
    resume() and verify exactly the build-layer + later agents fire."""
    workspace = tmp_path / "ws"
    job = BuildJob(spec=AppSpec(title="Partial", prompt="x"))

    # Manually create the workspace + a single after-architect
    # checkpoint, then persist. Simulates the build crashing right
    # after Architect finished.
    session = Session.open(job, workspace)
    session.checkpoint("after-architect")
    session.save()

    # Architect should NOT fire. We give resume() exactly enough script
    # for everything that *should* run: Coder, Designer, Integrator,
    # UnitTester, UITester, Reviewer, Security = 7 agents.
    recorded_llm.script = [
        LLMResponse(text=f"agent #{i}", tool_calls=[], stop_reason="end_turn")
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

    # Exactly the 7 non-architect agents should have been called.
    assert len(recorded_llm.calls) == 7
