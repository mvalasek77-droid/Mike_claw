"""Cross-build artifact recall.

Lets an agent fetch a file from a previously successful project's
workspace by path-substring search. Two tools:

  * `find_artifact(query)` — returns matching paths across all
    previously recorded successful projects, newest first.
  * `recall_artifact(job_id, path)` — returns the file's contents.

We anchor every lookup at `workspace_root` (the orchestrator's per-
job sandbox root). Memory's `recent_projects(...)` gives us the list
of past successful job ids; we read files directly off their on-disk
workspaces. The sandbox boundary still applies — we resolve the
target through a fresh sandbox rooted at the *other* job's workspace
so a path-traversal escape is caught.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from .base import Tool, ToolContext
from ..memory import Memory
from ..sandbox import Sandbox, SandboxPolicy


def _workspace_root_for(ctx: ToolContext) -> Path:
    """`ctx.workspace` is the *current job's* workspace dir; its
    parent is the cross-job root. We never recall from jobs outside
    that root, so the sandbox boundary holds."""
    return Path(ctx.workspace).parent


class FindArtifact(Tool):
    name = "find_artifact"
    description = (
        "Search file paths across previously successful CodeGenie "
        "builds. Returns up to N path lines, newest project first. "
        "Pair with recall_artifact to read the contents."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Substring to match against the file path."},
                "limit": {"type": "integer", "default": 20},
                "include_failed": {"type": "boolean", "default": False},
            },
            "required": ["query"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        query = args["query"].lower()
        limit = int(args.get("limit", 20))
        include_failed = bool(args.get("include_failed", False))
        root = _workspace_root_for(ctx)

        mem = Memory(root)
        projects = mem.recent_projects(limit=50)
        if not include_failed:
            projects = [p for p in projects if p.succeeded]

        hits: list[str] = []
        for proj in projects:
            wp = root / proj.job_id
            if not wp.is_dir() or proj.job_id == Path(ctx.workspace).name:
                continue  # skip the current job's own workspace
            for f in wp.rglob("*"):
                if not f.is_file():
                    continue
                parts = f.relative_to(wp).parts
                if not parts or parts[0] in {".codegenie", ".git"}:
                    continue
                rel = str(f.relative_to(wp))
                if query in rel.lower():
                    hits.append(f"{proj.job_id} :: {rel}    ({proj.title})")
                    if len(hits) >= limit:
                        break
            if len(hits) >= limit:
                break
        return "\n".join(hits) if hits else "(no matches)"


class RecallArtifact(Tool):
    name = "recall_artifact"
    description = (
        "Read a file from a previously built project's workspace. "
        "Use the (job_id, path) tuple returned by find_artifact."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "job_id": {"type": "string"},
                "path": {"type": "string"},
                "max_bytes": {"type": "integer", "default": 100_000},
            },
            "required": ["job_id", "path"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        root = _workspace_root_for(ctx)
        target_workspace = (root / args["job_id"]).resolve()
        try:
            target_workspace.relative_to(root.resolve())
        except ValueError:
            raise RuntimeError("job_id resolves outside the workspace root")
        if not target_workspace.is_dir():
            raise FileNotFoundError(f"no workspace for {args['job_id']!r}")

        # Fresh sandbox rooted at the other job's workspace gives us
        # path-traversal protection for free.
        other = Sandbox(SandboxPolicy(workspace=target_workspace))
        body = other.read_text(args["path"])
        cap = int(args.get("max_bytes", 100_000))
        if len(body) > cap:
            body = body[:cap] + f"\n... [truncated at {cap} bytes]"
        return body
