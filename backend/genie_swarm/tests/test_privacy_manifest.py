"""Tests for generating the privacy manifest.

The bug: `PrivacyInfo.xcprivacy` is required for App Store review and
the readiness audit checks for it, but no agent prompt ever mentions
it. Every generated app therefore failed that check, and the App Store
submit gate stayed shut no matter what the user did.
"""
from __future__ import annotations

import plistlib
from pathlib import Path
from types import SimpleNamespace

import pytest

from genie_swarm.privacy_manifest import (
    MANIFEST_NAME,
    ensure_privacy_manifest,
    find_manifest,
)


def test_writes_a_manifest_the_audit_accepts(tmp_path: Path):
    """The three keys here are exactly the ones the readiness audit
    requires, so the two must not drift apart."""
    (tmp_path / "App.xcodeproj").mkdir()
    (tmp_path / "App").mkdir()

    written = ensure_privacy_manifest(tmp_path)
    assert written is not None

    body = plistlib.loads(written.read_bytes())
    assert body["NSPrivacyTracking"] is False
    assert body["NSPrivacyCollectedDataTypes"] == []
    assert body["NSPrivacyAccessedAPITypes"] == []

    from genie_swarm.release_readiness import run_release_readiness
    from genie_swarm.models import AppSpec

    result = run_release_readiness(
        spec=AppSpec(title="Tides", prompt="ship"), workspace=tmp_path,
    )
    statuses = {item["key"]: item["status"] for item in result["items"]}
    assert statuses["privacy_manifest"] == "automated"


def test_lands_next_to_the_app_source(tmp_path: Path):
    """Apple wants it inside the app target's own folder, which in the
    layout Xcode creates is the directory named after the project."""
    (tmp_path / "Tides.xcodeproj").mkdir()
    (tmp_path / "Tides").mkdir()
    written = ensure_privacy_manifest(tmp_path)
    assert written == tmp_path / "Tides" / MANIFEST_NAME


def test_falls_back_to_a_source_folder(tmp_path: Path):
    (tmp_path / "App.xcodeproj").mkdir()
    (tmp_path / "Sources").mkdir()
    written = ensure_privacy_manifest(tmp_path)
    assert written == tmp_path / "Sources" / MANIFEST_NAME


def test_never_overwrites_an_existing_manifest(tmp_path: Path):
    """Whoever wrote one knows more about the app than this default."""
    existing = tmp_path / "App" / MANIFEST_NAME
    existing.parent.mkdir(parents=True)
    existing.write_bytes(plistlib.dumps({"NSPrivacyTracking": True}))

    assert ensure_privacy_manifest(tmp_path) is None
    assert plistlib.loads(existing.read_bytes())["NSPrivacyTracking"] is True


def test_finds_a_manifest_nested_anywhere(tmp_path: Path):
    nested = tmp_path / "a" / "b" / MANIFEST_NAME
    nested.parent.mkdir(parents=True)
    nested.write_bytes(plistlib.dumps({}))
    assert find_manifest(tmp_path) == nested


# ---------------------------------------------------------------------------
# The pipeline actually calls it
# ---------------------------------------------------------------------------

class _Events:
    def __init__(self) -> None:
        self.emitted: list[tuple[str, dict]] = []

    async def emit(self, name: str, **kw) -> None:
        self.emitted.append((name, kw))


@pytest.mark.asyncio
async def test_pipeline_writes_the_manifest(tmp_path: Path):
    """A correct generator that nothing calls is what the bug was."""
    from genie_swarm.orchestrator import SwarmOrchestrator
    from genie_swarm.sandbox import Sandbox, SandboxPolicy

    (tmp_path / "App.xcodeproj").mkdir(parents=True)
    (tmp_path / "App").mkdir()

    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    events = _Events()
    notes: list[str] = []
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(
            note_decision=lambda job_id, stage, text: notes.append(text)
        )
    )
    session = SimpleNamespace(sandbox=sandbox, job=SimpleNamespace(id="job1"))

    await SwarmOrchestrator._ensure_privacy_manifest(fake_self, session, events)

    assert (tmp_path / "App" / MANIFEST_NAME).exists()
    assert [n for n, _ in events.emitted] == ["privacy.manifest"]
    assert any("privacy manifest" in n for n in notes)


@pytest.mark.asyncio
async def test_pipeline_is_quiet_when_one_already_exists(tmp_path: Path):
    from genie_swarm.orchestrator import SwarmOrchestrator
    from genie_swarm.sandbox import Sandbox, SandboxPolicy

    existing = tmp_path / MANIFEST_NAME
    existing.write_bytes(plistlib.dumps({"NSPrivacyTracking": False}))

    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    events = _Events()
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(note_decision=lambda *a: None)
    )
    session = SimpleNamespace(sandbox=sandbox, job=SimpleNamespace(id="job1"))

    await SwarmOrchestrator._ensure_privacy_manifest(fake_self, session, events)
    assert events.emitted == []
