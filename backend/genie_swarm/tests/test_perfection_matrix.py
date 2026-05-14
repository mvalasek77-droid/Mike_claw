"""Perfection Matrix tests."""
from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router, state
from genie_swarm.memory import Memory
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.perfection import run_perfection_matrix


def _write_clean_workspace(root: Path, job_id: str = "job_green") -> Path:
    ws = root / job_id
    (ws / "Sources").mkdir(parents=True)
    (ws / "Resources" / "Assets.xcassets" / "AppIcon.appiconset").mkdir(parents=True)
    (ws / "Tests").mkdir()
    (ws / "Sources" / "DemoApp.swift").write_text(
        """
        import SwiftUI
        import CoreHaptics

        struct DemoAppView: View {
            @Environment(\\.accessibilityReduceMotion) private var reduceMotion

            var body: some View {
                Button {
                    withAnimation(reduceMotion ? nil : .spring()) { }
                } label: {
                    Text("Build")
                }
                .accessibilityLabel("Build the app")
            }
        }
        """,
        encoding="utf-8",
    )
    (ws / "Sources" / "OnboardingView.swift").write_text(
        """
        import SwiftUI

        struct OnboardingView: View {
            var body: some View {
                Text("A calm creative first launch")
                    .accessibilityLabel("A calm creative first launch")
            }
        }
        """,
        encoding="utf-8",
    )
    (ws / "Tests" / "DemoAppTests.swift").write_text(
        "import XCTest\nfinal class DemoAppTests: XCTestCase { func testSmoke() {} }\n",
        encoding="utf-8",
    )
    (ws / "Resources" / "Info.plist").write_text("<plist><dict></dict></plist>", encoding="utf-8")
    (ws / "Resources" / "PrivacyInfo.xcprivacy").write_text("{}", encoding="utf-8")
    (ws / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json").write_text(
        "{}",
        encoding="utf-8",
    )
    (ws / "Resources" / "AppStoreMetadata.json").write_text(
        """
        {
          "subtitle": "Calm creative progress",
          "description": "A focused habit app with a clear first-run payoff.",
          "keywords": ["calm", "habit", "create"],
          "screenshots": ["Screenshots/01-home.png", "Screenshots/02-success.png"]
        }
        """,
        encoding="utf-8",
    )
    (ws / "Resources" / "Screenshots" / "01-home.png.json").parent.mkdir(parents=True)
    (ws / "Resources" / "Screenshots" / "01-home.png.json").write_text("{}", encoding="utf-8")
    return ws


def test_perfection_matrix_green_workspace_is_ready(tmp_path: Path):
    ws = _write_clean_workspace(tmp_path)
    result = run_perfection_matrix(
        spec=AppSpec(
            title="Calm Builder",
            prompt="Build a focused habit app with onboarding, persistence, empty states, and offline mode.",
            features=["onboarding", "persistence", "offline"],
        ),
        workspace=ws,
        requested_probes=10_000,
        now=1_800_000_000,
    )

    assert result["probes_run"] == 10_000
    assert result["release_gate"] == "ready"
    assert result["score"] >= 98
    assert sum(axis["probes"] for axis in result["axes"]) == 10_000
    assert result["severity_counts"]["critical"] == 0


def test_perfection_matrix_blocks_missing_workspace(tmp_path: Path):
    result = run_perfection_matrix(
        spec=AppSpec(title="Ghost", prompt="tiny"),
        workspace=tmp_path / "missing",
        requested_probes=10_000,
        now=1_800_000_000,
    )

    assert result["release_gate"] == "blocked"
    assert result["severity_counts"]["critical"] >= 1
    assert any(f["title"] == "Workspace is missing" for f in result["findings"])


def test_perfection_matrix_finds_release_blockers(tmp_path: Path):
    ws = tmp_path / "job_bad"
    ws.mkdir()
    (ws / "BadView.swift").write_text(
        """
        import SwiftUI
        struct BadView: View {
            var body: some View {
                Button("Go") { print("debug"); fatalError("boom") }
            }
        }
        """,
        encoding="utf-8",
    )

    result = run_perfection_matrix(
        spec=AppSpec(title="Bad", prompt="make app"),
        workspace=ws,
        requested_probes=25_000,
        now=1_800_000_000,
    )

    assert result["probes_run"] == 25_000
    assert result["release_gate"] == "blocked"
    titles = {f["title"] for f in result["findings"]}
    assert "Privacy manifest missing" in titles
    assert "fatalError call found" in titles
    assert "First-run payoff is not explicit" in titles
    assert result["score"] < 80


def test_perfection_route_records_memory_decision(tmp_path: Path):
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    original_jobs = dict(state.jobs)
    original_tasks = dict(state.tasks)
    original_pause_events = dict(state.pause_events)
    original_decisions = dict(state.decisions)
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()
    state.tasks.clear()
    state.pause_events.clear()
    state.decisions.clear()

    job = BuildJob(
        id="job_route",
        spec=AppSpec(
            title="Route App",
            prompt="Build a route-tested app with clear onboarding and robust offline state.",
            features=["offline"],
        ),
    )
    state.jobs[job.id] = job
    _write_clean_workspace(tmp_path, job.id)

    try:
        client = TestClient(app)
        response = client.post(f"/api/coding/swarm/{job.id}/perfection", json={"probes": "bad"})
        assert response.status_code == 200
        body = response.json()
        assert body["release_gate"] == "ready"
        assert body["probes_run"] == 10_000

        decisions = Memory(tmp_path).decisions_for(job.id)
        assert any("perfection matrix" in d.context for d in decisions)
    finally:
        state.config = original_config
        state.jobs.clear()
        state.jobs.update(original_jobs)
        state.tasks.clear()
        state.tasks.update(original_tasks)
        state.pause_events.clear()
        state.pause_events.update(original_pause_events)
        state.decisions.clear()
        state.decisions.update(original_decisions)


@pytest.mark.parametrize("requested,expected", [(0, 1_000), (500, 1_000), (120_000, 100_000)])
def test_perfection_probe_budget_is_bounded(tmp_path: Path, requested: int, expected: int):
    ws = _write_clean_workspace(tmp_path)
    result = run_perfection_matrix(
        spec=AppSpec(title="Bounded", prompt="Build a safe app with tests and polish."),
        workspace=ws,
        requested_probes=requested,
        now=1_800_000_000,
    )
    assert result["probes_run"] == expected
