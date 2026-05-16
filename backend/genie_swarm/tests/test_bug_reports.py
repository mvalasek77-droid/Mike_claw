from __future__ import annotations

import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router, state


def test_bug_report_persists_to_disk(tmp_path: Path):
    """POSTing a bug report writes a JSON file under .bug_reports and
    returns the assigned id so the iOS client can echo it back."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)

    try:
        client = TestClient(app)
        response = client.post(
            "/api/coding/swarm/bug-reports",
            json={
                "details": "Try a sample stayed on Planning for 5 minutes.",
                "diagnostics": "iOS: 18.5\nAuth: byok",
                "client_version": "0.1.0",
                "client_build": "1",
                "device": "iPhone16,2",
                "os_version": "18.5",
            },
        )
        assert response.status_code == 200
        body = response.json()
        assert body["ok"] is True
        assert body["id"]

        reports_dir = tmp_path / ".bug_reports"
        files = list(reports_dir.glob("*.json"))
        assert len(files) == 1
        on_disk = json.loads(files[0].read_text())
        assert on_disk["details"].startswith("Try a sample")
        assert on_disk["diagnostics"] == "iOS: 18.5\nAuth: byok"
        assert on_disk["device"] == "iPhone16,2"
        assert on_disk["id"] == body["id"]
        assert on_disk["received_at"]
    finally:
        state.config = original_config


def test_bug_report_rejects_short_details(tmp_path: Path):
    """Pydantic validation rejects details below 10 chars so users
    can't ship empty / one-word reports by accident."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)

    try:
        client = TestClient(app)
        response = client.post(
            "/api/coding/swarm/bug-reports",
            json={"details": "broken"},
        )
        assert response.status_code == 422
        assert not (tmp_path / ".bug_reports").exists()
    finally:
        state.config = original_config


def test_bug_report_minimal_payload_works(tmp_path: Path):
    """All metadata fields are optional — a user can submit just
    details and still get a recorded report."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)

    try:
        client = TestClient(app)
        response = client.post(
            "/api/coding/swarm/bug-reports",
            json={"details": "Pair Mac sheet never finds my Mac."},
        )
        assert response.status_code == 200
        on_disk = json.loads(
            next((tmp_path / ".bug_reports").glob("*.json")).read_text()
        )
        assert on_disk["diagnostics"] is None
        assert on_disk["device"] is None
    finally:
        state.config = original_config
