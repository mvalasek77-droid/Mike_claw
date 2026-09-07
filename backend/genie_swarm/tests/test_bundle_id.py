"""Tests for pinning the generated project's bundle identifier.

The bug these lock down: the phone created the App Store Connect
record, signed, uploaded and polled against one bundle ID, while the
generated Xcode project carried whatever the model wrote. Every upload
was therefore signed as one app and sent against another.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from genie_swarm.bundle_id import enforce_bundle_id, is_valid_bundle_id


def _pbxproj(workspace: Path, *values: str) -> Path:
    proj = workspace / "App.xcodeproj"
    proj.mkdir(parents=True)
    body = "\n".join(
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {v};" for v in values
    )
    path = proj / "project.pbxproj"
    path.write_text("// !$*UTF8*$!\n{\n" + body + "\n}\n")
    return path


# ---------------------------------------------------------------------------
# Rewriting
# ---------------------------------------------------------------------------

def test_rewrites_the_app_target(tmp_path: Path):
    path = _pbxproj(tmp_path, "com.example.app")
    changed = enforce_bundle_id(tmp_path, "com.mike.tides")
    assert changed == [str(Path("App.xcodeproj") / "project.pbxproj")]
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.mike.tides;" in path.read_text()
    assert "com.example.app" not in path.read_text()


def test_test_targets_keep_their_suffix(tmp_path: Path):
    """Apple refuses a test bundle that shares the app's identifier, so
    flattening every target to one value breaks the build in a way that
    looks nothing like a bundle ID problem."""
    path = _pbxproj(
        tmp_path, "com.example.app", "com.example.app.Tests", "com.example.app.UITests"
    )
    enforce_bundle_id(tmp_path, "com.mike.tides")
    body = path.read_text()
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.mike.tides;" in body
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.mike.tides.Tests;" in body
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.mike.tides.UITests;" in body


def test_handles_a_quoted_value(tmp_path: Path):
    path = _pbxproj(tmp_path, '"com.example.app"')
    enforce_bundle_id(tmp_path, "com.mike.tides")
    assert "PRODUCT_BUNDLE_IDENTIFIER = com.mike.tides;" in path.read_text()


def test_rewrites_an_xcodegen_project(tmp_path: Path):
    path = tmp_path / "project.yml"
    path.write_text(
        "targets:\n  App:\n    settings:\n"
        "      PRODUCT_BUNDLE_IDENTIFIER: com.example.app\n"
    )
    changed = enforce_bundle_id(tmp_path, "com.mike.tides")
    assert changed == ["project.yml"]
    assert "PRODUCT_BUNDLE_IDENTIFIER: com.mike.tides" in path.read_text()


def test_rewrites_the_plan_so_later_agents_agree(tmp_path: Path):
    """The plan is what the coder and integrator read; leaving a stale
    id there reintroduces the mismatch on the next retry."""
    docs = tmp_path / "docs"
    docs.mkdir()
    plan = docs / "plan.json"
    plan.write_text(json.dumps({"app": {"name": "Tides", "bundle_id": "com.example.app"}}))
    enforce_bundle_id(tmp_path, "com.mike.tides")
    assert json.loads(plan.read_text())["app"]["bundle_id"] == "com.mike.tides"


def test_finds_a_project_one_level_down(tmp_path: Path):
    nested = tmp_path / "ios"
    nested.mkdir()
    path = _pbxproj(nested, "com.example.app")
    enforce_bundle_id(tmp_path, "com.mike.tides")
    assert "com.mike.tides" in path.read_text()


def test_leaves_swift_source_alone(tmp_path: Path):
    """A blanket search-and-replace would rewrite the identifier inside
    generated source and docs, where it is prose, not configuration."""
    _pbxproj(tmp_path, "com.example.app")
    source = tmp_path / "App" / "Info.swift"
    source.parent.mkdir(parents=True)
    source.write_text('let id = "com.example.app"  // PRODUCT_BUNDLE_IDENTIFIER\n')
    enforce_bundle_id(tmp_path, "com.mike.tides")
    assert "com.example.app" in source.read_text()


def test_reports_nothing_when_already_correct(tmp_path: Path):
    _pbxproj(tmp_path, "com.mike.tides")
    assert enforce_bundle_id(tmp_path, "com.mike.tides") == []


# ---------------------------------------------------------------------------
# Refusing bad input
# ---------------------------------------------------------------------------

def test_a_bad_id_is_left_alone_rather_than_written_over(tmp_path: Path):
    """The generated project's own value is a better outcome than a
    malformed one written over it."""
    path = _pbxproj(tmp_path, "com.example.app")
    for bad in ["", "noDots", "com..double", ".com.x", "com.x.", "com.bad space"]:
        assert enforce_bundle_id(tmp_path, bad) == []
    assert "com.example.app" in path.read_text()


def test_validity_rules():
    assert is_valid_bundle_id("com.mike.tides")
    assert is_valid_bundle_id("com.mike-co.tides2")
    assert not is_valid_bundle_id("tides")
    assert not is_valid_bundle_id("com.mike.tides!")
    assert not is_valid_bundle_id("com." + "x" * 200)


def test_missing_project_is_not_an_error(tmp_path: Path):
    assert enforce_bundle_id(tmp_path, "com.mike.tides") == []


# ---------------------------------------------------------------------------
# The pipeline actually calls it
# ---------------------------------------------------------------------------

class _Events:
    def __init__(self) -> None:
        self.emitted: list[tuple[str, dict]] = []

    async def emit(self, name: str, **kw) -> None:
        self.emitted.append((name, kw))


async def _pin(tmp_path: Path, bundle_id):
    """Drive the orchestrator's own step, not the helper underneath it —
    a correct helper that nothing calls is what the bug was."""
    from types import SimpleNamespace

    from genie_swarm.orchestrator import SwarmOrchestrator
    from genie_swarm.sandbox import Sandbox, SandboxPolicy

    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    events = _Events()
    notes: list[str] = []
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(
            note_decision=lambda job_id, stage, text: notes.append(text)
        )
    )
    session = SimpleNamespace(
        sandbox=sandbox,
        job=SimpleNamespace(id="job1", spec=SimpleNamespace(bundle_id=bundle_id)),
    )
    await SwarmOrchestrator._pin_bundle_id(fake_self, session, events)
    return events, notes


@pytest.mark.asyncio
async def test_pipeline_pins_the_project_to_the_spec(tmp_path: Path):
    path = _pbxproj(tmp_path, "com.example.app")
    events, notes = await _pin(tmp_path, "com.mike.tides")

    assert "com.mike.tides" in path.read_text()
    assert [n for n, _ in events.emitted] == ["bundle.pinned"]
    assert any("Pinned bundle ID" in n for n in notes)


@pytest.mark.asyncio
async def test_pipeline_is_quiet_when_the_phone_sent_nothing(tmp_path: Path):
    """Older clients don't send a bundle id. Their generated project's
    own value has to survive rather than be blanked."""
    path = _pbxproj(tmp_path, "com.example.app")
    for missing in ["", None]:
        events, _ = await _pin(tmp_path, missing)
        assert events.emitted == []
    assert "com.example.app" in path.read_text()
