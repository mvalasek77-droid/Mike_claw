"""Tool registry + filesystem tools."""
from __future__ import annotations

import pytest

from genie_swarm.models import ToolCall
from genie_swarm.sandbox import Sandbox
from genie_swarm.tools import ToolRegistry
from genie_swarm.tools.base import ToolContext, ToolError
from genie_swarm.tools.filesystem import EditFile, ListDir, ReadFile, WriteFile


@pytest.fixture
def registry() -> ToolRegistry:
    r = ToolRegistry()
    for tool in (ReadFile(), WriteFile(), EditFile(), ListDir()):
        r.register(tool)
    return r


@pytest.fixture
def ctx() -> ToolContext:
    return ToolContext(job_id="t", agent="tester", workspace="/tmp")


# --------------------------------------------------------------------------- #
# Registry
# --------------------------------------------------------------------------- #

def test_registry_rejects_duplicate_names(registry: ToolRegistry):
    with pytest.raises(ToolError):
        registry.register(ReadFile())


def test_registry_get_unknown_raises(registry: ToolRegistry):
    with pytest.raises(ToolError):
        registry.get("nope")


# --------------------------------------------------------------------------- #
# Filesystem tools
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_write_file_then_read_file(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    write = await registry.invoke(ToolCall(name="write_file", arguments={"path": "a.txt", "body": "hello"}), sandbox, ctx)
    assert write.ok
    read = await registry.invoke(ToolCall(name="read_file", arguments={"path": "a.txt"}), sandbox, ctx)
    assert read.ok
    assert "hello" in read.content


@pytest.mark.asyncio
async def test_edit_file_unique_replacement(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    sandbox.write_text("a.txt", "old text once")
    result = await registry.invoke(
        ToolCall(name="edit_file", arguments={"path": "a.txt", "old": "old", "new": "new"}),
        sandbox, ctx,
    )
    assert result.ok
    assert sandbox.read_text("a.txt") == "new text once"


@pytest.mark.asyncio
async def test_edit_file_fails_on_multiple_matches_without_replace_all(
    registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext
):
    sandbox.write_text("a.txt", "old old old")
    result = await registry.invoke(
        ToolCall(name="edit_file", arguments={"path": "a.txt", "old": "old", "new": "new"}),
        sandbox, ctx,
    )
    assert not result.ok
    assert "old.replace_all=true" in result.content or "matches" in result.content.lower()


@pytest.mark.asyncio
async def test_edit_file_replace_all(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    sandbox.write_text("a.txt", "old old old")
    result = await registry.invoke(
        ToolCall(name="edit_file", arguments={
            "path": "a.txt", "old": "old", "new": "new", "replace_all": True
        }),
        sandbox, ctx,
    )
    assert result.ok
    assert sandbox.read_text("a.txt") == "new new new"


@pytest.mark.asyncio
async def test_edit_file_fails_when_old_missing(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    sandbox.write_text("a.txt", "hello")
    result = await registry.invoke(
        ToolCall(name="edit_file", arguments={"path": "a.txt", "old": "nope", "new": "x"}),
        sandbox, ctx,
    )
    assert not result.ok


@pytest.mark.asyncio
async def test_invalid_arguments_rejected(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    # write_file requires `body`; omit it.
    result = await registry.invoke(
        ToolCall(name="write_file", arguments={"path": "x.txt"}),
        sandbox, ctx,
    )
    assert not result.ok
    assert result.metadata.get("kind") == "schema_violation"


@pytest.mark.asyncio
async def test_sandbox_violation_surfaces(registry: ToolRegistry, sandbox: Sandbox, ctx: ToolContext):
    result = await registry.invoke(
        ToolCall(name="read_file", arguments={"path": "../etc/passwd"}),
        sandbox, ctx,
    )
    assert not result.ok
    assert result.metadata.get("kind") == "sandbox_violation"
