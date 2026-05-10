"""Head-to-head ranker tests."""
from __future__ import annotations

import pytest

from genie_swarm.llm import LLMResponse
from genie_swarm.ranker import Candidate, rank


@pytest.mark.asyncio
async def test_rank_picks_named_winner(recorded_llm):
    recorded_llm.script = [LLMResponse(
        text='{"winner":"claude","confidence":0.82,"rationale":"cleaner threading"}'
    )]
    verdict = await rank(
        [
            Candidate(label="claude", model="claude-opus-4-7", output="// version A", usage={}),
            Candidate(label="gpt",    model="gpt-5",            output="// version B", usage={}),
        ],
        judge=recorded_llm,
    )
    assert verdict.winner_label == "claude"
    assert verdict.losers == ["gpt"]
    assert verdict.score == pytest.approx(0.82)
    assert "threading" in verdict.rationale


@pytest.mark.asyncio
async def test_rank_handles_code_fence_wrapper(recorded_llm):
    recorded_llm.script = [LLMResponse(
        text='```json\n{"winner":"gpt","confidence":0.51,"rationale":"x"}\n```'
    )]
    verdict = await rank(
        [
            Candidate(label="claude", model="claude-opus-4-7", output="A", usage={}),
            Candidate(label="gpt",    model="gpt-5",            output="B", usage={}),
        ],
        judge=recorded_llm,
    )
    assert verdict.winner_label == "gpt"


@pytest.mark.asyncio
async def test_rank_falls_back_when_unparseable(recorded_llm):
    recorded_llm.script = [LLMResponse(text="completely unstructured judge reply")]
    verdict = await rank(
        [
            Candidate(label="claude", model="claude-opus-4-7", output="short", usage={}),
            Candidate(label="gpt",    model="gpt-5",            output="much, much longer reply", usage={}),
        ],
        judge=recorded_llm,
    )
    assert verdict.winner_label == "gpt"           # fell back to longest
    assert verdict.score < 0.5                      # low-confidence flag


@pytest.mark.asyncio
async def test_rank_rejects_unknown_winner_label(recorded_llm):
    recorded_llm.script = [LLMResponse(
        text='{"winner":"phantom","confidence":0.99,"rationale":"hi"}'
    )]
    verdict = await rank(
        [
            Candidate(label="claude", model="claude-opus-4-7", output="aa", usage={}),
            Candidate(label="gpt",    model="gpt-5",            output="bbbbbb", usage={}),
        ],
        judge=recorded_llm,
    )
    assert verdict.winner_label in {"claude", "gpt"}    # never "phantom"


@pytest.mark.asyncio
async def test_rank_with_single_candidate_short_circuits(recorded_llm):
    verdict = await rank(
        [Candidate(label="solo", model="claude-opus-4-7", output="x", usage={})],
        judge=recorded_llm,
    )
    assert verdict.winner_label == "solo"
    assert verdict.losers == []
    assert recorded_llm.calls == []   # judge never invoked
