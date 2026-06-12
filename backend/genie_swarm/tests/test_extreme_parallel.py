"""Extreme-parallelism tests for the overlapped test layer.

A probe LLM client adds a small real delay per call and records each
call's (agent-system, start, end) window plus the maximum number of
in-flight calls, so the tests assert ACTUAL concurrency — not just call
counts.
"""
from __future__ import annotations

import asyncio
import time
from pathlib import Path
from typing import Any

import pytest

from genie_swarm.llm import LLMClient, LLMResponse
from genie_swarm.models import AppSpec, BuildJob
from genie_swarm.orchestrator import SwarmConfig, SwarmOrchestrator
from genie_swarm.streaming import EventBus


class ProbeLLM(LLMClient):
    """Replays scripted responses with a real await, tracking overlap."""

    def __init__(self, script: list[LLMResponse], delay_s: float = 0.03) -> None:
        self.script = list(script)
        self.delay_s = delay_s
        self.calls: list[dict[str, Any]] = []
        self.windows: list[tuple[str, float, float]] = []   # (system, start, end)
        self.in_flight = 0
        self.max_in_flight = 0

    async def complete(self, **kwargs) -> LLMResponse:
        self.calls.append(kwargs)
        self.in_flight += 1
        self.max_in_flight = max(self.max_in_flight, self.in_flight)
        start = time.monotonic()
        await asyncio.sleep(self.delay_s)
        end = time.monotonic()
        self.in_flight -= 1
        self.windows.append((kwargs.get("system", ""), start, end))
        if not self.script:
            return LLMResponse(text="all tests pass", tool_calls=[], stop_reason="end_turn")
        return self.script.pop(0)


def _green(n: int) -> list[LLMResponse]:
    return [
        LLMResponse(text="all tests pass — 0 failures.", tool_calls=[], stop_reason="end_turn")
        for _ in range(n)
    ]


def _windows_overlap(a: tuple[float, float], b: tuple[float, float]) -> bool:
    return a[0] < b[1] and b[0] < a[1]


@pytest.mark.asyncio
async def test_overlap_review_runs_reviewer_during_unit_gate(tmp_path: Path):
    """With overlap_review on, the Reviewer/Security calls genuinely
    overlap the Unit Tester's window, and total agent calls stay at 8
    (no re-review when nothing mutated)."""
    llm = ProbeLLM(_green(8))
    orch = SwarmOrchestrator(
        llm=llm, bus=EventBus(),
        config=SwarmConfig(
            workspace_root=tmp_path / "ws",
            parallel_build=True, parallel_test=True, overlap_review=True,
            max_retries=2, max_crash_recoveries=0,
        ),
    )
    job = BuildJob(spec=AppSpec(title="Fast", prompt="speed test"))
    session = await orch.execute(job)

    assert session.job.state.value == "succeeded"
    assert len(llm.calls) == 8                      # no redundant re-review
    assert llm.max_in_flight >= 3                   # unit ∥ reviewer ∥ security

    def window(opening: str) -> tuple[float, float]:
        matches = [(start, end) for system, start, end in llm.windows
                   if system.startswith(opening)]
        assert len(matches) == 1, f"expected exactly one {opening!r} call, got {len(matches)}"
        return matches[0]

    unit = window("You are the **Unit Tester**")
    assert _windows_overlap(unit, window("You are the **Code Reviewer**"))
    assert _windows_overlap(unit, window("You are the **Security Auditor**"))
    # UI Tester must NOT overlap the unit gate — it needs a green build.
    ui = window("You are the **UI Tester**")
    assert ui[0] >= unit[1]


@pytest.mark.asyncio
async def test_overlap_review_reruns_reviews_after_mutation(tmp_path: Path):
    """If the retry loop mutates the code, Reviewer + Security re-run
    against the final workspace so the concurrent (now stale) reviews
    aren't the last word."""
    script = (
        _green(4)                                                # architect, coder, designer, integrator
        + [LLMResponse(text="Failing tests:\n  AppTests.testX",  # unit #1 (also races reviewer+security)
                       tool_calls=[], stop_reason="end_turn")]
        + _green(2)                                              # reviewer, security (concurrent pass)
        + _green(3)                                              # retry: coder, integrator, unit #2 (green)
        + _green(3)                                              # re-review ×2 + ui tester
    )
    llm = ProbeLLM(script, delay_s=0.01)
    orch = SwarmOrchestrator(
        llm=llm, bus=EventBus(),
        config=SwarmConfig(
            workspace_root=tmp_path / "ws",
            parallel_build=False, parallel_test=True, overlap_review=True,
            max_retries=2, max_crash_recoveries=0,
        ),
    )
    job = BuildJob(spec=AppSpec(title="Retry", prompt="mutation test"))
    session = await orch.execute(job)

    assert session.job.state.value == "succeeded"
    reviewer_calls = [c for c in llm.calls
                      if c.get("system", "").startswith("You are the **Code Reviewer**")]
    security_calls = [c for c in llm.calls
                      if c.get("system", "").startswith("You are the **Security Auditor**")]
    assert len(reviewer_calls) == 2                 # concurrent pass + post-mutation refresh
    assert len(security_calls) == 2
    # 8 baseline + 3 retry (coder/integrator/unit) + 2 re-reviews = 13.
    assert len(llm.calls) == 13
