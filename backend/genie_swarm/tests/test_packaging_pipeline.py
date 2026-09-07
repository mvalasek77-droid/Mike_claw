"""Tests for the path that actually turns generated source into a
signed .ipa, and for what the user is told when it cannot.

`test_archive_export.py` covers the contract around the Mac companion.
These cover the step that sits underneath it, because three things
were wrong there at once and every one of them was invisible to a test
that stopped at the runner boundary:

* the ship stage read `sandbox.root`, an attribute `Sandbox` does not
  have, so attempting to package raised `AttributeError` mid-run;
* nothing outside the test suite ever registered a companion
  transport, and the local runner refused outright, so packaging was
  impossible on *every* deployment rather than merely degraded;
* `xcrun` was spawned with no guard, so on a host without Xcode the
  upload raised `FileNotFoundError` instead of explaining itself.

So these tests drive the real functions with a stand-in `xcodebuild`
on PATH, rather than asserting against a mock of the thing under test.
"""
from __future__ import annotations

import os
import stat
from pathlib import Path
from types import SimpleNamespace

import pytest

from genie_swarm.runner import (
    CompanionRunner,
    LocalSandboxRunner,
    _detect_project,
    _explain_failure,
    set_companion_transport,
)
from genie_swarm.sandbox import Sandbox, SandboxPolicy


@pytest.fixture(autouse=True)
def _clear_transport():
    set_companion_transport(None)
    yield
    set_companion_transport(None)


# ---------------------------------------------------------------------------
# A stand-in xcodebuild
# ---------------------------------------------------------------------------

_FAKE_XCODEBUILD = r"""#!/usr/bin/env python3
import json, os, pathlib, sys

argv = sys.argv[1:]
log = pathlib.Path(os.environ["FAKE_XCB_LOG"])
with log.open("a") as fh:
    fh.write("\x00".join(argv) + "\n")

if "-list" in argv:
    print("note: some warning before the json")
    print(json.dumps({"project": {"schemes": ["AppTests", "App"]}}))
    sys.exit(0)

if os.environ.get("FAKE_XCB_FAIL") == "archive" and "archive" in argv:
    print("error: No profiles for 'com.example.app' were found")
    sys.exit(65)

if "archive" in argv:
    out = pathlib.Path(argv[argv.index("-archivePath") + 1])
    (out / "Products").mkdir(parents=True, exist_ok=True)
    print("** ARCHIVE SUCCEEDED **")
    sys.exit(0)

if "-exportArchive" in argv:
    if os.environ.get("FAKE_XCB_FAIL") == "export":
        print("error: exportArchive: No signing certificate")
        sys.exit(70)
    out = pathlib.Path(argv[argv.index("-exportPath") + 1])
    out.mkdir(parents=True, exist_ok=True)
    (out / "App.ipa").write_bytes(b"PK\x03\x04 not really a zip")
    print("** EXPORT SUCCEEDED **")
    sys.exit(0)

sys.exit(1)
"""


@pytest.fixture
def fake_xcode(tmp_path: Path, monkeypatch):
    """Put a scriptable `xcodebuild` on PATH so the real packaging code
    runs end to end on Linux."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    exe = bin_dir / "xcodebuild"
    exe.write_text(_FAKE_XCODEBUILD)
    exe.chmod(exe.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    calls = tmp_path / "xcb-calls.log"
    calls.touch()
    monkeypatch.setenv("FAKE_XCB_LOG", str(calls))
    monkeypatch.setenv("PATH", f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    return SimpleNamespace(
        calls=lambda: [
            line.split("\x00") for line in calls.read_text().splitlines() if line
        ],
    )


def _workspace(tmp_path: Path) -> tuple[Sandbox, Path]:
    root = tmp_path / "ws"
    (root / "App.xcodeproj").mkdir(parents=True)
    return Sandbox(SandboxPolicy(workspace=root)), root


# ---------------------------------------------------------------------------
# Packaging actually happens
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_local_runner_produces_an_ipa(tmp_path: Path, fake_xcode):
    """The whole point. Previously this refused outright, so no
    deployment could ever produce a binary to upload."""
    sandbox, root = _workspace(tmp_path)
    seen: list[str] = []

    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root),
        team_id="ABCDE12345",
        sandbox=sandbox,
        on_line=lambda line: _collect(seen, line),
    )

    assert result.ok, result.detail
    # Downstream resolves this through the Sandbox, which rejects
    # absolute paths.
    assert result.ipa_path == str(Path("build") / "export" / "App.ipa")
    assert not Path(result.ipa_path).is_absolute()
    assert (root / result.ipa_path).exists()
    assert "** EXPORT SUCCEEDED **" in seen


async def _collect(sink: list[str], line: str) -> None:
    sink.append(line)


@pytest.mark.asyncio
async def test_signing_inputs_reach_xcodebuild(tmp_path: Path, fake_xcode):
    """Without these, automatic signing has nothing to authenticate
    with and every export dies on a profile error."""
    sandbox, root = _workspace(tmp_path)
    (root / "asc.p8").write_text("-----BEGIN PRIVATE KEY-----")

    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root),
        team_id="ABCDE12345",
        asc_api_key_id="KEY1",
        asc_api_issuer_id="ISS1",
        asc_api_key_path="asc.p8",
        sandbox=sandbox,
    )
    assert result.ok, result.detail

    archive = next(c for c in fake_xcode.calls() if "archive" in c)
    assert "-allowProvisioningUpdates" in archive
    assert "DEVELOPMENT_TEAM=ABCDE12345" in archive
    assert "-authenticationKeyID" in archive
    assert archive[archive.index("-authenticationKeyID") + 1] == "KEY1"
    assert archive[archive.index("-authenticationKeyIssuerID") + 1] == "ISS1"


@pytest.mark.asyncio
async def test_missing_key_file_does_not_abort_packaging(tmp_path: Path, fake_xcode):
    """A stale key path should degrade to "sign it another way", not
    crash the run before anything is built."""
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root),
        asc_api_key_id="KEY1",
        asc_api_issuer_id="ISS1",
        asc_api_key_path="nope.p8",
        sandbox=sandbox,
    )
    assert result.ok, result.detail
    archive = next(c for c in fake_xcode.calls() if "archive" in c)
    assert "-authenticationKeyID" not in archive


@pytest.mark.asyncio
async def test_scheme_detection_skips_the_test_scheme(tmp_path: Path, fake_xcode):
    """`-list` returns AppTests first. Archiving a test scheme exports
    nothing, and the error it produces reads like the app is broken."""
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert result.scheme == "App"


@pytest.mark.asyncio
async def test_explicit_scheme_skips_detection(tmp_path: Path, fake_xcode):
    sandbox, root = _workspace(tmp_path)
    await LocalSandboxRunner().archive_export(
        workspace_root=str(root), scheme="Custom", sandbox=sandbox,
    )
    assert not any("-list" in c for c in fake_xcode.calls())


@pytest.mark.asyncio
async def test_no_transport_now_packages_locally(tmp_path: Path, fake_xcode):
    """The companion runner must degrade the way `xcodebuild` and
    `simctl` already do. Hard-failing here is what made packaging
    impossible in production, since nothing registers a transport."""
    sandbox, root = _workspace(tmp_path)
    result = await CompanionRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert result.ok, result.detail
    assert result.ipa_path.endswith("App.ipa")


# ---------------------------------------------------------------------------
# Honest failures
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_archive_failure_explains_itself(tmp_path: Path, fake_xcode, monkeypatch):
    monkeypatch.setenv("FAKE_XCB_FAIL", "archive")
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert not result.ok
    assert result.phase == "archive"
    # The raw log stays available, but the headline has to be actionable.
    assert "No profiles" in result.log_tail
    assert "signing profile" in result.detail


@pytest.mark.asyncio
async def test_export_failure_keeps_the_phase(tmp_path: Path, fake_xcode, monkeypatch):
    """Compile errors and signing errors need different advice."""
    monkeypatch.setenv("FAKE_XCB_FAIL", "export")
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert not result.ok
    assert result.phase == "export"
    assert result.ipa_path == ""


@pytest.mark.asyncio
async def test_no_project_says_so(tmp_path: Path, fake_xcode):
    root = tmp_path / "empty"
    root.mkdir()
    sandbox = Sandbox(SandboxPolicy(workspace=root))
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert not result.ok
    assert "No Xcode project" in result.detail


@pytest.mark.asyncio
async def test_host_without_xcode_names_the_real_reason(tmp_path: Path, monkeypatch):
    """No `fake_xcode` fixture here, so `xcodebuild` is genuinely absent."""
    monkeypatch.setenv("PATH", str(tmp_path / "nothing"))
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root), sandbox=sandbox,
    )
    assert not result.ok
    assert "your Mac" in result.detail
    assert "Settings" in result.detail


@pytest.mark.asyncio
async def test_project_outside_the_workspace_is_refused(tmp_path: Path, fake_xcode):
    """`workspace_or_project` arrives from the client, so it must not be
    able to point the build at something outside the sandbox."""
    sandbox, root = _workspace(tmp_path)
    outside = tmp_path / "elsewhere.xcodeproj"
    outside.mkdir()
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root),
        workspace_or_project="../elsewhere.xcodeproj",
        sandbox=sandbox,
    )
    assert not result.ok
    assert "not inside the workspace" in result.detail


@pytest.mark.asyncio
async def test_scheme_cannot_steer_the_archive_out_of_the_workspace(
    tmp_path: Path, fake_xcode,
):
    """`scheme` also arrives from the client, and it is used to build
    the archive path, not just passed as an argv value."""
    sandbox, root = _workspace(tmp_path)
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(root),
        scheme="../../escaped",
        sandbox=sandbox,
    )
    assert not result.ok
    assert not (tmp_path / "escaped.xcarchive").exists()


def test_detect_project_prefers_a_workspace(tmp_path: Path):
    """When both exist the workspace is the one with dependencies."""
    (tmp_path / "App.xcodeproj").mkdir()
    (tmp_path / "App.xcworkspace").mkdir()
    assert _detect_project(tmp_path) == "App.xcworkspace"


def test_detect_project_looks_one_level_down(tmp_path: Path):
    (tmp_path / "ios").mkdir()
    (tmp_path / "ios" / "App.xcodeproj").mkdir()
    assert _detect_project(tmp_path) == str(Path("ios") / "App.xcodeproj")


def test_missing_team_is_explained_plainly():
    detail = _explain_failure("archive", "error: Signing requires a development team")
    assert "Team ID" in detail


# ---------------------------------------------------------------------------
# The ship stage's own wiring
# ---------------------------------------------------------------------------

class _Events:
    def __init__(self) -> None:
        self.emitted: list[tuple[str, dict]] = []

    async def emit(self, name: str, **kw) -> None:
        self.emitted.append((name, kw))


@pytest.mark.asyncio
async def test_package_ipa_reads_the_workspace_correctly(tmp_path: Path, fake_xcode):
    """Regression: this read `sandbox.root`, which does not exist, so
    every attempt to package raised AttributeError. Nothing caught it
    because the other tests called the runner directly and never went
    through the ship stage."""
    from genie_swarm.orchestrator import ShipConfig, SwarmOrchestrator

    sandbox, root = _workspace(tmp_path)
    events = _Events()
    notes: list[str] = []
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(
            note_decision=lambda job_id, stage, text: notes.append(text)
        )
    )
    session = SimpleNamespace(sandbox=sandbox, job=SimpleNamespace(id="job1"))

    packaged = await SwarmOrchestrator._package_ipa(
        fake_self,
        ShipConfig(ipa_path="Build.ipa", bundle_id="com.example.app"),
        session,
        events,
    )

    assert packaged == str(Path("build") / "export" / "App.ipa")
    assert (root / packaged).exists()
    names = [n for n, _ in events.emitted]
    assert "testflight.package" in names
    # Minutes of silence reads as a hang, so progress has to reach the UI.
    assert "testflight.package.progress" in names
    assert any("Packaged signed IPA" in n for n in notes)


@pytest.mark.asyncio
async def test_packaging_events_match_what_the_app_parses(tmp_path: Path, fake_xcode):
    """The iOS strip switches on these exact values, and the boundary
    is untyped JSON, so a rename here would silently blank the progress
    UI rather than fail anywhere.

    `UploadProgressTracker.Phase` has raw values archive/export/
    validate/upload, and it reads a null `ok` as "still running" —
    which is the only way it can tell a start marker from a success.
    """
    from genie_swarm.orchestrator import ShipConfig, SwarmOrchestrator

    sandbox, _ = _workspace(tmp_path)
    events = _Events()
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(note_decision=lambda *a: None)
    )
    session = SimpleNamespace(sandbox=sandbox, job=SimpleNamespace(id="job1"))

    await SwarmOrchestrator._package_ipa(
        fake_self,
        ShipConfig(ipa_path="Build.ipa", bundle_id="com.example.app"),
        session,
        events,
    )

    package = [kw for n, kw in events.emitted if n == "testflight.package"]
    assert package, "the strip stays hidden without a start marker"
    assert package[0]["ok"] is None, "a start marker must not look like success"
    assert {p["phase"] for p in package} <= {"archive", "export"}
    assert package[-1]["ok"] is True

    progress = [kw for n, kw in events.emitted if n == "testflight.package.progress"]
    assert progress and all("line" in kw for kw in progress)


@pytest.mark.asyncio
async def test_package_ipa_reports_failure_without_raising(tmp_path: Path, monkeypatch):
    from genie_swarm.orchestrator import ShipConfig, SwarmOrchestrator

    monkeypatch.setenv("PATH", str(tmp_path / "nothing"))
    sandbox, _ = _workspace(tmp_path)
    events = _Events()
    fake_self = SimpleNamespace(
        memory=SimpleNamespace(note_decision=lambda *a: None)
    )
    session = SimpleNamespace(sandbox=sandbox, job=SimpleNamespace(id="job1"))

    packaged = await SwarmOrchestrator._package_ipa(
        fake_self,
        ShipConfig(ipa_path="Build.ipa", bundle_id="com.example.app"),
        session,
        events,
    )
    assert packaged is None
    failed = [kw for n, kw in events.emitted if n == "testflight.package"]
    assert failed[-1]["ok"] is False
    assert "Mac" in failed[-1]["preview"]


@pytest.mark.asyncio
async def test_upload_without_xcrun_explains_itself(tmp_path: Path, monkeypatch):
    """`xcrun` exists only on macOS. Spawning it unguarded raised
    FileNotFoundError out of the middle of the ship stage."""
    from genie_swarm.orchestrator import SwarmOrchestrator

    monkeypatch.setenv("PATH", str(tmp_path / "nothing"))
    events = _Events()
    ok, tail = await SwarmOrchestrator._stream_altool(
        SimpleNamespace(),
        ["xcrun", "altool", "--upload-app"],
        phase="upload",
        events=events,
    )
    assert ok is False
    assert "xcrun" in tail
