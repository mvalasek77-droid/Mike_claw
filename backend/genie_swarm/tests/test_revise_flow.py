"""Revision-loop tests: a finished build can be revised from the app
("change X"), spawning a seeded job that resumes from the build layer
and never touches the original workspace."""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.api import ReviseRequest, _seed_workspace, revise_job, state
from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.session import Session
from genie_swarm.streaming import EventBus


def test_seed_workspace_copies_sources_not_artifacts(tmp_path: Path):
    src = tmp_path / "src"
    (src / "App").mkdir(parents=True)
    (src / "App" / "Main.swift").write_text("let x = 1")
    (src / ".git").mkdir()
    (src / ".git" / "HEAD").write_text("ref")
    (src / ".codegenie").mkdir()
    (src / ".codegenie" / "session.json").write_text("{}")
    (src / "Build.ipa").write_bytes(b"old binary")
    (src / "App.xcarchive").mkdir()
    (src / "App.xcarchive" / "Info.plist").write_text("plist")

    dst = tmp_path / "dst"
    dst.mkdir()
    copied = _seed_workspace(src, dst)

    assert copied == 1
    assert (dst / "App" / "Main.swift").read_text() == "let x = 1"
    assert not (dst / "Build.ipa").exists()          # stale binary excluded
    assert not (dst / ".git").exists()
    assert not (dst / ".codegenie").exists()
    assert not (dst / "App.xcarchive").exists()


@pytest.mark.asyncio
async def test_revise_route_seeds_and_resumes(tmp_path: Path, recorded_llm):
    """Full loop: finished job → POST /revise body → new job runs the
    build layer onward against the seeded workspace, and every agent
    sees the revision request in its prompt."""
    workspace = tmp_path / "ws"

    original_config = state.config
    original_llm = state.llm
    original_jobs = dict(state.jobs)
    original_tasks = dict(state.tasks)
    state.config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
    )
    state.llm = recorded_llm
    state.jobs.clear()
    state.tasks.clear()
    try:
        # 1. A completed source job with a real file in its workspace.
        recorded_llm.script = [
            LLMResponse(text=f"agent {i} done.", tool_calls=[], stop_reason="end_turn")
            for i in range(8)
        ]
        job = BuildJob(spec=AppSpec(title="Habits", prompt="Build a habit tracker."))
        state.jobs[job.id] = job
        bus = state.bus = EventBus()
        orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=state.config)
        session1 = await orch.execute(job)
        assert session1.job.state.value == "succeeded"
        marker = session1.workspace / "Sources" / "Streak.swift"
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text("struct Streak {}")
        first_calls = len(recorded_llm.calls)

        # 2. Revise: everything downstream of the Architect re-runs —
        #    7 of the 8 agents → 7 more scripted responses.
        recorded_llm.script = [
            LLMResponse(text=f"revision agent {i} done.", tool_calls=[], stop_reason="end_turn")
            for i in range(7)
        ]
        result = await revise_job(job.id, ReviseRequest(prompt="Make streaks weekly, not daily."))
        assert result["ok"] is True
        new_id = result["job_id"]
        assert new_id != job.id
        assert result["files_seeded"] >= 1

        await state.tasks[new_id]            # background resume() finishes

        revised = Session.load(workspace, new_id)
        assert revised.job.state.value == "succeeded"
        # Seeded file came across; the original workspace is untouched.
        assert (revised.workspace / "Sources" / "Streak.swift").exists()
        assert marker.exists()
        # Architect was skipped: exactly 7 new LLM calls (8 agents - 1),
        # and each saw the revision request via the spec block.
        new_calls = recorded_llm.calls[first_calls:]
        assert len(new_calls) == 7
        for call in new_calls:
            joined = "\n".join(m.content for m in call["messages"])
            assert "Make streaks weekly, not daily." in joined
    finally:
        state.config = original_config
        state.llm = original_llm
        state.jobs.clear()
        state.jobs.update(original_jobs)
        state.tasks.clear()
        state.tasks.update(original_tasks)
