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
import json
import plistlib
import shutil
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import AsyncIterator, Awaitable, Callable, Protocol

from .sandbox import Sandbox

# An archive of a real app routinely runs for several minutes, and the
# export that follows re-signs every framework. The Sandbox's 90s cap
# is right for agent tool calls and wrong for this, so packaging gets
# its own ceiling — generous enough to finish, short enough that a
# genuinely wedged xcodebuild still surfaces as a failure.
ARCHIVE_TIMEOUT_S = 45 * 60
EXPORT_TIMEOUT_S = 20 * 60
_LIST_TIMEOUT_S = 120


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


@dataclass
class ArchiveResult:
    """Outcome of turning generated source into a signed .ipa.

    `ipa_path` is workspace-relative because everything downstream
    addresses files through the Sandbox, which rejects absolute paths.
    """
    ok: bool
    ipa_path: str = ""
    phase: str = ""           # "archive" | "export" — where it stopped
    exit_code: int = 0
    log_tail: str = ""
    scheme: str = ""
    detail: str = ""


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
    async def archive_export(
        self,
        *,
        workspace_root: str,
        team_id: str = "",
        scheme: str = "",
        workspace_or_project: str = "",
        configuration: str = "Release",
        export_method: str = "app-store-connect",
        asc_api_key_id: str = "",
        asc_api_issuer_id: str = "",
        asc_api_key_path: str = "",
        sandbox: Sandbox,
        on_line: Callable[[str], Awaitable[None]] | None = None,
    ) -> "ArchiveResult":
        """Archive and export a signed App Store .ipa."""
        ...

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

    async def archive_export(
        self, *, workspace_root, team_id="", scheme="", workspace_or_project="",
        configuration="Release", export_method="app-store-connect",
        asc_api_key_id="", asc_api_issuer_id="", asc_api_key_path="",
        sandbox, on_line=None,
    ) -> ArchiveResult:
        transport = _transport_for_runner()
        if transport is None:
            # Degrade the same way `xcodebuild` and `simctl` do. On a
            # macOS host this packages the app with the local Xcode; on
            # a host without one it returns a refusal naming the real
            # reason. Hard-failing here used to make packaging
            # impossible on every deployment, because nothing outside
            # the tests ever registers a transport.
            return await LocalSandboxRunner().archive_export(
                workspace_root=workspace_root,
                team_id=team_id,
                scheme=scheme,
                workspace_or_project=workspace_or_project,
                configuration=configuration,
                export_method=export_method,
                asc_api_key_id=asc_api_key_id,
                asc_api_issuer_id=asc_api_issuer_id,
                asc_api_key_path=asc_api_key_path,
                sandbox=sandbox,
                on_line=on_line,
            )
        return await transport.archive_export(
            workspace_root=workspace_root,
            team_id=team_id,
            scheme=scheme,
            workspace_or_project=workspace_or_project,
            configuration=configuration,
            export_method=export_method,
            asc_api_key_id=asc_api_key_id,
            asc_api_issuer_id=asc_api_issuer_id,
            asc_api_key_path=asc_api_key_path,
            on_line=on_line,
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

    async def archive_export(
        self, *, workspace_root, team_id="", scheme="", workspace_or_project="",
        configuration="Release", export_method="app-store-connect",
        asc_api_key_id="", asc_api_issuer_id="", asc_api_key_path="",
        sandbox, on_line=None,
    ) -> ArchiveResult:
        """Archive and export a signed .ipa using the host's own Xcode.

        CodeGenie's backend is meant to run on macOS, so when Xcode is
        right here the honest thing is to use it rather than insist on
        a paired Mac that would only run the same commands.

        This deliberately does not go through `Sandbox.run`: that caps
        every command at 90 seconds, which an archive comfortably
        exceeds, so routing packaging through it would kill the build
        part-way and report it as a signing failure. Containment is
        still enforced — every path below is resolved through
        `sandbox.safe_path`, and commands are spawned as argv lists
        with no shell, so neither a crafted scheme name nor a project
        path can reach outside the workspace.

        On a host without Xcode this returns a refusal naming the real
        reason instead of attempting a build that cannot work.
        """
        if shutil.which("xcodebuild") is None:
            return ArchiveResult(
                ok=False, phase="archive",
                detail=(
                    "This build server has no Xcode, so it cannot package "
                    "your app here. Packaging needs a Mac — pair your Mac "
                    "in Settings and try again."
                ),
            )

        try:
            root = sandbox.safe_path(workspace_root)
        except Exception as exc:  # noqa: BLE001 — SandboxViolation or bad path
            return ArchiveResult(
                ok=False, phase="archive",
                detail=f"Cannot read the project folder: {exc}",
            )

        project = workspace_or_project or _detect_project(root)
        if not project:
            return ArchiveResult(
                ok=False, phase="archive",
                detail=(
                    "No Xcode project found in the generated app, so there "
                    "is nothing to package."
                ),
            )
        try:
            project_path = sandbox.safe_path(
                project if Path(project).is_absolute() else root / project
            )
        except Exception as exc:  # noqa: BLE001
            return ArchiveResult(
                ok=False, phase="archive",
                detail=f"Project path is not inside the workspace: {exc}",
            )
        flag = "-workspace" if project_path.suffix == ".xcworkspace" else "-project"

        resolved_scheme = scheme or await _detect_scheme(project_path, flag, root)
        if not resolved_scheme:
            return ArchiveResult(
                ok=False, phase="archive",
                detail=(
                    "Could not work out which scheme to build. Open the "
                    "project in Xcode once and make a scheme shared."
                ),
            )

        auth = _auth_args(
            asc_api_key_id, asc_api_issuer_id, asc_api_key_path, sandbox,
        )
        # The scheme reaches us from the client, so it must not be able
        # to steer the archive out of the workspace via a name like
        # "../../etc/x". The argv is already injection-proof (no shell),
        # but the path built from it is not.
        try:
            archive_path = sandbox.safe_path(
                Path("build") / f"{resolved_scheme}.xcarchive"
            )
            export_dir = sandbox.safe_path(Path("build") / "export")
        except Exception as exc:  # noqa: BLE001
            return ArchiveResult(
                ok=False, phase="archive", scheme=resolved_scheme,
                detail=f"Scheme name is not usable as a folder: {exc}",
            )
        archive_path.parent.mkdir(parents=True, exist_ok=True)

        code, log = await _stream_argv(
            [
                "xcodebuild", "archive",
                flag, str(project_path),
                "-scheme", resolved_scheme,
                "-configuration", configuration,
                "-destination", "generic/platform=iOS",
                "-archivePath", str(archive_path),
                "-allowProvisioningUpdates",
                *(["DEVELOPMENT_TEAM=" + team_id] if team_id else []),
                *auth,
            ],
            cwd=root, on_line=on_line, timeout_s=ARCHIVE_TIMEOUT_S,
        )
        if code != 0 or not archive_path.exists():
            return ArchiveResult(
                ok=False, phase="archive", exit_code=code,
                log_tail=log[-4096:], scheme=resolved_scheme,
                detail=_explain_failure("archive", log),
            )

        options_path = root / "build" / "ExportOptions.plist"
        options: dict[str, object] = {
            "method": export_method,
            "signingStyle": "automatic",
            "destination": "export",
        }
        if team_id:
            options["teamID"] = team_id
        options_path.write_bytes(plistlib.dumps(options))

        code, log = await _stream_argv(
            [
                "xcodebuild", "-exportArchive",
                "-archivePath", str(archive_path),
                "-exportPath", str(export_dir),
                "-exportOptionsPlist", str(options_path),
                "-allowProvisioningUpdates",
                *auth,
            ],
            cwd=root, on_line=on_line, timeout_s=EXPORT_TIMEOUT_S,
        )
        ipa = next(iter(sorted(export_dir.glob("*.ipa"))), None) if export_dir.exists() else None
        if code != 0 or ipa is None:
            return ArchiveResult(
                ok=False, phase="export", exit_code=code,
                log_tail=log[-4096:], scheme=resolved_scheme,
                detail=_explain_failure("export", log),
            )

        # Downstream addresses files through the Sandbox, which rejects
        # absolute paths, so hand back a workspace-relative one.
        return ArchiveResult(
            ok=True,
            ipa_path=str(ipa.relative_to(root)),
            phase="export",
            scheme=resolved_scheme,
            log_tail=log[-4096:],
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
# Packaging helpers
# ---------------------------------------------------------------------------


def _detect_project(root: Path) -> str:
    """Find the thing to build. A workspace wins over a bare project
    because when both exist the workspace is the one with the
    dependencies wired in."""
    for pattern in ("*.xcworkspace", "*.xcodeproj"):
        found = sorted(p for p in root.glob(pattern) if not p.name.startswith("."))
        if found:
            return found[0].name
    for pattern in ("*/*.xcworkspace", "*/*.xcodeproj"):
        found = sorted(p for p in root.glob(pattern) if not p.name.startswith("."))
        if found:
            return str(found[0].relative_to(root))
    return ""


async def _detect_scheme(project_path: Path, flag: str, cwd: Path) -> str:
    """Ask xcodebuild what schemes exist rather than guessing a name.

    A guessed scheme fails with "scheme not found", which reads to a
    first-time user like their app is broken."""
    code, out = await _stream_argv(
        ["xcodebuild", "-list", "-json", flag, str(project_path)],
        cwd=cwd, on_line=None, timeout_s=_LIST_TIMEOUT_S,
    )
    if code != 0:
        return ""
    # `-list -json` can still print warnings before the JSON body.
    start = out.find("{")
    if start < 0:
        return ""
    try:
        parsed = json.loads(out[start:])
    except json.JSONDecodeError:
        return ""
    container = parsed.get("workspace") or parsed.get("project") or {}
    schemes = [s for s in container.get("schemes", []) if isinstance(s, str)]
    if not schemes:
        return ""
    # Test schemes archive to nothing useful; prefer a real app scheme.
    preferred = [s for s in schemes if not s.lower().endswith(("tests", "uitests"))]
    return (preferred or schemes)[0]


def _auth_args(
    key_id: str, issuer_id: str, key_path: str, sandbox: Sandbox,
) -> list[str]:
    """Credentials that let Xcode create the certificate and profile on
    its own. Without them `-allowProvisioningUpdates` has nothing to
    authenticate with and signing fails with a profile error."""
    if not (key_id and issuer_id and key_path):
        return []
    try:
        resolved = sandbox.safe_path(key_path)
    except Exception:  # noqa: BLE001 — a bad key path must not crash packaging
        return []
    if not resolved.exists():
        return []
    return [
        "-authenticationKeyID", key_id,
        "-authenticationKeyIssuerID", issuer_id,
        "-authenticationKeyPath", str(resolved),
    ]


def _explain_failure(phase: str, log: str) -> str:
    """Turn xcodebuild's output into something a first-time developer
    can act on. The raw tail is still carried on the result for anyone
    who wants it."""
    low = log.lower()
    if "no profiles for" in low or "no signing certificate" in low:
        return (
            "Xcode could not create a signing profile for this app. Check "
            "that your Apple Developer membership is active and that the "
            "bundle ID is not already registered to another team."
        )
    if "no account for team" in low:
        return (
            "Your Apple Developer team is not signed in on this Mac. Open "
            "Xcode, go to Settings, Accounts, and add your Apple ID."
        )
    if "requires a development team" in low:
        return (
            "This app has no development team set. Add your Team ID in "
            "CodeGenie's Apple settings and try again."
        )
    if "timed out after" in low:
        return (
            f"Packaging took too long during {phase} and was stopped. This "
            "usually means Xcode is waiting on something — try again with "
            "Xcode already open."
        )
    if phase == "archive":
        return (
            "The app did not compile, so there was nothing to package. The "
            "build log below shows the first error."
        )
    return (
        "The app compiled but could not be signed and exported. The export "
        "log below shows why."
    )


async def _stream_argv(
    argv: list[str],
    *,
    cwd: Path,
    on_line: Callable[[str], Awaitable[None]] | None,
    timeout_s: float,
) -> tuple[int, str]:
    """Run a long command, forwarding each line as it appears.

    Archives run for minutes; without streaming the UI looks hung, and
    a user who thinks it hung force-quits part-way through signing.
    """
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=str(cwd),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except (FileNotFoundError, NotADirectoryError, PermissionError) as exc:
        return 127, f"could not start {argv[0]}: {exc}"

    captured: list[str] = []

    async def pump() -> None:
        assert proc.stdout is not None
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip("\n")
            if not line:
                continue
            captured.append(line)
            if len(captured) > 4000:  # keep memory bounded on noisy builds
                del captured[: len(captured) // 2]
            if on_line is not None:
                await on_line(line)

    try:
        await asyncio.wait_for(pump(), timeout=timeout_s)
        await asyncio.wait_for(proc.wait(), timeout=60)
    except asyncio.TimeoutError:
        captured.append(f"timed out after {int(timeout_s)}s")
        try:
            proc.kill()
            await proc.wait()
        except ProcessLookupError:
            pass
        return 124, "\n".join(captured)

    return proc.returncode or 0, "\n".join(captured)


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

    async def archive_export(
        self, *, workspace_root: str, team_id: str, scheme: str,
        workspace_or_project: str, configuration: str, export_method: str,
        asc_api_key_id: str, asc_api_issuer_id: str, asc_api_key_path: str,
        on_line: Callable[[str], Awaitable[None]] | None,
    ) -> "ArchiveResult": ...

    async def simctl(self, *, subcommand: str, args: list[str]) -> RunnerResult: ...


_transport: CompanionTransport | None = None


def set_companion_transport(transport: CompanionTransport | None) -> None:
    """Wire a live companion bridge in (or remove it). Production
    deployments call this once at startup; tests substitute a fake."""
    global _transport
    _transport = transport


def _transport_for_runner() -> CompanionTransport | None:
    return _transport
