"""Pause gate + custom agents tests.

The orchestrator awaits a per-job asyncio.Event between agent runs.
When the event is cleared the run blocks; setting it unblocks
immediately. We verify the wait behaviour and the custom-agents
stage that runs after the standard test layer.
"""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from genie_swarm.agents import ALL_AGENTS
from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


# --------------------------------------------------------------------------- #
# Pause gate
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_orchestrator_waits_on_paused_gate(tmp_path: Path, recorded_llm):
    """A cleared event blocks the next agent. Setting it un-blocks
    immediately. We assert the orchestrator actually waited (i.e. it
    didn't sail past a closed gate)."""
    recorded_llm.script = [
        LLMResponse(text=f"agent {i} done", tool_calls=[], stop_reason="end_turn")
        for i in range(4)
    ]
    gate = asyncio.Event()
    # Gate starts cleared — the very first agent should block.

    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0, max_crash_recoveries=0,
        pause_gate=lambda _: gate,
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="Patient", prompt="x"))

    task = asyncio.create_task(orch.execute(job))
    # Give the orchestrator a moment to enter the gate.
    await asyncio.sleep(0.05)
    assert not task.done(), "orchestrator should be parked on the closed gate"
    assert len(recorded_llm.calls) == 0, "no LLM calls should have fired yet"

    # Release the gate — orchestrator proceeds.
    gate.set()
    await asyncio.wait_for(task, timeout=2.0)
    assert len(recorded_llm.calls) == 4


@pytest.mark.asyncio
async def test_orchestrator_skips_gate_when_already_set(tmp_path: Path, recorded_llm):
    """The pre-set fast path — gate is set from the start, no waiting."""
    recorded_llm.script = [
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn")
        for _ in range(4)
    ]
    gate = asyncio.Event(); gate.set()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0, max_crash_recoveries=0,
        pause_gate=lambda _: gate,
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="Fast", prompt="x"))

    await asyncio.wait_for(orch.execute(job), timeout=2.0)
    assert len(recorded_llm.calls) == 4


@pytest.mark.asyncio
async def test_pause_toggle_pattern(tmp_path: Path, recorded_llm):
    """End-to-end pause toggle: start with gate cleared, prove the
    orchestrator parks; set the gate, prove all eight agents run."""
    recorded_llm.script = [
        LLMResponse(text=f"#{i}", tool_calls=[], stop_reason="end_turn")
        for i in range(8)
    ]
    gate = asyncio.Event()  # cleared

    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
        pause_gate=lambda _: gate,
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="MidPause", prompt="x"))

    task = asyncio.create_task(orch.execute(job))
    await asyncio.sleep(0.05)
    # Gate is cleared — orchestrator must be parked on the Architect.
    assert not task.done()
    assert len(recorded_llm.calls) == 0

    # Release. The rest of the run completes.
    gate.set()
    await asyncio.wait_for(task, timeout=2.0)
    assert len(recorded_llm.calls) == 8


# --------------------------------------------------------------------------- #
# Custom agents
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_custom_agents_run_after_test_layer(tmp_path: Path, recorded_llm):
    """Every entry in `SwarmConfig.custom_agents` should produce one
    additional agent.finished event after the standard test layer."""
    # 8 standard agents + 2 custom = 10 text-only replies.
    recorded_llm.script = [
        LLMResponse(text=f"agent {i}", tool_calls=[], stop_reason="end_turn")
        for i in range(10)
    ]
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
        custom_agents=[
            {"name": "Accessibility Auditor", "system_prompt": "audit a11y", "tool_allowlist": ["read_file"]},
            {"name": "Privacy Auditor", "system_prompt": "check privacy", "tool_allowlist": []},
        ],
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="Extended", prompt="x"))

    starts: list[str] = []

    async def collect():
        stream = await bus.stream_for(job.id)
        async for ev in stream.subscribe():
            if ev.type == "agent.started" and ev.agent:
                starts.append(ev.agent)
            if ev.type == "done":
                break

    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.state.value == "succeeded"
    # The 9th and 10th agents.started events should be our custom ones.
    custom_starts = [s for s in starts if "🧩" in s]
    assert "🧩 Accessibility Auditor" in custom_starts
    assert "🧩 Privacy Auditor" in custom_starts
    assert len(custom_starts) == 2
    assert len(recorded_llm.calls) == 10


@pytest.mark.asyncio
async def test_no_custom_agents_no_extra_runs(tmp_path: Path, recorded_llm):
    """Empty list = no custom stage."""
    recorded_llm.script = [
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn")
        for _ in range(8)
    ]
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="Plain", prompt="x"))
    session = await orch.execute(job)
    assert session.job.state.value == "succeeded"
    assert len(recorded_llm.calls) == 8


@pytest.mark.asyncio
async def test_custom_agent_uses_its_allowlist(tmp_path: Path, recorded_llm):
    """A custom agent with tool_allowlist=['read_file'] only gets
    read_file in its registry. We verify by inspecting the tools list
    that the LLM saw on the custom-agent call."""
    recorded_llm.script = [
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn")
        for _ in range(9)
    ]
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
        custom_agents=[
            {"name": "Locked Down", "system_prompt": "p", "tool_allowlist": ["read_file"]},
        ],
    )
    bus = EventBus()
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    job = BuildJob(spec=AppSpec(title="Locked", prompt="x"))
    await orch.execute(job)

    # The custom agent's call is the 9th.
    custom_call = recorded_llm.calls[8]
    tools = custom_call["tools"]
    tool_names = {t["name"] for t in tools}
    assert tool_names == {"read_file"}
