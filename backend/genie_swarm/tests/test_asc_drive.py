from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router, state
from genie_swarm.models import AppSpec, BuildJob


def test_asc_drive_412_when_no_companion(tmp_path: Path, monkeypatch):
    """Without a paired Mac Companion, the route degrades cleanly
    with a 412 so the iOS side can fall back to the manual flow."""
    from genie_swarm import runner as runner_mod
    monkeypatch.setattr(runner_mod, "_transport", None)

    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()
    job = BuildJob(id="job_asc", spec=AppSpec(title="Tides", prompt="surf"))
    state.jobs[job.id] = job

    try:
        client = TestClient(app)
        response = client.post(
            f"/api/coding/swarm/{job.id}/asc/drive",
            json={"steps": []},
        )
        assert response.status_code == 412
        assert "Companion" in response.json()["detail"]
    finally:
        state.config = original_config
        state.jobs.clear()


def test_asc_drive_404_for_unknown_job(tmp_path: Path):
    """Unknown job returns 404 — not a bare KeyError leak."""
    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()
    try:
        client = TestClient(app)
        response = client.post(
            "/api/coding/swarm/does-not-exist/asc/drive",
            json={"steps": []},
        )
        assert response.status_code == 404
    finally:
        state.config = original_config


def test_asc_drive_runs_full_flow_when_companion_paired(tmp_path: Path, monkeypatch):
    """With a Companion paired (a real transport plugged in), the
    route walks all 10 default steps, leaving the final `submit` as
    a human action."""
    from genie_swarm import runner as runner_mod

    class _StubTransport:
        async def xcodebuild(self, **kw): raise NotImplementedError
        async def simctl(self, **kw): raise NotImplementedError
    monkeypatch.setattr(runner_mod, "_transport", _StubTransport())

    app = FastAPI()
    app.include_router(router)
    original_config = state.config
    state.config = state.config.__class__(workspace_root=tmp_path)
    state.jobs.clear()
    job = BuildJob(id="job_asc_run", spec=AppSpec(title="Tides", prompt="surf"))
    state.jobs[job.id] = job

    try:
        client = TestClient(app)
        response = client.post(
            f"/api/coding/swarm/{job.id}/asc/drive",
            json={"steps": []},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["ok"] is True
        assert body["companion_paired"] is True
        assert "submit" in body["manual_steps"]
        # 10 default steps minus the final manual `submit` = 9 driven.
        assert body["steps_driven"] == 9
    finally:
        state.config = original_config
        state.jobs.clear()
