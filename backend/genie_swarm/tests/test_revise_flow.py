"""Revision-loop tests: a finished build can be revised from the app
("change X"), spawning a seeded job that resumes from the build layer
and never touches the original workspace."""
from __future__ import annotations

import asyncio
import dataclasses

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


# --------------------------------------------------------------------------- #
# "Can the app be edited at the TestFlight stage and after?" — the gate +
# the re-ship path. A build that has shipped to TestFlight lands in
# `succeeded` (ship runs BEFORE the succeeded transition), and `succeeded`
# is editable; only an actively-running job is refused.
# --------------------------------------------------------------------------- #

import os

from genie_swarm.api import _to_ship_config
from genie_swarm.models import JobState, ShipRequest
from genie_swarm.orchestrator import ShipConfig
import genie_swarm.testflight_status as ts
from fastapi import HTTPException


@pytest.mark.asyncio
async def test_revise_gate_blocks_running_allows_finished(tmp_path: Path):
    """A job still building/testing is refused (409); a finished job with
    no saved workspace reports the actionable 404. Proves the editable
    window is exactly 'after the build (incl. after TestFlight ship)'."""
    original_jobs = dict(state.jobs)
    original_config = state.config
    state.config = SwarmConfig(workspace_root=tmp_path / "ws")
    state.jobs.clear()
    try:
        for blocked in (JobState.queued, JobState.planning, JobState.building, JobState.testing):
            job = BuildJob(spec=AppSpec(title="Busy", prompt="x"), state=blocked)
            state.jobs[job.id] = job
            with pytest.raises(HTTPException) as exc:
                await revise_job(job.id, ReviseRequest(prompt="change it"))
            assert exc.value.status_code == 409

        # Finished (succeeded) is past the gate — it fails only later, on
        # the missing-workspace check, with the actionable message.
        done = BuildJob(spec=AppSpec(title="Done", prompt="x"), state=JobState.succeeded)
        state.jobs[done.id] = done
        with pytest.raises(HTTPException) as exc:
            await revise_job(done.id, ReviseRequest(prompt="change it"))
        assert exc.value.status_code == 404
        assert "finished builds" in str(exc.value.detail)
    finally:
        state.config = original_config
        state.jobs.clear()
        state.jobs.update(original_jobs)


@pytest.mark.asyncio
async def test_revise_after_testflight_reships(tmp_path: Path, recorded_llm, monkeypatch):
    """End-to-end at the orchestrator level: a shipped build's workspace
    is revised (seeded, Architect skipped) and resume() with a ship
    config RE-UPLOADS to TestFlight. Proves edits after TestFlight ship
    again. Driven directly (not via the background task) for determinism.
    """
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$2\" == \"--validate-app\" ]]; then echo 'No errors validating'; exit 0; fi\n"
        "if [[ \"$2\" == \"--upload-app\" ]]; then echo 'Asset received id BUILD99'; exit 0; fi\n"
        "exit 1\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")

    workspace = tmp_path / "ws"

    recorded_llm.script = [
        LLMResponse(text=f"agent {i} done.", tool_calls=[], stop_reason="end_turn")
        for i in range(8)
    ]
    src = BuildJob(spec=AppSpec(title="Tracker", prompt="Build a tracker."))
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
    )
    src_session = await SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config).execute(src)
    assert src_session.job.state.value == "succeeded"

    new_job = BuildJob(spec=src.spec.model_copy(
        update={"prompt": src.spec.prompt + "\n--- REVISION ---\nAdd a weekly view."}))
    revised = Session.open(new_job, workspace)
    _seed_workspace(src_session.workspace, revised.workspace)
    (revised.workspace / "Build.ipa").write_text("fresh binary")
    revised.checkpoint("after-architect")
    revised.save()

    recorded_llm.script = [
        LLMResponse(text=f"rev {i} done.", tool_calls=[], stop_reason="end_turn")
        for i in range(7)
    ]
    ship_cfg = ShipConfig(
        ipa_path="Build.ipa",
        bundle_id="com.codegenie.tracker",
        apple_id="dev@example.com",
        app_specific_password="abcd-efgh-ijkl-mnop",
        poll_after_upload=False,
    )
    ship_config = dataclasses.replace(config, ship=ship_cfg)

    events: list[str] = []
    stream = await bus.stream_for(new_job.id)

    async def collect():
        async for ev in stream.subscribe():
            events.append(ev.type)
            if ev.type == "job.state" and ev.payload.get("state") == "succeeded":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    revised_session = await SwarmOrchestrator(llm=recorded_llm, bus=bus, config=ship_config).resume(new_job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert revised_session.job.state.value == "succeeded"
    assert "testflight.upload" in events
