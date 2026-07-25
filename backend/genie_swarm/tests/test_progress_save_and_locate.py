"""Tests that the orchestrator actively communicates WHERE the app is.

Covers:
  - job.workspace is populated on success
  - artifact SSE event is emitted with file count and title
  - done event includes file_count and title
  - job.state succeeded event includes file_count
  - session checkpoint persists and restores correctly
  - session restore rolls back to checkpoint state
"""
import asyncio
import pytest
from pathlib import Path
from ..models import BuildJob, AppSpec, JobState
from ..orchestrator import SwarmOrchestrator, SwarmConfig
from ..streaming import EventBus


def _make_job(title="TestApp"):
    return BuildJob(spec=AppSpec(title=title, prompt="a simple test app"))


async def _collect_events(stream, stop_on="done"):
    received = []
    async def _drain():
        async for ev in stream.subscribe():
            received.append(ev)
            if ev.type == stop_on:
                break
    task = asyncio.create_task(_drain())
    await asyncio.sleep(0.01)
    return received, task


def _orch(tmp_path, recorded_llm):
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=True,
    )
    return SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config), bus


@pytest.mark.asyncio
async def test_success_populates_workspace_field(tmp_path, recorded_llm):
    """On success, job.workspace should be non-None."""
    orch, bus = _orch(tmp_path, recorded_llm)
    job = _make_job()
    stream = await bus.stream_for(job.id)
    received, consumer = await _collect_events(stream)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.workspace is not None, (
        "job.workspace must be populated on success"
    )
    assert session.job.state == JobState.succeeded


@pytest.mark.asyncio
async def test_success_emits_artifact_event(tmp_path, recorded_llm):
    """The orchestrator must emit an 'artifact' SSE event on success."""
    orch, bus = _orch(tmp_path, recorded_llm)
    job = _make_job("ArtifactApp")
    stream = await bus.stream_for(job.id)
    received, consumer = await _collect_events(stream)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    artifact_events = [e for e in received if e.type == "artifact"]
    assert len(artifact_events) == 1, (
        "Exactly one artifact event should be emitted on success"
    )
    ae = artifact_events[0]
    assert ae.payload["title"] == "ArtifactApp"
    assert ae.payload["job_id"] == job.id
    assert "file_count" in ae.payload
    assert isinstance(ae.payload["file_count"], int)


@pytest.mark.asyncio
async def test_done_event_includes_file_info(tmp_path, recorded_llm):
    """The 'done' event should include file_count and title."""
    orch, bus = _orch(tmp_path, recorded_llm)
    job = _make_job("DoneApp")
    stream = await bus.stream_for(job.id)
    received, consumer = await _collect_events(stream)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    done_events = [e for e in received if e.type == "done"]
    assert len(done_events) == 1
    de = done_events[0]
    assert de.payload["success"] is True
    assert "file_count" in de.payload
    assert de.payload["title"] == "DoneApp"


@pytest.mark.asyncio
async def test_succeeded_state_includes_file_count(tmp_path, recorded_llm):
    """The job.state=succeeded event should include file_count."""
    orch, bus = _orch(tmp_path, recorded_llm)
    job = _make_job()
    stream = await bus.stream_for(job.id)
    received, consumer = await _collect_events(stream)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    state_events = [
        e for e in received
        if e.type == "job.state" and e.payload.get("state") == "succeeded"
    ]
    assert len(state_events) == 1
    assert "file_count" in state_events[0].payload


@pytest.mark.asyncio
async def test_summary_mentions_file_count(tmp_path, recorded_llm):
    """The job summary should mention the file count."""
    orch, bus = _orch(tmp_path, recorded_llm)
    job = _make_job("CountApp")
    stream = await bus.stream_for(job.id)
    received, consumer = await _collect_events(stream)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert "files" in session.job.summary.lower(), (
        "Summary should mention file count"
    )


@pytest.mark.asyncio
async def test_checkpoint_round_trip(tmp_path):
    """Checkpoints persist to disk and reload correctly."""
    from ..session import Session

    ws_root = tmp_path / "ws"
    job = BuildJob(spec=AppSpec(title="CheckpointApp", prompt="test"))
    session = Session.open(job, ws_root)

    test_file = session.workspace / "main.swift"
    test_file.write_text("import SwiftUI")

    cp = session.checkpoint("after-architect")
    assert cp.files_snapshot.get("main.swift") == "import SwiftUI"

    loaded = Session.load(ws_root, job.id)
    assert len(loaded.checkpoints) == 1
    assert loaded.checkpoints[0].label == "after-architect"
    assert "main.swift" in loaded.checkpoints[0].files_snapshot


@pytest.mark.asyncio
async def test_restore_removes_post_checkpoint_files(tmp_path):
    """Restoring a checkpoint removes files added after it."""
    from ..session import Session

    ws_root = tmp_path / "ws"
    job = BuildJob(spec=AppSpec(title="RestoreApp", prompt="test"))
    session = Session.open(job, ws_root)

    (session.workspace / "original.swift").write_text("original")
    cp = session.checkpoint("v1")

    (session.workspace / "added_later.swift").write_text("later")
    assert (session.workspace / "added_later.swift").exists()

    session.restore(cp)
    assert not (session.workspace / "added_later.swift").exists(), (
        "Files added after the checkpoint should be removed on restore"
    )
    assert (session.workspace / "original.swift").read_text() == "original"
