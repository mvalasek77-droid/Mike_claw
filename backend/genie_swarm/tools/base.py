"""Tool plumbing — Claude Code's tool-use protocol, in Python.

A `Tool` exposes:
  * `name`  — what the LLM calls
  * `schema()` — JSONSchema fed to the model so it knows how to call us
  * `run(args, sandbox, ctx)` — the implementation

The orchestrator never invokes a tool directly — it always goes through
the registry, which looks the tool up by name, validates the arguments
against the schema, and runs it inside the sandbox.
"""
from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

import jsonschema

from ..models import ToolCall, ToolResult
from ..sandbox import Sandbox, SandboxViolation


class ToolError(Exception):
    pass


@dataclass
class ToolContext:
    """Per-call context the orchestrator hands to a tool."""
    job_id: str
    agent: str
    workspace: str


class Tool(ABC):
    name: str = ""
    description: str = ""

    @abstractmethod
    def schema(self) -> dict[str, Any]:  # JSONSchema for `arguments`
        ...

    @abstractmethod
    async def run(
        self,
        args: dict[str, Any],
        sandbox: Sandbox,
        ctx: ToolContext,
    ) -> str:
        ...

    # Anthropic & OpenAI both consume the same shape; we ship one render.
    def as_anthropic(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.schema(),
        }

    def as_openai(self) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.schema(),
            },
        }


class ToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, Tool] = {}

    def register(self, tool: Tool) -> Tool:
        if tool.name in self._tools:
            raise ToolError(f"duplicate tool name: {tool.name}")
        self._tools[tool.name] = tool
        return tool

    def get(self, name: str) -> Tool:
        if name not in self._tools:
            raise ToolError(f"unknown tool: {name}")
        return self._tools[name]

    def all(self) -> list[Tool]:
        return list(self._tools.values())

    async def invoke(
        self,
        call: ToolCall,
        sandbox: Sandbox,
        ctx: ToolContext,
    ) -> ToolResult:
        start = time.time()
        try:
            tool = self.get(call.name)
            jsonschema.validate(call.arguments, tool.schema())
            content = await tool.run(call.arguments, sandbox, ctx)
            return ToolResult(
                call_id=call.id,
                ok=True,
                content=content,
                duration_ms=int((time.time() - start) * 1000),
            )
        except SandboxViolation as exc:
            return ToolResult(
                call_id=call.id,
                ok=False,
                content=f"sandbox violation: {exc}",
                duration_ms=int((time.time() - start) * 1000),
                metadata={"kind": "sandbox_violation"},
            )
        except jsonschema.ValidationError as exc:
            return ToolResult(
                call_id=call.id,
                ok=False,
                content=f"invalid arguments: {exc.message}",
                duration_ms=int((time.time() - start) * 1000),
                metadata={"kind": "schema_violation"},
            )
        except Exception as exc:  # noqa: BLE001 — propagate anything to the LLM
            return ToolResult(
                call_id=call.id,
                ok=False,
                content=f"{type(exc).__name__}: {exc}",
                duration_ms=int((time.time() - start) * 1000),
                metadata={"kind": "exception"},
            )


default_registry = ToolRegistry()
