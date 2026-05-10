"""Per-agent model routing + retry-on-test-failure tests."""
from __future__ import annotations

from pathlib import Path

import pytest

from genie_swarm.agents import ALL_AGENTS
from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob, ToolCall
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


# --------------------------------------------------------------------------- #
# Per-agent model overrides
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_per_agent_override_reaches_llm_client(tmp_path: Path, recorded_llm):
    """The model id passed to LLMClient.complete() must reflect the
    `model_overrides` map for each agent. Default model fills in where
    the map doesn't say otherwise."""
    overrides = {"coder": "claude-haiku-4-5", "reviewer": "gpt-5"}

    # Pad the script: each agent gets one text reply (no tool calls).
    recorded_llm.script = [
        LLMResponse(text=f"{a.title} done.", tool_calls=[], stop_reason="end_turn")
        for a in ALL_AGENTS
    ]

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, model_overrides=overrides, max_retries=0,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    await orch.execute(BuildJob(spec=AppSpec(title="X", prompt="..")))

    # Map each call's `model` kwarg to the matching agent in order.
    models_by_agent = {}
    for agent, call in zip(ALL_AGENTS, recorded_llm.calls):
        models_by_agent[agent.role.value] = call["model"]

    assert models_by_agent["coder"]    == "claude-haiku-4-5"
    assert models_by_agent["reviewer"] == "gpt-5"
    # Architect wasn't overridden — should be its blueprint default.
    assert models_by_agent["architect"] != "claude-haiku-4-5"


@pytest.mark.asyncio
async def test_no_overrides_uses_blueprint_defaults(tmp_path: Path, recorded_llm):
    recorded_llm.script = [
        LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn")
        for _ in ALL_AGENTS
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False, max_retries=0,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)
    await orch.execute(BuildJob(spec=AppSpec(title="X", prompt="..")))

    for agent, call in zip(ALL_AGENTS, recorded_llm.calls):
        assert call["model"] == agent.model


# --------------------------------------------------------------------------- #
# Retry-on-test-failure loop
# --------------------------------------------------------------------------- #

def _seven_agents_pass() -> list[LLMResponse]:
    """Architect → Coder → Designer → Integrator each finish, then the
    Unit Tester returns a failure message that triggers the retry path.
    """
    return [
        LLMResponse(text=f"agent #{i} done.", tool_calls=[], stop_reason="end_turn")
        for i in range(4)   # architect, coder, designer, integrator
    ]


@pytest.mark.asyncio
async def test_retry_loop_runs_until_tests_pass(tmp_path: Path, recorded_llm):
    """One failure round then green — should produce exactly:
    architect, coder, designer, integrator, unit-tester(fail),
    coder(retry), integrator(retry), unit-tester(pass), ui-tester,
    reviewer, security. That's 11 LLM calls."""
    script: list[LLMResponse] = []
    script.extend(_seven_agents_pass())               # 4 build-layer
    script.append(LLMResponse(                        # unit tester fails
        text="3 failures in HabitsTests, build failed",
        tool_calls=[], stop_reason="end_turn",
    ))
    script.append(LLMResponse(text="fixed", tool_calls=[], stop_reason="end_turn"))   # coder retry
    script.append(LLMResponse(text="integrated", tool_calls=[], stop_reason="end_turn"))  # integrator retry
    script.append(LLMResponse(                        # unit tester green
        text="All tests pass — 0 failures.",
        tool_calls=[], stop_reason="end_turn",
    ))
    # Remaining test agents (ui_tester, reviewer, security).
    for _ in range(3):
        script.append(LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn"))
    recorded_llm.script = script

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False, max_retries=3,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    # Capture retry events.
    stream = await bus.stream_for("placeholder")  # ensure bus is initialised
    import asyncio
    retries: list[int] = []

    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "retry.attempt":
                retries.append(ev.payload.get("attempt", 0))
            if ev.type == "done":
                break

    job = BuildJob(spec=AppSpec(title="HabitsApp", prompt="habits"))
    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert session.job.state.value == "succeeded"
    assert retries == [1]                               # one retry, then green
    assert len(recorded_llm.calls) == 11


@pytest.mark.asyncio
async def test_retry_loop_gives_up_after_max_attempts(tmp_path: Path, recorded_llm):
    """If the Unit Tester keeps reporting failures, retries cap out and
    the run continues to the remaining test agents (no infinite loop)."""
    script: list[LLMResponse] = []
    script.extend(_seven_agents_pass())               # 4 build-layer
    # Unit tester always says failing — 1 initial + 3 retries = 4 unit
    # tester runs, each preceded (after the first) by coder + integrator.
    for _ in range(4):
        script.append(LLMResponse(text="2 failures detected.", tool_calls=[], stop_reason="end_turn"))
    # Coder + Integrator pair for each of the 3 retries
    for _ in range(3):
        script.append(LLMResponse(text="tried", tool_calls=[], stop_reason="end_turn"))
        script.append(LLMResponse(text="reglued", tool_calls=[], stop_reason="end_turn"))
    # After the cap, remaining test agents (ui, reviewer, security) run.
    for _ in range(3):
        script.append(LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn"))

    # Re-order to actual execution sequence: build(4), ut, [coder, integ, ut]*3, ui+rev+sec(3)
    ordered = (
        _seven_agents_pass()
        + [LLMResponse(text="2 failures detected.", tool_calls=[], stop_reason="end_turn")]
    )
    for _ in range(3):
        ordered += [
            LLMResponse(text="fixing", tool_calls=[], stop_reason="end_turn"),
            LLMResponse(text="reglued", tool_calls=[], stop_reason="end_turn"),
            LLMResponse(text="2 failures detected.", tool_calls=[], stop_reason="end_turn"),
        ]
    ordered += [LLMResponse(text="ok", tool_calls=[], stop_reason="end_turn") for _ in range(3)]
    recorded_llm.script = ordered

    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False, max_retries=3,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    import asyncio
    retries: list[int] = []

    async def collect():
        s = await bus.stream_for(job.id)
        async for ev in s.subscribe():
            if ev.type == "retry.attempt":
                retries.append(ev.payload.get("attempt", 0))
            if ev.type == "done":
                break

    job = BuildJob(spec=AppSpec(title="StubbornApp", prompt="x"))
    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)

    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    # We finished even though tests were never green — by design, the
    # orchestrator continues so Reviewer + Security can still emit
    # findings. The retry counter should hit max_retries exactly.
    assert retries == [1, 2, 3]
    assert session.job.state.value == "succeeded"


# --------------------------------------------------------------------------- #
# Heuristic
# --------------------------------------------------------------------------- #

def test_unit_test_failure_heuristic():
    from genie_swarm.orchestrator import SwarmOrchestrator

    class FakeRun:
        def __init__(self, text: str):
            from genie_swarm.models import Message
            self.final_message = Message(role="assistant", content=text)

    failed = SwarmOrchestrator._unit_tests_failed
    assert failed(FakeRun("Failing tests:\n  HabitsTests.testSync"))
    assert failed(FakeRun("2 failures detected during xcodebuild test"))
    assert failed(FakeRun("Test failed"))
    assert failed(FakeRun("BUILD FAILED"))
    assert not failed(FakeRun("All tests pass — 0 failures."))
    assert not failed(FakeRun("OK"))
    assert not failed(FakeRun(""))
    # An empty-string output shouldn't be treated as failure.
    assert not failed(FakeRun("Suite ran with 0 failures, 12 tests."))
