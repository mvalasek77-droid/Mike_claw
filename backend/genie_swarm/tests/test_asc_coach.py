"""Tests for the App Store Connect coach.

We never call a real model here. What matters is that the coach is
*grounded*: that the user's live situation reaches the prompt, that the
server owns the rules rather than the client, and that a provider
failure degrades to "you can't ask questions" rather than "your
submission is broken".
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from genie_swarm.asc_coach import (
    ASC_CURRICULUM,
    SYSTEM_PROMPT,
    CoachContext,
    answer,
    suggested_questions,
)
from genie_swarm.llm import LLMResponse
from genie_swarm.models import ASC_TOTAL_STEPS, Message


class FakeLLM:
    """Captures what the coach actually sent."""

    def __init__(self, text: str = "Here is the answer.") -> None:
        self.text = text
        self.system: str | None = None
        self.messages: list[Message] = []
        self.kwargs: dict = {}

    async def complete(self, **kwargs):
        self.system = kwargs["system"]
        self.messages = kwargs["messages"]
        self.kwargs = kwargs
        return LLMResponse(text=self.text, usage={"input_tokens": 10, "output_tokens": 5})


class ExplodingLLM:
    async def complete(self, **kwargs):
        raise RuntimeError("provider down")


# ---------------------------------------------------------------------------
# Grounding
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_users_live_situation_reaches_the_prompt():
    llm = FakeLLM()
    ctx = CoachContext(
        app_name="TideRider",
        bundle_id="com.codegenie.tiderider",
        step_number=2,
        step_title="Create the app record",
        completed_steps=[1],
        mac_paired=False,
        blocking_issues=["Support URL is missing."],
        outstanding_items=["Distribution IPA: none found."],
    )
    await answer(llm=llm, question="What is a bundle ID?", context=ctx)

    assert llm.system is not None
    # Without these the coach gives a generic article instead of an
    # answer about the app in front of the user.
    for expected in [
        "TideRider",
        "com.codegenie.tiderider",
        "step 2 of 18",
        "Support URL is missing.",
        "Distribution IPA: none found.",
    ]:
        assert expected in llm.system, f"missing from prompt: {expected}"


@pytest.mark.asyncio
async def test_no_mac_is_stated_as_a_constraint():
    llm = FakeLLM()
    await answer(
        llm=llm,
        question="Can I upload now?",
        context=CoachContext(app_name="Tides", mac_paired=False),
    )
    assert "No Mac is connected" in llm.system
    assert "cannot package the app for upload" in llm.system


@pytest.mark.asyncio
async def test_curriculum_is_always_present():
    llm = FakeLLM()
    await answer(llm=llm, question="hi", context=CoachContext())
    # A coach that isn't carrying the curriculum is just a chatbot.
    assert ASC_CURRICULUM.strip() in llm.system
    assert "100 characters TOTAL" in llm.system


# ---------------------------------------------------------------------------
# Guardrails live server-side
# ---------------------------------------------------------------------------

def test_system_prompt_forbids_inventing_ui():
    assert "Never invent App Store Connect interface" in SYSTEM_PROMPT
    assert "Never claim you performed an action" in SYSTEM_PROMPT
    assert "Do not give legal, tax, or accounting advice" in SYSTEM_PROMPT


@pytest.mark.asyncio
async def test_history_is_replayed_but_question_is_last():
    llm = FakeLLM()
    history = [
        Message(role="user", content="What is a bundle ID?"),
        Message(role="assistant", content="It's your app's permanent unique name."),
    ]
    await answer(llm=llm, question="Can I change it later?", context=CoachContext(), history=history)

    assert len(llm.messages) == 3
    assert llm.messages[-1].role == "user"
    assert llm.messages[-1].content == "Can I change it later?"


@pytest.mark.asyncio
async def test_long_conversations_are_trimmed():
    llm = FakeLLM()
    history = [Message(role="user", content=f"q{i}") for i in range(40)]
    await answer(llm=llm, question="latest", context=CoachContext(), history=history)
    # Trimmed history plus the new question.
    assert len(llm.messages) <= 13
    assert llm.messages[-1].content == "latest"


@pytest.mark.asyncio
async def test_no_tools_are_offered():
    """The coach explains; it never acts. Handing it tools would make
    'never claim you performed an action' a lie."""
    llm = FakeLLM()
    await answer(llm=llm, question="upload it for me", context=CoachContext())
    assert llm.kwargs["tools"] == []


# ---------------------------------------------------------------------------
# Degradation
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_empty_question_never_hits_the_model():
    llm = FakeLLM()
    result = await answer(llm=llm, question="   ", context=CoachContext())
    assert result["answer"] == ""
    assert llm.system is None, "an empty question should not cost a request"


@pytest.mark.asyncio
async def test_provider_failure_propagates_for_the_route_to_translate():
    with pytest.raises(RuntimeError):
        await answer(llm=ExplodingLLM(), question="help", context=CoachContext())


# ---------------------------------------------------------------------------
# Suggestions
# ---------------------------------------------------------------------------

def test_every_step_offers_questions():
    for step in range(1, ASC_TOTAL_STEPS + 1):
        assert suggested_questions(step), f"step {step} has no suggested questions"


def test_suggestions_are_step_specific():
    assert any("bundle ID" in q for q in suggested_questions(2))
    assert any("screenshot" in q.lower() for q in suggested_questions(8))
    assert any("reject" in q.lower() for q in suggested_questions(17))


def test_suggestions_work_with_no_step():
    assert suggested_questions(None)


# --------------------------------------------------------------------------- #
# Staying in step with the phone
# --------------------------------------------------------------------------- #

_IOS = Path(__file__).resolve().parents[3] / "ios" / "CodeGenie"


def _swift_step_numbers() -> list[int]:
    source = (_IOS / "Models" / "ASCStep.swift").read_text(encoding="utf-8")
    return [int(n) for n in re.findall(r"\.init\(number: (\d+),", source)]


def test_step_count_matches_the_ios_guide():
    numbers = _swift_step_numbers()
    assert numbers == list(range(1, ASC_TOTAL_STEPS + 1))


def test_phone_and_server_offer_the_same_questions_per_step():
    """The phone shows its own copy of the chips until the first answer
    arrives; if the two lists drift the chips change under the user."""
    source = (_IOS / "Services" / "ASCCoachChat.swift").read_text(encoding="utf-8")
    for step in range(1, ASC_TOTAL_STEPS + 1):
        for question in suggested_questions(step)[:-1]:
            assert f'"{question}"' in source, f"step {step}: {question!r} missing on the phone"


def test_request_accepts_every_step_and_rejects_beyond():
    from pydantic import ValidationError
    from genie_swarm.models import ASCCoachRequest
    ASCCoachRequest(question="q", step_number=ASC_TOTAL_STEPS)
    with pytest.raises(ValidationError):
        ASCCoachRequest(question="q", step_number=ASC_TOTAL_STEPS + 1)


@pytest.mark.parametrize("needle", [
    "Waiting for Review", "In Review", "Metadata Rejected",
    "Pending Developer Release", "4.3", "Add for Review alone sends",
    "Age rating", "App Review Information", "appeal",
])
def test_curriculum_covers_the_review_phase(needle):
    from genie_swarm.asc_coach import SYSTEM_PROMPT
    assert needle in SYSTEM_PROMPT
