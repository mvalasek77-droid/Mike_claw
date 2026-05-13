"""Ship-stage orchestrator tests.

The ship stage is opt-in (`SwarmConfig.ship`). When set, after the
test layer succeeds the orchestrator calls `testflight_upload`
directly (no LLM round-trip — it's a deterministic call) and, if ASC
API key creds are present, spawns the status poller. This module
verifies the whole loop with a fake `xcrun` and a fake `http_get`.
"""
from __future__ import annotations

import asyncio
import os
from pathlib import Path

import pytest

from genie_swarm import testflight_status as ts
from genie_swarm.agents import ALL_AGENTS
from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import ShipConfig, SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


@pytest.fixture
def fake_xcrun_ok(tmp_path: Path, monkeypatch) -> Path:
    """Stub `xcrun altool` so validate + upload both succeed."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$2\" == \"--validate-app\" ]]; then echo 'No errors validating'; exit 0; fi\n"
        "if [[ \"$2\" == \"--upload-app\" ]]; then\n"
        "  echo 'No errors uploading'\n"
        "  echo 'Asset received with id BUILD42'\n"
        "  exit 0\n"
        "fi\n"
        "exit 1\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    return bin_dir


def _no_op_script_for_8_agents() -> list[LLMResponse]:
    return [
        LLMResponse(text=f"{a.title} done.", tool_calls=[], stop_reason="end_turn")
        for a in ALL_AGENTS
    ]


# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_ship_stage_uploads_and_polls(tmp_path: Path, recorded_llm,
                                            fake_xcrun_ok, monkeypatch):
    """Full happy path: agents finish, ship config kicks in, upload
    succeeds, poller emits a state event, ASC marks VALID, done."""
    monkeypatch.setenv("APPLE_ID", "x@y.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "abcd-efgh")

    workspace = tmp_path / "ws"
    workspace.mkdir()
    job_dir = workspace / "job_test"
    job_dir.mkdir()
    (job_dir / "Build.ipa").write_text("fake binary")
    (job_dir / "ascKey.p8").write_text("(stub)")

    recorded_llm.script = _no_op_script_for_8_agents()
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False, max_retries=0,
        ship=ShipConfig(
            ipa_path="Build.ipa",
            bundle_id="com.codegenie.demo",
            asc_api_key_id="ABCD12",
            asc_api_issuer_id="0000-0000",
            asc_api_key_path="ascKey.p8",
            poll_interval_s=0.0,
            poll_timeout_s=2.0,
        ),
    )

    # Inject a fake http_get that returns a single VALID response.
    async def fake_http(url: str, jwt: str):
        return {
            "data": [{
                "id": "BUILD42",
                "attributes": {
                    "processingState": "VALID",
                    "version": "1.0",
                    "buildNumber": "1",
                },
            }]
        }
    real_watch = ts.watch
    async def watch_with_fake(cfg, evs, **kw):
        return await real_watch(cfg, evs, http_get=fake_http)
    monkeypatch.setattr(ts, "watch", watch_with_fake)

    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(id="job_test", spec=AppSpec(title="X", prompt="x"))

    received: list[str] = []
    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            received.append(ev.type)
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.state.value == "succeeded"
    assert "testflight.upload" in received
    assert "testflight.status" in received


@pytest.mark.asyncio
async def test_ship_stage_skips_polling_when_no_asc_creds(tmp_path: Path, recorded_llm,
                                                          fake_xcrun_ok, monkeypatch):
    """Without ASC API key creds, upload still runs but poller emits
    POLL_SKIPPED so the user knows why no status updates are coming."""
    monkeypatch.setenv("APPLE_ID", "x@y.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "abcd")

    workspace = tmp_path / "ws"
    (workspace / "job_x").mkdir(parents=True)
    (workspace / "job_x" / "Build.ipa").write_text("fake")

    recorded_llm.script = _no_op_script_for_8_agents()
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False, max_retries=0,
        ship=ShipConfig(
            ipa_path="Build.ipa",
            bundle_id="com.codegenie.demo",
            apple_id="x@y.com",
            app_specific_password="abcd",
        ),
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(id="job_x", spec=AppSpec(title="X", prompt="x"))

    statuses: list[str] = []
    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "testflight.status":
                statuses.append(ev.payload.get("state", ""))
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.state.value == "succeeded"
    assert statuses == ["POLL_SKIPPED"]


@pytest.mark.asyncio
async def test_ship_stage_records_failure_without_killing_job(tmp_path: Path, recorded_llm,
                                                              monkeypatch):
    """If the upload fails, the job still reaches succeeded (the build
    was made; only the ship step broke) and the failure is logged in
    Memory so the user can investigate."""
    bin_dir = tmp_path / "failbin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text("#!/usr/bin/env bash\necho 'ITMS-90161 invalid' 1>&2\nexit 1\n")
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    monkeypatch.setenv("APPLE_ID", "x@y.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "abcd")

    workspace = tmp_path / "ws"
    (workspace / "job_y").mkdir(parents=True)
    (workspace / "job_y" / "Build.ipa").write_text("fake")

    recorded_llm.script = _no_op_script_for_8_agents()
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=workspace,
        parallel_build=False, parallel_test=False, max_retries=0,
        ship=ShipConfig(
            ipa_path="Build.ipa", bundle_id="com.codegenie.demo",
            apple_id="x@y.com", app_specific_password="abcd",
            poll_after_upload=False,
        ),
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(id="job_y", spec=AppSpec(title="X", prompt="x"))

    upload_oks: list[bool] = []
    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "testflight.upload":
                upload_oks.append(ev.payload.get("ok", False))
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    # Build itself stayed green; ship failed but didn't crash the run.
    assert session.job.state.value == "succeeded"
    assert upload_oks == [False]

    # Memory should have recorded the failure as a decision.
    decisions = orch.memory.decisions_for(job.id)
    # The orchestrator may log this as a validate- OR upload-phase
    # failure depending on which altool call broke. Either is fine.
    assert any(
        "upload failed" in d.decision.lower() or "validate failed" in d.decision.lower()
        for d in decisions
    )
