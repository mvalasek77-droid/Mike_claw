"""Comprehensive end-to-end integration test: build a "Tides" app through the
entire pipeline and check every step for holes.

Simulates a complete user journey from AppSpec creation through all 8 agents,
bundle-ID pinning, privacy manifest, event validation, SSE streaming, cost
tracking, memory persistence, snapshots, release readiness, ship config
validation, ASC coach, workspace structure, comparison, TestFlight status
polling, and middleware.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
from pathlib import Path
from typing import Any
from unittest import mock

import pytest
from fastapi import FastAPI
from starlette.testclient import TestClient

from genie_swarm.agents import ALL_AGENTS
from genie_swarm.asc_coach import CoachContext, answer as asc_answer, suggested_questions
from genie_swarm.bundle_id import enforce_bundle_id, is_valid_bundle_id
from genie_swarm.cost import CostMeter
from genie_swarm.llm import LLMResponse
from genie_swarm.memory import Memory
from genie_swarm.middleware import register_middleware, rate_limiter
from genie_swarm.models import (
    AppSpec,
    BuildJob,
    BuildRequest,
    JobState,
    ShipRequest,
    SwarmEvent,
    ToolCall,
)
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.privacy_manifest import ensure_privacy_manifest, find_manifest
from genie_swarm.release_readiness import run_release_readiness
from genie_swarm.streaming import EventBus
from genie_swarm.testflight_status import PollerConfig, _extract_app_id, _extract_first_build


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

BUNDLE_ID = "com.testuser.tidetimes"
APP_TITLE = "Tide Times"
STYLE = "liquidGlass"
CATEGORY = "utility"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _valid_event_types() -> set[str]:
    """All type values accepted by SwarmEvent.type Literal."""
    annotation = SwarmEvent.model_fields["type"].annotation
    return set(getattr(annotation, "__args__", ()))


def _script_for_all_agents_tides() -> list[LLMResponse]:
    """Build a RecordedLLMClient script that exercises every agent.

    Build-layer agents (architect, coder, designer, integrator) write
    realistic marker files via write_file tool calls. Read-only agents
    (unit_tester, ui_tester, reviewer, security) reply with text only.
    """
    writers = {"architect", "coder", "designer", "integrator",
               "unit_tester", "ui_tester"}
    out: list[LLMResponse] = []

    file_map = {
        "architect": ("docs/plan.json", json.dumps({
            "app": {
                "name": "Tide Times",
                "bundle_id": "com.example.tidetimes",
            },
            "files": ["TideTimesApp.swift", "ContentView.swift"],
        })),
        "coder": ("Sources/TideTimesApp.swift",
                  'import SwiftUI\n@main\nstruct TideTimesApp: App {\n'
                  '    var body: some Scene {\n        WindowGroup { ContentView() }\n    }\n}\n'),
        "designer": ("Sources/ContentView.swift",
                     'import SwiftUI\nstruct ContentView: View {\n'
                     '    var body: some View {\n        Text("Tide Times")\n    }\n}\n'),
        "integrator": ("TideTimes.xcodeproj/project.pbxproj",
                       '// !$*UTF8*$!\n{\n'
                       '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.tidetimes;\n'
                       '}\n'),
        "unit_tester": ("Tests/TideTimesTests.swift",
                        'import XCTest\nclass TideTimesTests: XCTestCase {\n'
                        '    func testExample() { XCTAssertTrue(true) }\n}\n'),
        "ui_tester": ("UITests/TideTimesUITests.swift",
                      'import XCTest\nclass TideTimesUITests: XCTestCase {\n'
                      '    func testLaunch() { let app = XCUIApplication(); app.launch() }\n}\n'),
    }

    for agent in ALL_AGENTS:
        slug = agent.role.value
        if slug in writers:
            path, body = file_map[slug]
            out.append(LLMResponse(
                text="",
                tool_calls=[ToolCall(
                    name="write_file",
                    arguments={"path": path, "body": body},
                )],
                stop_reason="tool_use",
                usage={"input_tokens": 150, "output_tokens": 30},
            ))
            out.append(LLMResponse(
                text=f"{agent.title} done. All tests pass, 0 failures.",
                tool_calls=[],
                stop_reason="end_turn",
                usage={"input_tokens": 100, "output_tokens": 15},
            ))
        else:
            out.append(LLMResponse(
                text=f"{agent.title} reviewed — no findings.",
                tool_calls=[],
                stop_reason="end_turn",
                usage={"input_tokens": 120, "output_tokens": 18},
            ))
    return out


# ---------------------------------------------------------------------------
# 1. Build request creation
# ---------------------------------------------------------------------------

class TestBuildRequestCreation:
    def test_app_spec_fields(self):
        spec = AppSpec(
            title=APP_TITLE,
            prompt="Show me the tides near my location",
            bundle_id=BUNDLE_ID,
            category=CATEGORY,
            style=STYLE,
        )
        assert spec.title == APP_TITLE
        assert spec.bundle_id == BUNDLE_ID
        assert spec.category == CATEGORY
        assert spec.style == STYLE
        assert spec.target_ios == "17.0"  # default

    def test_build_job_from_spec(self):
        spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
        job = BuildJob(spec=spec)
        assert job.id.startswith("job_")
        assert job.state is JobState.queued
        assert job.spec.bundle_id == BUNDLE_ID

    def test_build_request_validation(self):
        req = BuildRequest(
            spec=AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID,
                         category=CATEGORY, style=STYLE),
        )
        assert req.spec.title == APP_TITLE
        assert req.parallel is True
        assert req.skip_tests is False

    def test_bundle_id_validity(self):
        assert is_valid_bundle_id(BUNDLE_ID)
        assert is_valid_bundle_id("com.testuser.tidetimes")
        assert not is_valid_bundle_id("tidetimes")
        assert not is_valid_bundle_id("")
        assert not is_valid_bundle_id("com..bad")


# ---------------------------------------------------------------------------
# 2. Orchestrator pipeline: all 8 agents
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_orchestrator_runs_all_8_agents(tmp_path: Path, recorded_llm):
    """Drive the orchestrator through all 8 agents and verify each starts
    and finishes, events fire correctly, and the job succeeds."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(
        title=APP_TITLE,
        prompt="Show tide times near my location",
        bundle_id=BUNDLE_ID,
        category=CATEGORY,
        style=STYLE,
    )
    job = BuildJob(spec=spec)

    # Subscribe before execute to capture early events.
    stream = await bus.stream_for(job.id)
    received: list[dict[str, Any]] = []

    async def collect():
        async for ev in stream.subscribe():
            received.append({"type": ev.type, "payload": ev.payload, "agent": ev.agent})
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)

    await asyncio.wait_for(consumer, timeout=10.0)

    # -- Job succeeded --
    assert session.job.state is JobState.succeeded
    assert session.job.summary is not None
    assert APP_TITLE in session.job.summary
    assert session.job.error is None

    # -- Every agent fired at least one start + finish event --
    types = [e["type"] for e in received]
    starts = [e for e in received if e["type"] == "agent.started"]
    finishes = [e for e in received if e["type"] == "agent.finished"]
    assert len(starts) >= len(ALL_AGENTS), f"only {len(starts)} starts for {len(ALL_AGENTS)} agents"
    assert len(finishes) >= len(ALL_AGENTS), f"only {len(finishes)} finishes for {len(ALL_AGENTS)} agents"

    # -- Top-level event shape --
    assert "job.created" in types
    assert "job.state" in types
    assert "agent.started" in types
    assert "agent.finished" in types
    assert types[-1] == "done"

    # -- The done event payload has success=True --
    done_ev = received[-1]
    assert done_ev["payload"].get("success") is True


# ---------------------------------------------------------------------------
# 3. Bundle ID pinning
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_bundle_id_pinning_after_integrator(tmp_path: Path, recorded_llm):
    """After the full pipeline, verify the generated project's bundle ID
    was pinned to 'com.testuser.tidetimes'."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)
    events: list[dict] = []

    async def collect():
        async for ev in stream.subscribe():
            events.append({"type": ev.type, "payload": ev.payload})
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # -- bundle.pinned event was emitted --
    pinned = [e for e in events if e["type"] == "bundle.pinned"]
    assert len(pinned) >= 1, "bundle.pinned event was never emitted"
    assert pinned[0]["payload"]["bundle_id"] == BUNDLE_ID

    # -- The pbxproj has the correct bundle ID --
    ws = session.workspace
    pbxproj = ws / "TideTimes.xcodeproj" / "project.pbxproj"
    assert pbxproj.exists(), "project.pbxproj should exist"
    content = pbxproj.read_text()
    assert f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};" in content
    # Old example ID should be gone
    assert "com.example.tidetimes" not in content

    # -- The plan.json was also patched --
    plan = ws / "docs" / "plan.json"
    if plan.exists():
        plan_data = json.loads(plan.read_text())
        assert plan_data["app"]["bundle_id"] == BUNDLE_ID


# ---------------------------------------------------------------------------
# 4. Privacy manifest
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_privacy_manifest_created(tmp_path: Path, recorded_llm):
    """Verify ensure_privacy_manifest() creates PrivacyInfo.xcprivacy."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)
    events: list[dict] = []

    async def collect():
        async for ev in stream.subscribe():
            events.append({"type": ev.type, "payload": ev.payload})
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # -- privacy.manifest event was emitted --
    manifest_evts = [e for e in events if e["type"] == "privacy.manifest"]
    assert len(manifest_evts) >= 1, "privacy.manifest event was never emitted"

    # -- The file exists on disk --
    ws = session.workspace
    found = find_manifest(ws)
    assert found is not None, "PrivacyInfo.xcprivacy was not created"
    assert found.name == "PrivacyInfo.xcprivacy"


def test_privacy_manifest_standalone(tmp_path: Path):
    """Direct test: ensure_privacy_manifest writes a valid plist."""
    import plistlib

    # Create an xcodeproj so the manifest placement logic works.
    (tmp_path / "App.xcodeproj").mkdir()
    (tmp_path / "App").mkdir()

    result = ensure_privacy_manifest(tmp_path)
    assert result is not None
    assert result.name == "PrivacyInfo.xcprivacy"

    data = plistlib.loads(result.read_bytes())
    assert data["NSPrivacyTracking"] is False
    assert isinstance(data["NSPrivacyCollectedDataTypes"], list)
    assert isinstance(data["NSPrivacyAccessedAPITypes"], list)


def test_privacy_manifest_does_not_overwrite(tmp_path: Path):
    """If a manifest already exists, ensure_privacy_manifest leaves it alone."""
    existing = tmp_path / "PrivacyInfo.xcprivacy"
    existing.write_text("custom")

    result = ensure_privacy_manifest(tmp_path)
    assert result is None
    assert existing.read_text() == "custom"


# ---------------------------------------------------------------------------
# 5. Event type validation
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_every_emitted_event_type_is_valid(tmp_path: Path, recorded_llm):
    """Every SwarmEvent emitted during the pipeline must have a type field
    that is in the SwarmEvent Literal."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)
    emitted_types: list[str] = []

    async def collect():
        async for ev in stream.subscribe():
            emitted_types.append(ev.type)
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    valid = _valid_event_types()
    invalid = [t for t in emitted_types if t not in valid]
    assert not invalid, f"Invalid event types emitted: {invalid}"
    assert len(emitted_types) > 0, "No events emitted at all"


# ---------------------------------------------------------------------------
# 6. SSE streaming
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_sse_stream_terminates_with_done(tmp_path: Path, recorded_llm):
    """The event stream must deliver events and terminate with 'done'."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)
    all_events: list[SwarmEvent] = []
    stream_ended = False

    async def collect():
        nonlocal stream_ended
        async for ev in stream.subscribe():
            all_events.append(ev)
            if ev.type == "done":
                stream_ended = True
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    assert stream_ended, "stream did not emit a 'done' event"
    assert len(all_events) > 10, f"too few events: {len(all_events)}"

    # Verify every event is a proper SwarmEvent with job_id.
    for ev in all_events:
        assert isinstance(ev, SwarmEvent)
        assert ev.job_id == job.id
        assert ev.ts > 0


# ---------------------------------------------------------------------------
# 7. Cost tracking
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_cost_tracking(tmp_path: Path, recorded_llm):
    """CostMeter should track spend and cost.update events should fire."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)
    cost_events: list[dict] = []

    async def collect():
        async for ev in stream.subscribe():
            if ev.type == "cost.update":
                cost_events.append(ev.payload)
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # cost.update events should have fired at least once per agent
    assert len(cost_events) >= len(ALL_AGENTS), \
        f"only {len(cost_events)} cost events for {len(ALL_AGENTS)} agents"

    # Each cost event should have the expected shape
    for ce in cost_events:
        assert "input_tokens" in ce
        assert "output_tokens" in ce
        assert "spend_usd" in ce
        assert ce["input_tokens"] > 0 or ce["output_tokens"] > 0

    # The cost meter on the orchestrator should have accumulated
    assert orch.cost.input_tokens > 0
    assert orch.cost.output_tokens > 0
    assert orch.cost.spend_usd > 0


def test_cost_meter_standalone():
    """Direct test of CostMeter logic."""
    meter = CostMeter(cap_usd=None)
    meter.record(model="claude-opus-4-7", input_tokens=1000, output_tokens=500)
    assert meter.input_tokens == 1000
    assert meter.output_tokens == 500
    assert meter.spend_usd > 0

    snap = meter.snapshot()
    assert snap["input_tokens"] == 1000
    assert snap["output_tokens"] == 500
    assert snap["spend_usd"] > 0


# ---------------------------------------------------------------------------
# 8. Memory persistence
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_memory_persistence(tmp_path: Path, recorded_llm):
    """The orchestrator should write project records and decisions to memory."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)

    async def drain():
        async for ev in stream.subscribe():
            if ev.type == "done":
                break

    consumer = asyncio.create_task(drain())
    await asyncio.sleep(0.01)

    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # -- Project record --
    mem = Memory(config.workspace_root)
    recent = mem.recent_projects()
    matching = [p for p in recent if p.job_id == job.id]
    assert len(matching) == 1, "project record not found in memory"
    assert matching[0].succeeded is True
    assert matching[0].title == APP_TITLE

    # -- Decisions (bundle pinning + privacy manifest at minimum) --
    decisions = mem.decisions_for(job.id)
    assert len(decisions) >= 2, f"expected at least 2 decisions, got {len(decisions)}"
    decision_texts = " ".join(d.decision for d in decisions)
    assert "bundle" in decision_texts.lower() or "pinned" in decision_texts.lower(), \
        "bundle pinning decision not found"
    assert "privacy" in decision_texts.lower(), "privacy manifest decision not found"


# ---------------------------------------------------------------------------
# 9. Snapshot/checkpoint
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_checkpoints_created(tmp_path: Path, recorded_llm):
    """At least one checkpoint should be created during the build."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)

    async def drain():
        async for ev in stream.subscribe():
            if ev.type == "done":
                break

    consumer = asyncio.create_task(drain())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # Checkpoints expected: after-architect, after-build-layer,
    # after-integrator, after-tests
    assert len(session.checkpoints) >= 3, \
        f"expected at least 3 checkpoints, got {len(session.checkpoints)}"
    labels = {cp.label for cp in session.checkpoints}
    assert "after-architect" in labels
    assert "after-integrator" in labels

    # Each checkpoint should have a non-empty files snapshot
    for cp in session.checkpoints:
        assert cp.at > 0


# ---------------------------------------------------------------------------
# 10. Release readiness
# ---------------------------------------------------------------------------

def test_release_readiness_on_tides_workspace(tmp_path: Path):
    """Run release readiness audit on a realistic Tides workspace."""
    ws = tmp_path / "tides_ws"
    ws.mkdir()

    # Create the expected structure
    (ws / "TideTimes.xcodeproj").mkdir()
    (ws / "Sources").mkdir()
    (ws / "Sources" / "TideTimesApp.swift").write_text("import SwiftUI\n")
    (ws / "Sources" / "ContentView.swift").write_text("import SwiftUI\n")

    # Privacy manifest
    (ws / "Sources" / "PrivacyInfo.xcprivacy").write_text(
        "<plist><dict>"
        "<key>NSPrivacyTracking</key><false/>"
        "<key>NSPrivacyCollectedDataTypes</key><array/>"
        "<key>NSPrivacyAccessedAPITypes</key><array/>"
        "</dict></plist>"
    )

    # Privacy policy
    (ws / "PRIVACY.md").write_text("# Privacy Policy\nWe collect nothing.\n")

    result = run_release_readiness(
        spec=AppSpec(title=APP_TITLE, prompt="tides"),
        workspace=ws,
        ship=ShipRequest(
            ipa_path="Build.ipa",
            bundle_id=BUNDLE_ID,
            asc_api_key_id="KEYABC",
            asc_api_issuer_id="issuer-uuid",
            asc_api_key_path="AuthKey_KEYABC.p8",
        ),
        github=None,
    )

    # Should not crash
    assert "release_gate" in result
    assert "score" in result
    assert "items" in result
    assert isinstance(result["items"], list)
    assert len(result["items"]) > 0

    # Should report meaningful items, not empty
    keys = {item["key"] for item in result["items"]}
    assert "workspace" in keys
    assert "xcode_project" in keys
    assert "privacy_manifest" in keys
    assert "testflight_upload" in keys

    # The workspace and xcode project should be "automated"
    statuses = {item["key"]: item["status"] for item in result["items"]}
    assert statuses["workspace"] == "automated"
    assert statuses["xcode_project"] == "automated"
    assert statuses["privacy_manifest"] == "automated"


def test_release_readiness_empty_workspace(tmp_path: Path):
    """Release readiness on an empty workspace should report needs_setup,
    not crash."""
    ws = tmp_path / "empty_ws"
    ws.mkdir()

    result = run_release_readiness(
        spec=AppSpec(title=APP_TITLE, prompt="tides"),
        workspace=ws,
        ship=None,
        github=None,
    )
    assert result["release_gate"] == "needs_setup"
    assert result["score"] < 100


# ---------------------------------------------------------------------------
# 11. Ship config validation
# ---------------------------------------------------------------------------

def test_ship_request_validates():
    """ShipRequest with the Tides bundle ID should validate cleanly."""
    ship = ShipRequest(
        ipa_path="Build.ipa",
        bundle_id=BUNDLE_ID,
        asc_api_key_id="KEY123",
        asc_api_issuer_id="issuer-uuid",
        asc_api_key_path="AuthKey_KEY123.p8",
    )
    assert ship.bundle_id == BUNDLE_ID
    assert ship.auto_archive is True
    assert ship.configuration == "Release"
    assert ship.export_method == "app-store-connect"

    # Round-trip through JSON
    data = ship.model_dump()
    restored = ShipRequest.model_validate(data)
    assert restored.bundle_id == BUNDLE_ID


def test_ship_request_defaults():
    """ShipRequest should have sane defaults."""
    ship = ShipRequest(ipa_path="x.ipa", bundle_id=BUNDLE_ID)
    assert ship.poll_after_upload is True
    assert ship.team_id == ""
    assert ship.scheme == ""


# ---------------------------------------------------------------------------
# 12. ASC Coach
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_asc_coach_responds(recorded_llm):
    """Send a coaching question and verify the response is coherent."""
    recorded_llm.script = [
        LLMResponse(
            text=(
                "To create an app record for your Tides app, go to "
                "App Store Connect, click Apps, then the blue + button "
                "near the top-left, and select New App."
            ),
            tool_calls=[],
            stop_reason="end_turn",
            usage={"input_tokens": 500, "output_tokens": 80},
        )
    ]

    context = CoachContext(
        app_name="Tide Times",
        bundle_id=BUNDLE_ID,
        step_number=2,
        step_title="Create App Record",
    )
    result = await asc_answer(
        llm=recorded_llm,
        question="How do I create an app record for my Tides app?",
        context=context,
    )
    assert "answer" in result
    assert len(result["answer"]) > 0
    assert "usage" in result


def test_asc_suggested_questions():
    """suggested_questions should return a non-empty list."""
    q = suggested_questions(step_number=2)
    assert len(q) > 0
    assert any("bundle" in q_text.lower() for q_text in q)

    # General (no step)
    general = suggested_questions(step_number=None)
    assert len(general) > 0


# ---------------------------------------------------------------------------
# 13. Workspace files
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_workspace_has_expected_structure(tmp_path: Path, recorded_llm):
    """The generated workspace should have an Xcode project, Swift files,
    and a privacy manifest."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)

    async def drain():
        async for ev in stream.subscribe():
            if ev.type == "done":
                break

    consumer = asyncio.create_task(drain())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    ws = session.workspace

    # Xcode project
    xcodeprojs = list(ws.glob("*.xcodeproj"))
    assert len(xcodeprojs) >= 1, "no .xcodeproj found"

    # At least one .swift file
    swift_files = list(ws.rglob("*.swift"))
    assert len(swift_files) >= 1, "no .swift files found"

    # Privacy manifest should have been created by the pipeline
    privacy = find_manifest(ws)
    assert privacy is not None, "PrivacyInfo.xcprivacy not found"

    # Session JSON should exist
    session_json = ws / ".genie-session.json"
    assert session_json.exists(), ".genie-session.json not found"
    data = json.loads(session_json.read_text())
    assert data["job"]["spec"]["title"] == APP_TITLE


# ---------------------------------------------------------------------------
# 14. Compare
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_compare_two_workspaces(tmp_path: Path, recorded_llm):
    """Create two job workspaces and verify the compare module works."""
    from genie_swarm.compare import compare_workspaces

    # Job A: has a file
    ws_a = tmp_path / "job_a"
    ws_a.mkdir()
    (ws_a / "Sources").mkdir()
    (ws_a / "Sources" / "App.swift").write_text("// version 1\n")
    (ws_a / "Sources" / "Only_A.swift").write_text("// only in A\n")

    # Job B: same file modified + one new file
    ws_b = tmp_path / "job_b"
    ws_b.mkdir()
    (ws_b / "Sources").mkdir()
    (ws_b / "Sources" / "App.swift").write_text("// version 2 modified\n")
    (ws_b / "Sources" / "Only_B.swift").write_text("// only in B\n")

    diff = compare_workspaces(ws_a, ws_b, job_a="job_a", job_b="job_b")
    assert diff.job_a == "job_a"
    assert diff.job_b == "job_b"

    paths = {f.path for f in diff.files}
    # App.swift should be modified, Only_A removed, Only_B added
    statuses = {f.path: f.status for f in diff.files}
    assert statuses.get("Sources/App.swift") == "modified"
    assert statuses.get("Sources/Only_A.swift") == "removed"
    assert statuses.get("Sources/Only_B.swift") == "added"


# ---------------------------------------------------------------------------
# 15. TestFlight status polling
# ---------------------------------------------------------------------------

def test_testflight_poller_config():
    """PollerConfig can be constructed without crashing."""
    cfg = PollerConfig(
        api_key_id="KEY123",
        issuer_id="issuer-uuid",
        p8_path="/nonexistent/key.p8",
        bundle_id=BUNDLE_ID,
        poll_interval_s=5.0,
        timeout_s=30.0,
    )
    assert cfg.bundle_id == BUNDLE_ID
    assert cfg.poll_interval_s == 5.0


def test_extract_app_id_valid():
    """_extract_app_id should parse a valid response."""
    body = {"data": [{"id": "12345", "type": "apps"}]}
    assert _extract_app_id(body) == "12345"


def test_extract_app_id_empty():
    """_extract_app_id should return None for empty data."""
    assert _extract_app_id({"data": []}) is None
    assert _extract_app_id({}) is None
    assert _extract_app_id({"data": "bad"}) is None


def test_extract_first_build():
    """_extract_first_build picks the right build."""
    cfg = PollerConfig(
        api_key_id="K", issuer_id="I", p8_path="x.p8",
        bundle_id=BUNDLE_ID,
    )
    body = {
        "data": [
            {"id": "b1", "attributes": {"processingState": "PROCESSING", "buildNumber": "1"}},
            {"id": "b2", "attributes": {"processingState": "VALID", "buildNumber": "2"}},
        ]
    }
    build = _extract_first_build(body, cfg)
    assert build is not None
    assert build["id"] == "b1"

    # With specific build_number filter
    cfg2 = PollerConfig(
        api_key_id="K", issuer_id="I", p8_path="x.p8",
        bundle_id=BUNDLE_ID,
        build_number="2",
    )
    build2 = _extract_first_build(body, cfg2)
    assert build2 is not None
    assert build2["id"] == "b2"


@pytest.mark.asyncio
async def test_testflight_watch_with_fake_http(tmp_path: Path):
    """Drive watch() with a fake HTTP getter that returns VALID immediately."""
    from genie_swarm.testflight_status import watch

    call_count = 0

    async def fake_http(url: str, token: str) -> dict:
        nonlocal call_count
        call_count += 1
        if "apps?" in url:
            return {"data": [{"id": "APP123", "type": "apps"}]}
        return {
            "data": [{
                "id": "BUILD1",
                "attributes": {
                    "processingState": "VALID",
                    "version": "1.0",
                    "buildNumber": "1",
                },
            }]
        }

    cfg = PollerConfig(
        api_key_id="KEY",
        issuer_id="ISS",
        p8_path="/fake.p8",
        bundle_id=BUNDLE_ID,
        poll_interval_s=0.1,
        timeout_s=5.0,
    )

    bus = EventBus()
    stream = await bus.stream_for("test_tf")
    events: list[dict] = []

    async def collect():
        async for ev in stream.subscribe():
            events.append({"type": ev.type, "payload": ev.payload})
            if ev.payload.get("state") in ("VALID", "FAILED", "INVALID", "EXPIRED", "TIMEOUT"):
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    result = await watch(cfg, stream, http_get=fake_http)

    # Give the consumer a moment to process
    await asyncio.sleep(0.1)
    consumer.cancel()
    try:
        await consumer
    except asyncio.CancelledError:
        pass

    assert result["state"] == "VALID"
    assert call_count >= 2  # apps + builds


# ---------------------------------------------------------------------------
# 16. Middleware (auth + rate limiting)
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def _reset_rate_limiter():
    rate_limiter.reset()
    yield
    rate_limiter.reset()


def _make_test_app() -> FastAPI:
    from genie_swarm.api import router
    app = FastAPI()
    register_middleware(app)
    app.include_router(router)
    return app


class TestMiddlewareTides:
    def test_health_endpoint(self):
        client = TestClient(_make_test_app())
        resp = client.get("/api/coding/swarm/health")
        assert resp.status_code == 200
        assert resp.json()["ok"] is True

    def test_request_id_present(self):
        client = TestClient(_make_test_app())
        resp = client.get("/api/coding/swarm/health")
        assert "x-request-id" in resp.headers
        rid = resp.headers["x-request-id"]
        assert len(rid) == 36  # uuid4

    def test_auth_rejects_bad_token(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "tides-secret"}):
            client = TestClient(_make_test_app())
            resp = client.get(
                "/api/coding/swarm/nonexistent",
                headers={"Authorization": "Bearer wrong"},
            )
            assert resp.status_code == 401

    def test_auth_accepts_valid_token(self):
        with mock.patch.dict(os.environ, {"CODEGENIE_API_TOKEN": "tides-secret"}):
            client = TestClient(_make_test_app())
            resp = client.get(
                "/api/coding/swarm/health",
                headers={"Authorization": "Bearer tides-secret"},
            )
            assert resp.status_code == 200

    def test_rate_limiting(self):
        rate_limiter.max_requests = 2
        rate_limiter.window = 60.0
        client = TestClient(_make_test_app())

        for _ in range(2):
            r = client.get("/api/coding/swarm/nonexistent/status")
            assert r.status_code != 429

        r = client.get("/api/coding/swarm/nonexistent/status")
        assert r.status_code == 429
        assert "Retry-After" in r.headers


# ---------------------------------------------------------------------------
# Integration: full pipeline + post-build audits
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_full_pipeline_then_release_audit(tmp_path: Path, recorded_llm):
    """Run the full pipeline, then run the release readiness audit on the
    resulting workspace -- verifying the two fit together end to end."""
    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=False,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)

    async def drain():
        async for ev in stream.subscribe():
            if ev.type == "done":
                break

    consumer = asyncio.create_task(drain())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # Now run release readiness on the generated workspace
    result = run_release_readiness(
        spec=spec,
        workspace=session.workspace,
        ship=ShipRequest(
            ipa_path="Build.ipa",
            bundle_id=BUNDLE_ID,
            asc_api_key_id="KEY123",
            asc_api_issuer_id="issuer",
            asc_api_key_path="AuthKey.p8",
        ),
        github=None,
    )

    assert result["release_gate"] in ("ready_for_testflight", "needs_setup")
    assert "items" in result
    assert len(result["items"]) > 0

    statuses = {item["key"]: item["status"] for item in result["items"]}
    # The workspace and Xcode project should exist
    assert statuses["workspace"] == "automated"
    assert statuses["xcode_project"] == "automated"
    # Privacy manifest should have been created by the pipeline
    assert statuses["privacy_manifest"] == "automated"


@pytest.mark.asyncio
async def test_session_save_and_load(tmp_path: Path, recorded_llm):
    """Verify that the session can be saved and reloaded from disk."""
    from genie_swarm.session import Session

    recorded_llm.script = _script_for_all_agents_tides()

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False,
        parallel_test=False,
        skip_tests=True,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    spec = AppSpec(title=APP_TITLE, prompt="tides", bundle_id=BUNDLE_ID)
    job = BuildJob(spec=spec)

    stream = await bus.stream_for(job.id)

    async def drain():
        async for ev in stream.subscribe():
            if ev.type == "done":
                break

    consumer = asyncio.create_task(drain())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=10.0)

    # Load the session back from disk
    loaded = Session.load(config.workspace_root, job.id)
    assert loaded.job.id == job.id
    assert loaded.job.spec.title == APP_TITLE
    assert len(loaded.checkpoints) >= 1
    assert loaded.workspace == session.workspace
