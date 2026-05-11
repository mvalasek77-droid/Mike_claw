"""Crash-recovery loop tests for the orchestrator.

When an agent throws an unexpected exception, the orchestrator should
roll back to the latest checkpoint and try again, up to
`max_crash_recoveries`. The retry.attempt SwarmEvent fires each time
with a `reason: crash:<ExceptionName>` payload.
"""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from genie_swarm.llm import LLMClient, LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


class _ExplosiveLLM(LLMClient):
    """Raises on the first N calls, then returns a clean text reply."""

    def __init__(self, *, fail_first: int, error: type[Exception] = RuntimeError) -> None:
        self.fail_first = fail_first
        self.error = error
        self.calls: list[dict] = []

    async def complete(self, **kwargs):  # type: ignore[override]
        self.calls.append(kwargs)
        if len(self.calls) <= self.fail_first:
            raise self.error(f"synthetic failure #{len(self.calls)}")
        return LLMResponse(text="agent done.", tool_calls=[], stop_reason="end_turn")


@pytest.mark.asyncio
async def test_agent_recovers_after_transient_crash(tmp_path: Path):
    """Architect crashes once, recovers on the second attempt — the
    job overall should succeed and the retry.attempt event should
    carry the crash reason."""
    llm = _ExplosiveLLM(fail_first=1)

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0,
        max_crash_recoveries=2,
    )
    orch = SwarmOrchestrator(llm=llm, bus=bus, config=config)

    retries: list[dict] = []

    async def collect():
        stream = await bus.stream_for(job.id)
        async for ev in stream.subscribe():
            if ev.type == "retry.attempt":
                retries.append(dict(ev.payload))
            if ev.type == "done":
                break

    job = BuildJob(spec=AppSpec(title="Resilient", prompt="bounce back"))
    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.state.value == "succeeded"
    # First architect call crashed; second succeeded.
    assert len(retries) == 1
    assert retries[0].get("reason", "").startswith("crash:")


@pytest.mark.asyncio
async def test_max_crash_recoveries_caps_attempts(tmp_path: Path):
    """If the agent keeps crashing past the cap, the orchestrator
    surfaces the exception — it should NOT loop forever."""
    llm = _ExplosiveLLM(fail_first=99)

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0,
        max_crash_recoveries=2,
    )
    orch = SwarmOrchestrator(llm=llm, bus=bus, config=config)

    job = BuildJob(spec=AppSpec(title="Doomed", prompt="x"))
    with pytest.raises(RuntimeError):
        await orch.execute(job)

    # Initial attempt + 2 recoveries = 3 total LLM calls before giving up.
    assert len(llm.calls) == 3


@pytest.mark.asyncio
async def test_zero_recoveries_propagates_immediately(tmp_path: Path):
    """With max_crash_recoveries=0, the first crash bubbles up."""
    llm = _ExplosiveLLM(fail_first=99)
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0,
        max_crash_recoveries=0,
    )
    orch = SwarmOrchestrator(llm=llm, bus=bus, config=config)

    job = BuildJob(spec=AppSpec(title="Brittle", prompt="x"))
    with pytest.raises(RuntimeError):
        await orch.execute(job)
    # Just the one attempt, no retries.
    assert len(llm.calls) == 1
