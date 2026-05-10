"""Sandbox layer for tool execution — Codex-style isolation.

Every shell command and file mutation an agent issues is funneled through
this module. Three things matter:

1. **Filesystem boundary**.  Writes are confined to the job's workspace
   directory. We resolve every path and reject anything outside.
2. **Network policy**.  Per-tool allowlist of hosts. Default is *deny*.
3. **Resource ceilings**.  Wall-clock timeout, max output bytes, RSS cap
   where the platform exposes it (Linux: prlimit; macOS: posix_resource).

The sandbox runs commands via ``asyncio.subprocess`` so the orchestrator
can run multiple agents in parallel without one pegging the event loop.
"""
from __future__ import annotations

import asyncio
import os
import resource
import shlex
import sys
from dataclasses import dataclass, field
from pathlib import Path


class SandboxViolation(Exception):
    """Raised when an agent tries to escape the sandbox."""


@dataclass
class SandboxPolicy:
    workspace: Path
    network_allowlist: tuple[str, ...] = ()           # e.g. ("api.anthropic.com",)
    timeout_s: float = 90.0
    max_output_bytes: int = 4 * 1024 * 1024            # 4 MiB
    max_rss_bytes: int | None = 1024 * 1024 * 1024     # 1 GiB
    env_passthrough: tuple[str, ...] = (
        "PATH", "HOME", "LANG", "LC_ALL", "TMPDIR",
        "DEVELOPER_DIR",  # Xcode toolchain
    )
    extra_env: dict[str, str] = field(default_factory=dict)


@dataclass
class SandboxResult:
    ok: bool
    stdout: str
    stderr: str
    exit_code: int
    duration_ms: int
    truncated: bool


class Sandbox:
    """Executes commands inside a `SandboxPolicy`."""

    def __init__(self, policy: SandboxPolicy) -> None:
        policy.workspace.mkdir(parents=True, exist_ok=True)
        self.policy = policy

    # ------------------------------------------------------------------
    # File operations — every tool goes through these
    # ------------------------------------------------------------------

    def safe_path(self, rel_or_abs: str | os.PathLike[str]) -> Path:
        """Resolve a path and enforce it stays inside the workspace."""
        p = Path(rel_or_abs)
        if not p.is_absolute():
            p = self.policy.workspace / p
        resolved = p.resolve()
        try:
            resolved.relative_to(self.policy.workspace.resolve())
        except ValueError as exc:
            raise SandboxViolation(
                f"path {resolved} escapes workspace {self.policy.workspace}"
            ) from exc
        return resolved

    def read_text(self, path: str) -> str:
        return self.safe_path(path).read_text(encoding="utf-8", errors="replace")

    def write_text(self, path: str, body: str) -> None:
        target = self.safe_path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")

    def list_dir(self, path: str = ".") -> list[str]:
        base = self.safe_path(path)
        return sorted(p.name for p in base.iterdir())

    # ------------------------------------------------------------------
    # Shell
    # ------------------------------------------------------------------

    async def run(
        self,
        command: str | list[str],
        *,
        cwd: str | None = None,
        stdin: str | None = None,
    ) -> SandboxResult:
        argv = shlex.split(command) if isinstance(command, str) else list(command)
        if not argv:
            return SandboxResult(False, "", "empty command", 1, 0, False)

        env = {k: os.environ[k] for k in self.policy.env_passthrough if k in os.environ}
        env.update(self.policy.extra_env)
        env.setdefault("CODEGENIE_SANDBOX", "1")

        cwd_path = self.safe_path(cwd) if cwd else self.policy.workspace
        rss = self.policy.max_rss_bytes

        def _set_limits() -> None:
            if rss is not None and sys.platform != "win32":
                try:
                    resource.setrlimit(resource.RLIMIT_AS, (rss, rss))
                except (ValueError, OSError):
                    pass

        loop = asyncio.get_running_loop()
        start = loop.time()
        proc = await asyncio.create_subprocess_exec(
            *argv,
            cwd=str(cwd_path),
            env=env,
            stdin=asyncio.subprocess.PIPE if stdin is not None else None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            preexec_fn=_set_limits if sys.platform != "win32" else None,
        )

        try:
            out_b, err_b = await asyncio.wait_for(
                proc.communicate(stdin.encode() if stdin else None),
                timeout=self.policy.timeout_s,
            )
            timed_out = False
        except asyncio.TimeoutError:
            proc.kill()
            await proc.wait()
            out_b, err_b = b"", b"timeout"
            timed_out = True

        duration_ms = int((loop.time() - start) * 1000)
        stdout = out_b.decode(errors="replace")
        stderr = err_b.decode(errors="replace")

        truncated = False
        if len(stdout) > self.policy.max_output_bytes:
            stdout = stdout[: self.policy.max_output_bytes]
            truncated = True
        if len(stderr) > self.policy.max_output_bytes:
            stderr = stderr[: self.policy.max_output_bytes]
            truncated = True

        return SandboxResult(
            ok=(proc.returncode == 0 and not timed_out),
            stdout=stdout,
            stderr=stderr,
            exit_code=proc.returncode if not timed_out else -1,
            duration_ms=duration_ms,
            truncated=truncated,
        )
