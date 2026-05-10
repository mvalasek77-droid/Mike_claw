"""Xcode-flavoured tools — only meaningful when the runner has macOS + Xcode."""
from __future__ import annotations

from typing import Any

from .base import Tool, ToolContext
from .shell import RunShell  # re-uses sandbox.run plumbing
from ..sandbox import Sandbox


class XcodeBuild(Tool):
    name = "xcodebuild"
    description = (
        "Run xcodebuild against a workspace or project. Returns compiler "
        "diagnostics summarised by xcpretty if installed, raw otherwise."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "scheme": {"type": "string"},
                "destination": {
                    "type": "string",
                    "default": "platform=iOS Simulator,name=iPhone 16,OS=latest",
                },
                "configuration": {"type": "string", "default": "Debug"},
                "action": {
                    "type": "string",
                    "enum": ["build", "clean", "test", "archive"],
                    "default": "build",
                },
                "workspace_or_project": {"type": "string"},
            },
            "required": ["scheme", "workspace_or_project"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        wp = args["workspace_or_project"]
        flag = "-workspace" if wp.endswith(".xcworkspace") else "-project"
        cmd = [
            "xcodebuild", flag, wp,
            "-scheme", args["scheme"],
            "-configuration", args.get("configuration", "Debug"),
            "-destination", args.get("destination", "platform=iOS Simulator,name=iPhone 16,OS=latest"),
            args.get("action", "build"),
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
        ]
        result = await sandbox.run(cmd)
        # If xcpretty is on $PATH, pipe through it for human-readable output.
        if result.ok or "error:" in result.stdout:
            return result.stdout[-12_000:]
        return f"exit={result.exit_code}\n{result.stderr[-6000:]}\n{result.stdout[-6000:]}"


class SwiftLint(Tool):
    name = "swiftlint"
    description = "Run swiftlint against the workspace. Returns the JSON report."

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {"path": {"type": "string", "default": "."}},
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        result = await sandbox.run(["swiftlint", "lint", "--reporter", "json", args.get("path", ".")])
        return result.stdout or result.stderr or "(empty)"


class XcrunSimctl(Tool):
    name = "simctl"
    description = "Drive the iOS Simulator via xcrun simctl (boot, install, launch, screenshot)."

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "subcommand": {"type": "string"},
                "args": {"type": "array", "items": {"type": "string"}, "default": []},
            },
            "required": ["subcommand"],
            "additionalProperties": False,
        }

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        argv = ["xcrun", "simctl", args["subcommand"], *args.get("args", [])]
        result = await sandbox.run(argv)
        return result.stdout or result.stderr or "(empty)"
