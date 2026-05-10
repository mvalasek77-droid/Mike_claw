"""Shared pytest fixtures for genie_swarm tests.

We deliberately avoid hitting real LLM providers in tests — every
runtime test gets a `RecordedLLMClient` that replays a hand-crafted
script.  That keeps the suite fast, deterministic, and free.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

import pytest

from genie_swarm.llm import LLMClient, LLMResponse
from genie_swarm.models import Message, ToolCall
from genie_swarm.sandbox import Sandbox, SandboxPolicy
from genie_swarm.streaming import EventStream


# --------------------------------------------------------------------------- #
# Recorded LLM
# --------------------------------------------------------------------------- #

@dataclass
class RecordedLLMClient(LLMClient):
    """Replays a list of `LLMResponse`s in order. Each `complete()` call
    pops the next one. Tests can swap in custom responses to exercise the
    runtime's branching logic without touching the network."""

    script: list[LLMResponse] = field(default_factory=list)
    calls: list[dict[str, Any]] = field(default_factory=list)

    async def complete(self, **kwargs) -> LLMResponse:
        self.calls.append(kwargs)
        if not self.script:
            return LLMResponse(text="(end)", tool_calls=[], stop_reason="end_turn")
        return self.script.pop(0)


# --------------------------------------------------------------------------- #
# Fixtures
# --------------------------------------------------------------------------- #

@pytest.fixture
def temp_workspace(tmp_path: Path) -> Path:
    ws = tmp_path / "ws"
    ws.mkdir()
    return ws


@pytest.fixture
def sandbox(temp_workspace: Path) -> Sandbox:
    return Sandbox(SandboxPolicy(
        workspace=temp_workspace,
        timeout_s=10.0,
        max_output_bytes=128 * 1024,
        max_rss_bytes=None,  # disabled in tests so coverage tooling can run
    ))


@pytest.fixture
def event_stream() -> EventStream:
    return EventStream(job_id="test_job")


@pytest.fixture
def recorded_llm() -> RecordedLLMClient:
    return RecordedLLMClient()


@pytest.fixture
def assistant_text():
    """Helper to build an assistant text-only response."""
    def _build(text: str) -> LLMResponse:
        return LLMResponse(text=text, tool_calls=[], stop_reason="end_turn")
    return _build


@pytest.fixture
def assistant_tool():
    """Helper to build an assistant tool-call response."""
    def _build(name: str, args: dict[str, Any]) -> LLMResponse:
        return LLMResponse(
            text="",
            tool_calls=[ToolCall(name=name, arguments=args)],
            stop_reason="tool_use",
        )
    return _build


# pytest's asyncio mode is enabled in pyproject.toml; nothing else needed here.
