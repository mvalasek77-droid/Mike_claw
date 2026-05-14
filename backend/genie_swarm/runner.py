"""Mac runner abstraction.

Lets the orchestrator route Apple-toolchain calls (`xcodebuild`,
`xcrun simctl`, screenshot capture, etc.) to a real Mac while keeping
the rest of the swarm in its existing sandbox. Two strategies share
one interface:

  * **`CompanionRunner`** — talks to a paired Mac companion daemon.
    Used for production. Streams build output line-by-line so the iOS
    transcript shows progress as Apple's toolchain emits it.
  * **`LocalSandboxRunner`** — falls back to `Sandbox.run` for
    development on macOS-where-CodeGenie-is-installed-natively, and
    for tests on Linux (where the calls would fail but the routing
    decisions are still verifiable).

The orchestrator never imports either concrete class directly — it
calls `MacRunner.resolve(...)` which picks the strategy based on
whether a companion is paired for this job.
"""
from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, Awaitable, Callable, Protocol

from .sandbox import Sandbox


# ---------------------------------------------------------------------------
# Public protocol
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RunnerResult:
    """Outcome of an Apple-toolchain invocation routed through the runner."""
    ok: bool
    exit_code: int
    stdout_tail: str          # last ~4KB of combined stdout/stderr
    duration_ms: int
    strategy: str             # "companion" | "local-sandbox"


class MacRunner(ABC):
    """Abstract Mac-toolchain dispatcher."""

    @property
    @abstractmethod
    def strategy(self) -> str: ...

    @abstractmethod
    async def xcodebuild(
        self,
        *,
        workspace_or_project: str,
        scheme: str,
        action: str = "build",
        destination: str = "platform=iOS Simulator,name=iPhone 16,OS=latest",
        configuration: str = "Debug",
        sandbox: Sandbox,
        on_line: Callable[[str], Awaitable[None]] | None = None,
    ) -> RunnerResult: ...

    @abstractmethod
    async def simctl(
        self,
        *,
        subcommand: str,
        args: list[str],
        sandbox: Sandbox,
    ) -> RunnerResult: ...

    @classmethod
    def resolve(cls, *, job_id: str, companion_paired: bool) -> "MacRunner":
        """Pick the right strategy.

        * If a companion is paired for this job → `CompanionRunner` so
          the call lands on a real Mac.
        * Otherwise → `LocalSandboxRunner` so the orchestrator's tests
          run cleanly on Linux and macOS-native installs still work.

        The `job_id` parameter is reserved for per-job runner pinning
        (e.g. multiple parallel forks each with their own companion).
        Today both implementations are stateless.
        """
        if companion_paired:
            return CompanionRunner()
        return LocalSandboxRunner()


# ---------------------------------------------------------------------------
# Companion strategy (production)
# ---------------------------------------------------------------------------


class CompanionRunner(MacRunner):
    """Routes through the Mac companion daemon. Falls back to the
    local sandbox if the companion call raises — we'd rather degrade
    than crash the run."""

    @property
    def strategy(self) -> str:
        return "companion"

    async def xcodebuild(
        self, *, workspace_or_project, scheme, action="build",
        destination="platform=iOS Simulator,name=iPhone 16,OS=latest",
        configuration="Debug", sandbox, on_line=None,
    ) -> RunnerResult:
        # Real companion dispatch is wired in `CompanionTransport`
        # below — that lives in the orchestrator's pause-gate map.
        # When the transport is unavailable we degrade.
        transport = _transport_for_runner()
        if transport is None:
            return await LocalSandboxRunner().xcodebuild(
                workspace_or_project=workspace_or_project,
                scheme=scheme, action=action, destination=destination,
                configuration=configuration, sandbox=sandbox, on_line=on_line,
            )
        return await transport.xcodebuild(
            workspace_or_project=workspace_or_project,
            scheme=scheme, action=action, destination=destination,
            configuration=configuration, on_line=on_line,
        )

    async def simctl(self, *, subcommand, args, sandbox) -> RunnerResult:
        transport = _transport_for_runner()
        if transport is None:
            return await LocalSandboxRunner().simctl(
                subcommand=subcommand, args=args, sandbox=sandbox,
            )
        return await transport.simctl(subcommand=subcommand, args=args)


# ---------------------------------------------------------------------------
# Local fallback (tests + macOS-native installs)
# ---------------------------------------------------------------------------


class LocalSandboxRunner(MacRunner):
    """Runs the toolchain in-process via `Sandbox.run`. The Sandbox
    enforces RSS + timeout + path-traversal protection so an attacker-
    controlled build can't escape. On Linux these calls predictably
    fail with `xcrun not found` — the return value is still
    structured so callers can branch on `ok=False`."""

    @property
    def strategy(self) -> str:
        return "local-sandbox"

    async def xcodebuild(
        self, *, workspace_or_project, scheme, action="build",
        destination="platform=iOS Simulator,name=iPhone 16,OS=latest",
        configuration="Debug", sandbox, on_line=None,
    ) -> RunnerResult:
        flag = "-workspace" if workspace_or_project.endswith(".xcworkspace") else "-project"
        argv = [
            "xcodebuild", flag, workspace_or_project,
            "-scheme", scheme,
            "-configuration", configuration,
            "-destination", destination,
            action,
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO",
        ]
        import time
        t0 = time.perf_counter()
        result = await sandbox.run(argv)
        duration_ms = int((time.perf_counter() - t0) * 1000)
        # Best-effort line streaming for the local path: the sandbox
        # already collected stdout; we emit it line-by-line to the
        # callback if one was provided.
        if on_line:
            for line in result.stdout.splitlines():
                await on_line(line)
        return RunnerResult(
            ok=result.ok,
            exit_code=result.exit_code,
            stdout_tail=result.stdout[-4096:],
            duration_ms=duration_ms,
            strategy=self.strategy,
        )

    async def simctl(self, *, subcommand, args, sandbox) -> RunnerResult:
        argv = ["xcrun", "simctl", subcommand, *args]
        import time
        t0 = time.perf_counter()
        result = await sandbox.run(argv)
        return RunnerResult(
            ok=result.ok,
            exit_code=result.exit_code,
            stdout_tail=result.stdout[-4096:],
            duration_ms=int((time.perf_counter() - t0) * 1000),
            strategy=self.strategy,
        )


# ---------------------------------------------------------------------------
# Companion transport hook
# ---------------------------------------------------------------------------


class CompanionTransport(Protocol):
    """Wire shape the companion bridge implements. Kept Protocol-based
    so the orchestrator doesn't pull in iOS-specific bridge code."""

    async def xcodebuild(
        self, *, workspace_or_project: str, scheme: str, action: str,
        destination: str, configuration: str,
        on_line: Callable[[str], Awaitable[None]] | None,
    ) -> RunnerResult: ...

    async def simctl(self, *, subcommand: str, args: list[str]) -> RunnerResult: ...


_transport: CompanionTransport | None = None


def set_companion_transport(transport: CompanionTransport | None) -> None:
    """Wire a live companion bridge in (or remove it). Production
    deployments call this once at startup; tests substitute a fake."""
    global _transport
    _transport = transport


def _transport_for_runner() -> CompanionTransport | None:
    return _transport
