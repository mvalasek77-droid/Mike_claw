"""Sandbox boundary + execution tests."""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.sandbox import Sandbox, SandboxPolicy, SandboxViolation


def test_safe_path_resolves_relative(sandbox: Sandbox, temp_workspace: Path):
    p = sandbox.safe_path("foo/bar.txt")
    assert p == (temp_workspace / "foo/bar.txt").resolve()


def test_safe_path_rejects_escape(sandbox: Sandbox, temp_workspace: Path):
    with pytest.raises(SandboxViolation):
        sandbox.safe_path("../escape.txt")


def test_safe_path_rejects_absolute_outside(sandbox: Sandbox):
    with pytest.raises(SandboxViolation):
        sandbox.safe_path("/etc/passwd")


def test_write_then_read_round_trips(sandbox: Sandbox):
    sandbox.write_text("hello.txt", "world")
    assert sandbox.read_text("hello.txt") == "world"


def test_write_creates_parent_dirs(sandbox: Sandbox, temp_workspace: Path):
    sandbox.write_text("a/b/c/file.txt", "ok")
    assert (temp_workspace / "a/b/c/file.txt").exists()


def test_list_dir(sandbox: Sandbox):
    sandbox.write_text("alpha.txt", "1")
    sandbox.write_text("beta.txt", "2")
    assert sandbox.list_dir(".") == ["alpha.txt", "beta.txt"]


@pytest.mark.asyncio
async def test_run_captures_stdout(sandbox: Sandbox):
    result = await sandbox.run(["echo", "hi"])
    assert result.ok
    assert result.exit_code == 0
    assert "hi" in result.stdout


@pytest.mark.asyncio
async def test_run_returns_nonzero(sandbox: Sandbox):
    result = await sandbox.run(["false"])
    assert not result.ok
    assert result.exit_code != 0


@pytest.mark.asyncio
async def test_run_truncates_huge_output(temp_workspace: Path):
    # 1KB cap so we can prove truncation triggers without a 4MB write.
    sb = Sandbox(SandboxPolicy(workspace=temp_workspace, max_output_bytes=1024, timeout_s=10, max_rss_bytes=None))
    # Generate ~5KB
    result = await sb.run(["sh", "-c", "for i in $(seq 1 1000); do echo line$i; done"])
    assert result.ok
    assert result.truncated
    assert len(result.stdout) <= 1024


@pytest.mark.asyncio
async def test_run_times_out(temp_workspace: Path):
    sb = Sandbox(SandboxPolicy(workspace=temp_workspace, timeout_s=0.5, max_rss_bytes=None))
    result = await sb.run(["sleep", "5"])
    assert not result.ok
    assert result.exit_code == -1
