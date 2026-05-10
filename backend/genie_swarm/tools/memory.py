"""Memory tools — let agents remember and recall facts across builds.

The orchestrator threads a `Memory` instance into each tool call's
`ToolContext` via a per-call attribute, so tests can swap in a
temp-directory memory without touching globals.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from .base import Tool, ToolContext
from ..memory import Memory
from ..sandbox import Sandbox


def _memory_for(ctx: ToolContext) -> Memory:
    """Resolve the memory instance for this job. We anchor at the
    workspace root so every job's memory lives next to its files."""
    return Memory(Path(ctx.workspace).parent)


class RememberFact(Tool):
    name = "remember_fact"
    description = (
        "Store a small key/value preference CodeGenie should remember "
        "for future builds (palette tendencies, naming style, package "
        "choices, etc.). Use sparingly — one stable fact per call."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "key":   {"type": "string", "description": "Short stable identifier, e.g. 'preferred_palette'."},
                "value": {"type": "string"},
                "confidence": {"type": "number", "minimum": 0, "maximum": 1, "default": 0.7},
            },
            "required": ["key", "value"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        mem = _memory_for(ctx)
        mem.remember(
            args["key"], args["value"],
            confidence=float(args.get("confidence", 0.7)),
            source=ctx.agent or "agent",
        )
        return f"remembered {args['key']!r}"


class RecallMemory(Tool):
    name = "recall_memory"
    description = (
        "Retrieve previously remembered facts. Returns up to N matches "
        "sorted by confidence × recency."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 8},
            },
            "required": ["query"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        mem = _memory_for(ctx)
        rows = mem.recall(args["query"], limit=int(args.get("limit", 8)))
        if not rows:
            return "(no matches)"
        return "\n".join(
            f"- {r.key}: {r.value} (confidence {r.confidence:.2f}, source {r.source})"
            for r in rows
        )


class NoteDecision(Tool):
    name = "note_decision"
    description = (
        "Record a reasoning step CodeGenie should be able to explain "
        "later — e.g. why a particular library was rejected. Tied to "
        "the current job."
    )

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "context":  {"type": "string"},
                "decision": {"type": "string"},
            },
            "required": ["context", "decision"],
            "additionalProperties": False,
        }

    async def run(self, args: dict[str, Any], sandbox: Sandbox, ctx: ToolContext) -> str:
        mem = _memory_for(ctx)
        mem.note_decision(ctx.job_id, args["context"], args["decision"])
        return "decision noted"
