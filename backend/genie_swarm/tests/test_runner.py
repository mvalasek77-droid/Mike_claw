"""Tests for the Mac runner abstraction.

We never invoke real xcodebuild — these are routing tests. The
goal is to verify that:
  * `MacRunner.resolve` picks the right strategy based on whether a
    companion is paired.
  * `CompanionRunner` calls the registered transport and surfaces its
    result.
  * `CompanionRunner` falls back to the local sandbox when no
    transport is wired.
  * `LocalSandboxRunner` runs argv through the sandbox and returns a
    structured `RunnerResult` even on the host-without-xcrun case
    (which is the test environment, and also the default fallback in
    production when the user hasn't paired a Mac).
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass
from pathlib import Path

import pytest

from genie_swarm.runner import (
    CompanionRunner,
    LocalSandboxRunner,
    MacRunner,
    RunnerResult,
    set_companion_transport,
)
from genie_swarm.sandbox import Sandbox, SandboxPolicy


@pytest.fixture(autouse=True)
def _clear_transport():
    """Every test starts with no companion transport wired."""
    set_companion_transport(None)
    yield
    set_companion_transport(None)


# --------------------------------------------------------------------------- #
# Resolution
# --------------------------------------------------------------------------- #

def test_resolve_picks_local_when_no_companion():
    runner = MacRunner.resolve(job_id="job_abc", companion_paired=False)
    assert isinstance(runner, LocalSandboxRunner)
    assert runner.strategy == "local-sandbox"


def test_resolve_picks_companion_when_paired():
    runner = MacRunner.resolve(job_id="job_abc", companion_paired=True)
    assert isinstance(runner, CompanionRunner)
    assert runner.strategy == "companion"


# --------------------------------------------------------------------------- #
# Companion strategy
# --------------------------------------------------------------------------- #

@dataclass
class _RecordingTransport:
    """A fake CompanionTransport that records every call and replies
    with a canned RunnerResult. Used to verify routing decisions
    without standing up a real Mac bridge."""
    calls: list[tuple] = None
    canned: RunnerResult = RunnerResult(
        ok=True, exit_code=0, stdout_tail="canned",
        duration_ms=1, strategy="companion",
    )

    def __post_init__(self):
        self.calls = []

    async def xcodebuild(self, *, workspace_or_project, scheme, action,
                          destination, configuration, on_line):
        self.calls.append(("xcodebuild", scheme, action))
        if on_line:
            await on_line("** BUILD SUCCEEDED **")
        return self.canned

    async def simctl(self, *, subcommand, args):
        self.calls.append(("simctl", subcommand, tuple(args)))
        return self.canned


@pytest.mark.asyncio
async def test_companion_runner_routes_to_transport(tmp_path: Path):
    transport = _RecordingTransport()
    set_companion_transport(transport)
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))

    captured: list[str] = []
    async def on_line(line: str): captured.append(line)

    result = await CompanionRunner().xcodebuild(
        workspace_or_project="App.xcodeproj",
        scheme="App", action="build",
        destination="platform=iOS Simulator,name=iPhone 16",
        configuration="Debug",
        sandbox=sandbox,
        on_line=on_line,
    )
    assert result.ok
    assert result.strategy == "companion"
    assert transport.calls == [("xcodebuild", "App", "build")]
    assert "** BUILD SUCCEEDED **" in captured


@pytest.mark.asyncio
async def test_companion_runner_falls_back_when_no_transport(tmp_path: Path):
    """No transport wired → fall back to local sandbox. On Linux the
    local call fails with exit_code != 0; what matters is that we got
    a structured RunnerResult from the local strategy, not an
    exception."""
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))
    result = await CompanionRunner().xcodebuild(
        workspace_or_project="App.xcodeproj",
        scheme="App", action="build",
        destination="platform=iOS Simulator,name=iPhone 16",
        configuration="Debug",
        sandbox=sandbox, on_line=None,
    )
    assert result.strategy == "local-sandbox"


@pytest.mark.asyncio
async def test_companion_runner_routes_simctl(tmp_path: Path):
    transport = _RecordingTransport()
    set_companion_transport(transport)
    sandbox = Sandbox(SandboxPolicy(workspace=tmp_path))

    result = await CompanionRunner().simctl(
        subcommand="boot", args=["iPhone 16"], sandbox=sandbox,
    )
    assert result.ok
    assert transport.calls == [("simctl", "boot", ("iPhone 16",))]


# --------------------------------------------------------------------------- #
# Local fallback
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_local_runner_emits_line_callbacks_in_order(tmp_path: Path):
    """Use a fake xcrun-like script that emits known lines, so we can
    assert the line-streaming contract without depending on the host
    Xcode install."""
    bin_dir = tmp_path / "fakebin"
    bin_dir.mkdir()
    fake = bin_dir / "xcodebuild"
    fake.write_text(
        "#!/usr/bin/env bash\n"
        "echo 'Preparing build'\n"
        "echo 'Compiling Swift sources'\n"
        "echo '** BUILD SUCCEEDED **'\n"
    )
    fake.chmod(0o755)

    import os
    sandbox = Sandbox(SandboxPolicy(
        workspace=tmp_path,
        extra_env={"PATH": f"{bin_dir}:{os.environ['PATH']}"},
    ))
    captured: list[str] = []
    async def on_line(line: str): captured.append(line)

    result = await LocalSandboxRunner().xcodebuild(
        workspace_or_project="App.xcodeproj",
        scheme="App", action="build",
        destination="platform=iOS Simulator,name=iPhone 16",
        configuration="Debug",
        sandbox=sandbox, on_line=on_line,
    )
    assert result.ok
    assert captured[0] == "Preparing build"
    assert captured[-1] == "** BUILD SUCCEEDED **"
