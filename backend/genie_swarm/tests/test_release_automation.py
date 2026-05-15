"""Release automation and GitHub sync tests."""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from genie_swarm.api import router, state
from genie_swarm.github_sync import GitHubSyncError, sync_workspace_to_github
from genie_swarm.memory import Memory
from genie_swarm.models import (
    AppSpec,
    BuildJob,
    GitHubSyncRequest,
    ReleaseReadinessRequest,
    ShipRequest,
)
from genie_swarm.release_readiness import run_release_readiness


def _write_release_workspace(root: Path, job_id: str = "job_release") -> Path:
    ws = root / job_id
    (ws / "CodeGenie.xcodeproj").mkdir(parents=True)
    (ws / "Resources").mkdir()
    (ws / "Screenshots").mkdir()
    (ws / "Resources" / "PrivacyInfo.xcprivacy").write_text(
        """
        <plist><dict>
          <key>NSPrivacyTracking</key><false/>
          <key>NSPrivacyCollectedDataTypes</key><array/>
          <key>NSPrivacyAccessedAPITypes</key><array/>
        </dict></plist>
        """,
        encoding="utf-8",
    )
    (ws / "Resources" / "AppStoreMetadata.json").write_text(
        """
        {
          "name": "CodeGenie",
          "description": "Build and ship iOS apps from iPhone.",
          "privacy_policy_url": "https://example.com/privacy"
        }
        """,
        encoding="utf-8",
    )
    (ws / "TermsOfUse.md").write_text("# Terms\n", encoding="utf-8")
    (ws / "Screenshots" / "iphone-67-screenshot.png").write_bytes(b"\x89PNG\r\n\x1a\n")
    (ws / "Build.ipa").write_bytes(b"ipa")
    (ws / "Sources").mkdir()
    (ws / "Sources" / "App.swift").write_text("import SwiftUI\n", encoding="utf-8")
    return ws


def test_release_readiness_ready_for_testflight(tmp_path: Path):
    ws = _write_release_workspace(tmp_path)
    result = run_release_readiness(
        spec=AppSpec(title="CodeGenie", prompt="ship"),
        workspace=ws,
        ship=ShipRequest(
            ipa_path="Build.ipa",
            bundle_id="com.example.codegenie",
            asc_api_key_id="ABC123",
            asc_api_issuer_id="issuer",
            asc_api_key_path="AuthKey_ABC123.p8",
        ),
        github=GitHubSyncRequest(repo_url="git@github.com:user/repo.git", branch="release/codegenie"),
    )

    assert result["release_gate"] == "ready_for_testflight"
    assert result["score"] == 100
    statuses = {item["key"]: item["status"] for item in result["items"]}
    assert statuses["testflight_upload"] == "automated"
    assert statuses["privacy_manifest"] == "automated"
    assert statuses["github"] == "automated"
    assert statuses["final_submit"] == "user_confirmation"


def test_release_readiness_reports_missing_automation(tmp_path: Path):
    ws = tmp_path / "job_missing"
    ws.mkdir()
    result = run_release_readiness(
        spec=AppSpec(title="Missing", prompt="ship"),
        workspace=ws,
        ship=None,
        github=None,
    )

    assert result["release_gate"] == "needs_setup"
    keys = {item["key"]: item for item in result["items"]}
    assert keys["xcode_project"]["status"] == "needs_setup"
    assert keys["apple_credentials"]["status"] == "needs_setup"
    assert keys["privacy_manifest"]["status"] == "needs_setup"
    assert any("Archive and export" in action for action in result["next_actions"])


@pytest.mark.asyncio
async def test_github_sync_pushes_workspace_and_excludes_codegenie(tmp_path: Path):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "Sources").mkdir()
    (workspace / "Sources" / "App.swift").write_text("import SwiftUI\n", encoding="utf-8")
    (workspace / ".codegenie").mkdir()
    (workspace / ".codegenie" / "secret.txt").write_text("do-not-commit", encoding="utf-8")
    (workspace / ".genie-session.json").write_text("{}", encoding="utf-8")

    remote = tmp_path / "remote.git"
    subprocess.run(["git", "init", "--bare", str(remote)], check=True, capture_output=True)

    result = await sync_workspace_to_github(
        workspace,
        GitHubSyncRequest(repo_url=str(remote), branch="codegenie-test", commit_message="test sync"),
    )

    assert result["ok"] is True
    tree = subprocess.run(
        ["git", "--git-dir", str(remote), "ls-tree", "-r", "--name-only", "codegenie-test"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    assert "Sources/App.swift" in tree
    assert ".gitignore" in tree
    assert ".codegenie/secret.txt" not in tree
    assert ".genie-session.json" not in tree


@pytest.mark.asyncio
async def test_github_sync_rejects_bad_branch(tmp_path: Path):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    with pytest.raises(GitHubSyncError):
        await sync_workspace_to_github(
            workspace,
            GitHubSyncRequest(repo_url="git@github.com:user/repo.git", branch="bad branch"),
        )


@pytest.mark.asyncio
async def test_github_sync_open_pr_requires_token(tmp_path: Path):
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    with pytest.raises(GitHubSyncError, match="token required"):
        await sync_workspace_to_github(
            workspace,
            GitHubSyncRequest(repo_url="git@github.com:user/repo.git", open_pr=True),
        )


def test_release_readiness_route_records_memory(tmp_path: Path):
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

    job = BuildJob(id="job_route_release", spec=AppSpec(title="Route Release", prompt="ship"))
    state.jobs[job.id] = job
    _write_release_workspace(tmp_path, job.id)

    try:
        client = TestClient(app)
        request = ReleaseReadinessRequest(
            ship=ShipRequest(
                ipa_path="Build.ipa",
                bundle_id="com.example.route",
                asc_api_key_id="KEY123",
                asc_api_issuer_id="issuer",
                asc_api_key_path="AuthKey_KEY123.p8",
            )
        )
        response = client.post(
            f"/api/coding/swarm/{job.id}/release-readiness",
            json=request.model_dump(),
        )
        assert response.status_code == 200
        assert response.json()["release_gate"] == "ready_for_testflight"
        decisions = Memory(tmp_path).decisions_for(job.id)
        assert any("release readiness" in decision.context for decision in decisions)
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
