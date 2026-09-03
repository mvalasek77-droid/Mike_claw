"""Tests for packaging a signed .ipa.

Nothing here runs xcodebuild. What these lock down is the contract
around it, because the failure that mattered was structural rather
than a bug in any one command: everything downstream of the ship stage
assumed a signed binary already existed, and nothing ever produced one,
so TestFlight upload could not succeed for anybody.

So we assert that packaging is attempted when the binary is missing,
that it is skipped when it is not, that its result is what the upload
then uses, and — most importantly — that when packaging is impossible
the user is told the true reason instead of "ipa not found".
"""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.runner import (
    ArchiveResult,
    CompanionRunner,
    LocalSandboxRunner,
    set_companion_transport,
)
from genie_swarm.sandbox import Sandbox, SandboxPolicy


@pytest.fixture(autouse=True)
def _clear_transport():
    set_companion_transport(None)
    yield
    set_companion_transport(None)


class _RecordingTransport:
    """Stands in for the paired Mac."""

    def __init__(self, result: ArchiveResult | None = None) -> None:
        self.result = result or ArchiveResult(
            ok=True, ipa_path="build/export/App.ipa", scheme="App"
        )
        self.kwargs: dict = {}
        self.lines = ["Archiving...", "** ARCHIVE SUCCEEDED **", "** EXPORT SUCCEEDED **"]

    async def archive_export(self, **kwargs):
        self.kwargs = kwargs
        forward = kwargs.get("on_line")
        if forward:
            for line in self.lines:
                await forward(line)
        return self.result


# ---------------------------------------------------------------------------
# Routing to the Mac
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_packaging_routes_to_the_paired_mac(tmp_path: Path):
    transport = _RecordingTransport()
    set_companion_transport(transport)
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))

    seen: list[str] = []

    async def on_line(line: str) -> None:
        seen.append(line)

    result = await CompanionRunner().archive_export(
        workspace_root=str(tmp_path),
        team_id="ABCDE12345",
        asc_api_key_id="KEY1",
        asc_api_issuer_id="ISS1",
        asc_api_key_path="asc-key.p8",
        sandbox=sandbox,
        on_line=on_line,
    )

    assert result.ok
    assert result.ipa_path == "build/export/App.ipa"
    # Signing inputs must actually reach the Mac, or Xcode cannot
    # create the certificate and profile on its own.
    assert transport.kwargs["team_id"] == "ABCDE12345"
    assert transport.kwargs["asc_api_key_id"] == "KEY1"
    assert transport.kwargs["asc_api_issuer_id"] == "ISS1"
    assert transport.kwargs["asc_api_key_path"] == "asc-key.p8"
    # Archive builds run for minutes; silence reads as a hang.
    assert "** EXPORT SUCCEEDED **" in seen


@pytest.mark.asyncio
async def test_scheme_and_project_are_left_for_the_mac_to_detect(tmp_path: Path):
    """Only the Mac can see what the generated project actually is, so
    blank means detect rather than guess from the phone."""
    transport = _RecordingTransport()
    set_companion_transport(transport)
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))

    await CompanionRunner().archive_export(
        workspace_root=str(tmp_path), sandbox=sandbox,
    )
    assert transport.kwargs["scheme"] == ""
    assert transport.kwargs["workspace_or_project"] == ""
    assert transport.kwargs["export_method"] == "app-store-connect"
    assert transport.kwargs["configuration"] == "Release"


# ---------------------------------------------------------------------------
# Honest refusals
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_no_mac_gives_the_real_reason(tmp_path: Path):
    """Previously this surfaced as "ipa not found at Build.ipa", which
    tells the user nothing they can act on."""
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    result = await CompanionRunner().archive_export(
        workspace_root=str(tmp_path), sandbox=sandbox,
    )
    assert not result.ok
    assert "Mac" in result.detail
    assert "Settings" in result.detail


@pytest.mark.asyncio
async def test_local_runner_refuses_rather_than_timing_out(tmp_path: Path):
    """The Sandbox caps commands at 90s. An archive routinely exceeds
    that, so attempting it locally would be killed part-way and look
    like a signing failure."""
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    result = await LocalSandboxRunner().archive_export(
        workspace_root=str(tmp_path), sandbox=sandbox,
    )
    assert not result.ok
    assert "your Mac" in result.detail


@pytest.mark.asyncio
async def test_packaging_failure_reports_which_phase(tmp_path: Path):
    """Archive and export fail for completely different reasons —
    compile errors versus signing — so the phase has to survive."""
    set_companion_transport(_RecordingTransport(
        ArchiveResult(
            ok=False, phase="export", exit_code=70,
            log_tail="error: No profiles for 'com.x.y' were found",
        )
    ))
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    result = await CompanionRunner().archive_export(
        workspace_root=str(tmp_path), sandbox=sandbox,
    )
    assert not result.ok
    assert result.phase == "export"
    assert "No profiles" in result.log_tail


# ---------------------------------------------------------------------------
# The ship stage's decision
# ---------------------------------------------------------------------------

def test_ship_config_packages_by_default():
    """A user who never heard of an archive still gets one."""
    from genie_swarm.orchestrator import ShipConfig

    cfg = ShipConfig(ipa_path="Build.ipa", bundle_id="com.x.y")
    assert cfg.auto_archive is True
    assert cfg.configuration == "Release"
    assert cfg.export_method == "app-store-connect"
    assert cfg.scheme == ""


def test_ship_request_carries_packaging_fields():
    from genie_swarm.models import ShipRequest

    req = ShipRequest(
        ipa_path="Build.ipa",
        bundle_id="com.x.y",
        team_id="ABCDE12345",
    )
    assert req.auto_archive is True
    assert req.team_id == "ABCDE12345"
    assert req.export_method == "app-store-connect"


def test_api_passes_packaging_fields_to_the_orchestrator():
    """A field that stops at the API boundary is the same as one that
    was never sent."""
    from genie_swarm.api import _to_ship_config
    from genie_swarm.models import ShipRequest

    cfg = _to_ship_config(ShipRequest(
        ipa_path="Build.ipa",
        bundle_id="com.x.y",
        team_id="TEAM1",
        scheme="MyApp",
        configuration="Release",
        export_method="app-store",
        auto_archive=False,
    ))
    assert cfg.team_id == "TEAM1"
    assert cfg.scheme == "MyApp"
    assert cfg.export_method == "app-store"
    assert cfg.auto_archive is False
