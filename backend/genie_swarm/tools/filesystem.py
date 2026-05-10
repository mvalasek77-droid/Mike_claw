"""Filesystem tools — what every coding agent needs."""
from __future__ import annotations

from typing import Any

from .base import Tool, ToolContext
from ..sandbox import Sandbox


class ReadFile(Tool):
    name = "read_file"
    description = "Read a UTF-8 text file from the workspace and return its contents."

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Workspace-relative path."},
                "max_bytes": {"type": "integer", "default": 200_000},
            },
            "required": ["path"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        body = sandbox.read_text(args["path"])
        cap = int(args.get("max_bytes", 200_000))
        if len(body) > cap:
            body = body[:cap] + f"\n... [truncated at {cap} bytes]"
        return body


class WriteFile(Tool):
    name = "write_file"
    description = (
        "Create or overwrite a file in the workspace. "
        "Returns a confirmation with byte count."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "body": {"type": "string"},
            },
            "required": ["path", "body"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        sandbox.write_text(args["path"], args["body"])
        return f"wrote {len(args['body'])} bytes → {args['path']}"


class EditFile(Tool):
    """Targeted patch: replace `old` with `new` in `path`. Mirrors Claude
    Code's Edit tool — fails if `old` isn't found exactly once."""

    name = "edit_file"
    description = (
        "Replace exactly one occurrence of `old` with `new` in `path`. "
        "Use this for surgical edits; use write_file for new files or full "
        "rewrites. Fails loudly if `old` is missing or appears multiple times."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "old": {"type": "string"},
                "new": {"type": "string"},
                "replace_all": {"type": "boolean", "default": False},
            },
            "required": ["path", "old", "new"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        body = sandbox.read_text(args["path"])
        old, new = args["old"], args["new"]
        replace_all = bool(args.get("replace_all", False))
        count = body.count(old)
        if count == 0:
            raise RuntimeError(f"`old` not found in {args['path']}")
        if count > 1 and not replace_all:
            raise RuntimeError(
                f"`old` matches {count} places in {args['path']}; pass replace_all=true"
            )
        body = body.replace(old, new) if replace_all else body.replace(old, new, 1)
        sandbox.write_text(args["path"], body)
        return f"edited {args['path']} ({count} replacement{'s' if count != 1 else ''})"


class ListDir(Tool):
    name = "list_dir"
    description = "List files in a workspace directory."

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {"path": {"type": "string", "default": "."}},
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        return "\n".join(sandbox.list_dir(args.get("path", ".")))
