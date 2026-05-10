"""TestFlight uploader tests.

We mock `xcrun altool` by shipping a tiny script onto $PATH that the
sandbox can call. This lets us exercise the validate → upload flow,
the credentials selection logic, and error handling without touching
Apple's servers (or even needing macOS).
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

from genie_swarm.models import ToolCall
from genie_swarm.tools import ToolRegistry
from genie_swarm.tools.base import ToolContext
from genie_swarm.tools.testflight import TestFlightUpload


@pytest.fixture
def fake_xcrun(tmp_path: Path, monkeypatch) -> Path:
    """Create a fake `xcrun` script that records its argv and prints
    a believable altool transcript. Prepend its dir to $PATH so the
    sandbox finds it before the real one."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "if [[ \"$2\" == \"--validate-app\" ]]; then\n"
        "  echo 'No errors validating archive Build.ipa'\n"
        "  exit 0\n"
        "fi\n"
        "if [[ \"$2\" == \"--upload-app\" ]]; then\n"
        "  echo 'No errors uploading Build.ipa'\n"
        "  echo 'Asset received with id ABC123XYZ'\n"
        "  exit 0\n"
        "fi\n"
        "exit 1\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    return bin_dir


@pytest.fixture
def fake_xcrun_failure(tmp_path: Path, monkeypatch) -> Path:
    bin_dir = tmp_path / "fakebin_fail"
    bin_dir.mkdir()
    script = bin_dir / "xcrun"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "echo 'ERROR ITMS-90161: Invalid Provisioning Profile' 1>&2\n"
        "exit 1\n"
    )
    script.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{os.environ['PATH']}")
    return bin_dir


@pytest.fixture
def registry() -> ToolRegistry:
    r = ToolRegistry()
    r.register(TestFlightUpload())
    return r


def _ctx(sandbox) -> ToolContext:
    return ToolContext(job_id="j", agent="integrator", workspace=str(sandbox.policy.workspace))


# --------------------------------------------------------------------------- #
# Happy path
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_upload_with_apple_id_creds(fake_xcrun, registry, sandbox, monkeypatch):
    sandbox.write_text("Build.ipa", "fake binary")
    monkeypatch.setenv("APPLE_ID", "tester@example.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "abcd-efgh-ijkl-mnop")

    result = await registry.invoke(
        ToolCall(name="testflight_upload", arguments={"ipa_path": "Build.ipa"}),
        sandbox, _ctx(sandbox),
    )
    assert result.ok, result.content
    assert "build_id=ABC123XYZ" in result.content
    assert "validate" in result.content
    assert "upload" in result.content


@pytest.mark.asyncio
async def test_upload_skips_validate_when_disabled(fake_xcrun, registry, sandbox, monkeypatch):
    sandbox.write_text("Build.ipa", "fake binary")
    monkeypatch.setenv("APPLE_ID", "tester@example.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "abcd-efgh-ijkl-mnop")

    result = await registry.invoke(
        ToolCall(name="testflight_upload", arguments={"ipa_path": "Build.ipa", "validate": False}),
        sandbox, _ctx(sandbox),
    )
    assert result.ok
    # `upload` should be present, `validate` should not.
    assert "upload" in result.content
    assert "altool --validate-app" not in result.content


# --------------------------------------------------------------------------- #
# Credentials handling
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_upload_fails_without_credentials(fake_xcrun, registry, sandbox, monkeypatch):
    sandbox.write_text("Build.ipa", "fake")
    monkeypatch.delenv("APPLE_ID", raising=False)
    monkeypatch.delenv("APP_SPECIFIC_PASSWORD", raising=False)
    monkeypatch.delenv("ASC_API_KEY_ID", raising=False)

    result = await registry.invoke(
        ToolCall(name="testflight_upload", arguments={"ipa_path": "Build.ipa"}),
        sandbox, _ctx(sandbox),
    )
    assert not result.ok
    assert "credentials" in result.content.lower()


@pytest.mark.asyncio
async def test_upload_fails_when_ipa_missing(fake_xcrun, registry, sandbox, monkeypatch):
    monkeypatch.setenv("APPLE_ID", "x@y.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "p")

    result = await registry.invoke(
        ToolCall(name="testflight_upload", arguments={"ipa_path": "nope.ipa"}),
        sandbox, _ctx(sandbox),
    )
    assert not result.ok
    assert "not found" in result.content.lower()


# --------------------------------------------------------------------------- #
# Apple's failure path surfaces cleanly
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_upload_surfaces_altool_errors(fake_xcrun_failure, registry, sandbox, monkeypatch):
    sandbox.write_text("Build.ipa", "fake")
    monkeypatch.setenv("APPLE_ID", "x@y.com")
    monkeypatch.setenv("APP_SPECIFIC_PASSWORD", "p")

    result = await registry.invoke(
        ToolCall(name="testflight_upload", arguments={"ipa_path": "Build.ipa"}),
        sandbox, _ctx(sandbox),
    )
    assert not result.ok
    assert "ITMS-90161" in result.content or "validate failed" in result.content.lower()
