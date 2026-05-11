"""Cost meter + budget cap tests."""
from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from genie_swarm.cost import BudgetExceeded, CostMeter, DEFAULT_PRICES
from genie_swarm.llm import LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


# --------------------------------------------------------------------------- #
# CostMeter unit
# --------------------------------------------------------------------------- #

def test_meter_sums_tokens_per_model():
    meter = CostMeter()
    meter.record(model="claude-sonnet-4-6", input_tokens=1_000_000, output_tokens=0)
    # $3 per million input.
    assert meter.spend_usd == pytest.approx(3.0)
    meter.record(model="claude-haiku-4-5", input_tokens=0, output_tokens=1_000_000)
    # +$5 per million output → 8.
    assert meter.spend_usd == pytest.approx(8.0)


def test_meter_falls_back_for_unknown_model():
    meter = CostMeter()
    # Unknown model — fallback rate is the conservative Opus rate
    # (15 input / 75 output per million).
    meter.record(model="some-future-model", input_tokens=1_000_000, output_tokens=0)
    assert meter.spend_usd == pytest.approx(15.0)


def test_meter_raises_budget_exceeded_when_over_cap():
    meter = CostMeter(cap_usd=2.0)
    # 1M tokens of Sonnet input = $3 — should trip the cap.
    with pytest.raises(BudgetExceeded) as exc_info:
        meter.record(model="claude-sonnet-4-6", input_tokens=1_000_000, output_tokens=0)
    assert exc_info.value.cap == 2.0
    assert exc_info.value.spent > 2.0


def test_meter_snapshot_is_json_safe():
    meter = CostMeter(cap_usd=10)
    meter.record(model="claude-haiku-4-5", input_tokens=500_000, output_tokens=100_000)
    snap = meter.snapshot()
    assert snap == {
        "input_tokens": 500_000,
        "output_tokens": 100_000,
        "spend_usd": pytest.approx(1.0, abs=0.001),
        "cap_usd": 10,
    }


def test_default_prices_cover_main_models():
    for model in ("claude-opus-4-7", "claude-sonnet-4-6", "claude-haiku-4-5",
                  "gpt-5", "gpt-5-mini"):
        assert model in DEFAULT_PRICES


# --------------------------------------------------------------------------- #
# Orchestrator integration
# --------------------------------------------------------------------------- #

@pytest.mark.asyncio
async def test_orchestrator_emits_cost_update_per_agent(tmp_path: Path, recorded_llm):
    """Every agent's finish should produce one cost.update with running
    spend + token totals."""
    recorded_llm.script = [
        LLMResponse(
            text="ok",
            tool_calls=[],
            stop_reason="end_turn",
            usage={"input_tokens": 50_000, "output_tokens": 10_000},
        )
        for _ in range(4)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=True, max_retries=0, max_crash_recoveries=0,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    updates: list[dict] = []

    async def collect():
        stream = await bus.stream_for(job.id)
        async for ev in stream.subscribe():
            if ev.type == "cost.update":
                updates.append(dict(ev.payload))
            if ev.type == "done":
                break

    job = BuildJob(spec=AppSpec(title="Costly", prompt="x"))
    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    assert len(updates) == 4
    # spend_usd should be monotonically increasing.
    spends = [u["spend_usd"] for u in updates]
    assert spends == sorted(spends)
    assert spends[-1] > 0


@pytest.mark.asyncio
async def test_orchestrator_halts_cleanly_on_cost_cap(tmp_path: Path, recorded_llm):
    """Cap hit mid-build → job ends in cancelled state with the
    cost.cap_hit + done events fired in order. No exception escapes."""
    # Use a wild-card model with the fallback rate so 1 token = $15/M.
    recorded_llm.script = [
        LLMResponse(
            text="ok", tool_calls=[], stop_reason="end_turn",
            usage={"input_tokens": 200_000, "output_tokens": 50_000},
        )
        for _ in range(8)
    ]
    bus = EventBus()
    config = SwarmConfig(
        workspace_root=tmp_path / "ws",
        parallel_build=False, parallel_test=False,
        skip_tests=False, max_retries=0, max_crash_recoveries=0,
        # Default model is Opus → $15/M input, $75/M output.
        # First agent: 200k * $15/M + 50k * $75/M = $3 + $3.75 = $6.75
        cost_cap_usd=4.0,
    )
    orch = SwarmOrchestrator(llm=recorded_llm, bus=bus, config=config)

    received: list[str] = []
    async def collect():
        stream = await bus.stream_for(job.id)
        async for ev in stream.subscribe():
            received.append(ev.type)
            if ev.type == "done":
                break

    job = BuildJob(spec=AppSpec(title="Pricy", prompt="x"))
    consumer = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    session = await orch.execute(job)
    await asyncio.wait_for(consumer, timeout=5.0)

    # cost.cap_hit fires before done; job ends as cancelled.
    assert "cost.cap_hit" in received
    assert received[-1] == "done"
    assert session.job.state.value == "cancelled"
    # Only one agent should have actually run before the cap stopped us.
    assert len(recorded_llm.calls) == 1
