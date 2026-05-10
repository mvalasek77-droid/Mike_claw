"""Shell + search tools."""
from __future__ import annotations

from typing import Any

from .base import Tool, ToolContext
from ..sandbox import Sandbox


class RunShell(Tool):
    name = "shell"
    description = (
        "Run a shell command inside the sandboxed workspace. The command "
        "runs with a 90s timeout and a 1GiB RSS cap by default. Use this "
        "for git, swiftlint, swiftformat, npm, pip, etc."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "command": {"type": "string"},
                "cwd": {"type": "string", "default": "."},
                "stdin": {"type": "string"},
            },
            "required": ["command"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        result = await sandbox.run(
            args["command"],
            cwd=args.get("cwd"),
            stdin=args.get("stdin"),
        )
        out = []
        out.append(f"$ {args['command']}")
        out.append(f"exit={result.exit_code} time={result.duration_ms}ms")
        if result.stdout:
            out.append("--- stdout ---")
            out.append(result.stdout)
        if result.stderr:
            out.append("--- stderr ---")
            out.append(result.stderr)
        if result.truncated:
            out.append("[output truncated]")
        return "\n".join(out)


class Grep(Tool):
    name = "grep"
    description = "Search for a regex pattern across the workspace using ripgrep."

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "pattern": {"type": "string"},
                "glob": {"type": "string"},
                "path": {"type": "string", "default": "."},
                "max_matches": {"type": "integer", "default": 200},
            },
            "required": ["pattern"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        argv = ["rg", "--no-heading", "--line-number", "--color=never"]
        if "glob" in args:
            argv += ["-g", args["glob"]]
        argv += ["-m", str(int(args.get("max_matches", 200)))]
        argv += ["--", args["pattern"], args.get("path", ".")]
        result = await sandbox.run(argv)
        if not result.ok and result.exit_code == 1:
            return "no matches"
        return result.stdout or result.stderr or "(empty)"
