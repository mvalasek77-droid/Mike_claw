"""Workspace rotation + streaming ship-stage tests."""
from __future__ import annotations

import asyncio
import os
import time
import zipfile
from pathlib import Path

import pytest

from genie_swarm.archive import archive_old_workspaces
from genie_swarm.llm import LLMResponse
from genie_swarm.memory import Memory
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import ShipConfig, SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


# --------------------------------------------------------------------------- #
# Archive rotation
# --------------------------------------------------------------------------- #

def _seed_job(root: Path, job_id: str, mtime: float) -> Path:
    """Create a fake job workspace with a session JSON whose mtime we pin."""
    ws = root / job_id
    ws.mkdir(parents=True)
    (ws / "App.swift").write_text("// app")
    sess = ws / ".genie-session.json"
    sess.write_text("{}")
    os.utime(sess, (mtime, mtime))
    return ws


def test_archive_old_workspaces_skips_recent(tmp_path: Path):
    """A workspace touched within the cutoff stays put."""
    now = time.time()
    _seed_job(tmp_path, "fresh", mtime=now - 60)   # 1 minute ago
    results = archive_old_workspaces(
        tmp_path, older_than_seconds=24 * 60 * 60, now=now,
    )
    assert results == []
    assert (tmp_path / "fresh").is_dir()


def test_archive_old_workspaces_zips_old(tmp_path: Path):
    """A workspace older than the cutoff gets zipped + removed."""
    now = time.time()
    _seed_job(tmp_path, "stale", mtime=now - 10 * 24 * 60 * 60)  # 10 days ago
    results = archive_old_workspaces(
        tmp_path, older_than_seconds=24 * 60 * 60, now=now,
    )
    assert len(results) == 1
    summary = results[0]
    assert summary.job_id == "stale"
    assert Path(summary.archive_path).exists()
    assert summary.files_archived >= 2   # App.swift + .genie-session.json
    assert not (tmp_path / "stale").exists()

    # The zip actually contains the files.
    with zipfile.ZipFile(summary.archive_path) as zf:
        names = set(zf.namelist())
        assert "App.swift" in names
        assert ".genie-session.json" in names


def test_archive_old_workspaces_skips_active_jobs(tmp_path: Path):
    """Even if old, an active job id is left alone."""
    now = time.time()
    _seed_job(tmp_path, "active", mtime=now - 10 * 24 * 60 * 60)
    results = archive_old_workspaces(
        tmp_path, older_than_seconds=24 * 60 * 60, now=now,
        active_job_ids={"active"},
    )
    assert results == []
    assert (tmp_path / "active").is_dir()


def test_archive_old_workspaces_skips_non_sessions(tmp_path: Path):
    """Dirs without .genie-session.json aren't considered job
    workspaces (e.g. user-dropped scratch)."""
    scratch = tmp_path / "scratch"
    scratch.mkdir()
    (scratch / "notes.md").write_text("hello")
    os.utime(scratch / "notes.md", (time.time() - 365 * 24 * 60 * 60,) * 2)
    results = archive_old_workspaces(tmp_path)
    assert results == []
    assert scratch.is_dir()


def test_archive_old_workspaces_logs_to_memory(tmp_path: Path):
    """The archive helper notes a decision against the job in Memory
    so the iOS crash log / future history can surface it."""
    now = time.time()
    _seed_job(tmp_path, "archive_me", mtime=now - 10 * 24 * 60 * 60)
    archive_old_workspaces(tmp_path, older_than_seconds=60, now=now)
    mem = Memory(tmp_path)
    decisions = mem.decisions_for("archive_me")
    assert any("archive" in d.context.lower() for d in decisions)


# --------------------------------------------------------------------------- #
# Streaming TestFlight upload
# --------------------------------------------------------------------------- #

@pytest.fixture
def fake_xcrun_streaming(tmp_path: Path, monkeypatch) -> Path:
    """`xcrun altool` that emits five distinct progress lines on stdout
    so the streaming reader produces one event per line."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "echo 'Preparing for upload'\n"
        "echo 'Authenticating'\n"
        "echo 'Generating checksum'\n"
        "echo 'Uploading bytes'\n"
        "echo 'Asset received with id ABC123'\n"
        "exit 0\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    return bin_dir


@pytest.mark.asyncio
async def test_ship_stage_emits_progress_lines(tmp_path: Path, recorded_llm,
                                                fake_xcrun_streaming, monkeypatch):
    """Every stdout line from altool surfaces as a
    testflight.upload.progress event with the right `phase`."""
    workspace = tmp_path / "ws"
    workspace.mkdir()
    job_dir = workspace / "job_ship"
    job_dir.mkdir()
    (job_dir / "Build.ipa").write_text("fake")

    recorded_llm.script = [
        LLMResponse(text=f"agent {i}", tool_calls=[], stop_reason="end_turn")
        for i in range(8)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        max_retries=0, max_crash_recoveries=0,
        ship=ShipConfig(
            ipa_path="Build.ipa",
            bundle_id="com.codegenie.demo",
            apple_id="x@y.com",
            app_specific_password="abcd-efgh",
            poll_after_upload=False,
        ),
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(id="job_ship", spec=AppSpec(title="Streamy", prompt="x"))

    progress: list[dict] = []
    summary: list[bool] = []
    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "testflight.upload.progress":
                progress.append(dict(ev.payload))
            elif ev.type == "testflight.upload":
                summary.append(bool(ev.payload.get("ok")))
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    # 5 validate lines + 5 upload lines.
    phases = [p["phase"] for p in progress]
    assert phases.count("validate") == 5
    assert phases.count("upload") == 5
    assert "Asset received with id ABC123" in {p["line"] for p in progress}
    assert summary == [True]


@pytest.mark.asyncio
async def test_ship_stage_no_progress_when_validate_fails(tmp_path: Path, recorded_llm,
                                                          monkeypatch):
    """Validate-side failure short-circuits upload — no upload-phase
    progress fires."""
    bin_dir = tmp_path / "failbin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "echo 'Validating'\n"
        "echo 'ERROR ITMS-90161 Invalid profile' 1>&2\n"
        "exit 1\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")

    workspace = tmp_path / "ws2"
    (workspace / "job_x").mkdir(parents=True)
    (workspace / "job_x" / "Build.ipa").write_text("fake")

    recorded_llm.script = [
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn")
        for _ in range(8)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False,
        max_retries=0, max_crash_recoveries=0,
        ship=ShipConfig(
            ipa_path="Build.ipa", bundle_id="com.codegenie.demo",
            apple_id="x@y.com", app_specific_password="abcd",
            poll_after_upload=False,
        ),
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(id="job_x", spec=AppSpec(title="FailUp", prompt="x"))

    progress: list[dict] = []
    summary: list[bool] = []
    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "testflight.upload.progress":
                progress.append(dict(ev.payload))
            elif ev.type == "testflight.upload":
                summary.append(bool(ev.payload.get("ok")))
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    phases = {p["phase"] for p in progress}
    assert phases == {"validate"}     # upload never started
    assert summary == [False]
