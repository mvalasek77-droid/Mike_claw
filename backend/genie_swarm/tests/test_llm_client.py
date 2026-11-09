"""The provider layer: model ids, replayed turns, vendor routing, refusals."""
from __future__ import annotations

import pytest

from genie_swarm.llm import (
    COACH_MODEL,
    DEFAULT_MODEL,
    LLMResponse,
    RoutingLLMClient,
    _to_anthropic_messages,
    canonical_model,
    is_openai_model,
)
from genie_swarm.cost import DEFAULT_PRICES
from genie_swarm.models import Message, ToolCall, ToolResult
from genie_swarm.runtime import ConversationRuntime, RuntimeConfig
from genie_swarm.tools import default_registry


def test_defaults_are_priced():
    assert DEFAULT_MODEL in DEFAULT_PRICES
    assert COACH_MODEL in DEFAULT_PRICES


@pytest.mark.parametrize("old,new", [
    ("claude-opus-4-7", "claude-opus-5-5"),
    ("claude-sonnet-4-6", "claude-sonnet-5-5"),
    ("claude-sonnet-5", "claude-sonnet-5-5"),
    ("claude-haiku-4-5", "claude-haiku-5-5"),
])
def test_superseded_ids_resolve(old, new):
    assert canonical_model(old) == new
    assert canonical_model(new) == new


def test_unknown_ids_pass_through():
    assert canonical_model("gpt-5") == "gpt-5"
    assert canonical_model("something-else") == "something-else"


def test_openai_detection():
    assert is_openai_model("gpt-5-mini")
    assert not is_openai_model("claude-opus-5-5")


def test_assistant_turn_replays_provider_blocks_verbatim():
    blocks = [
        {"type": "thinking", "thinking": "", "signature": "sig"},
        {"type": "tool_use", "id": "t1", "name": "write_file", "input": {"path": "a"}},
    ]
    msgs = [
        Message(role="user", content="go"),
        Message(
            role="assistant",
            tool_calls=[ToolCall(id="t1", name="write_file", arguments={"path": "a"})],
            provider_blocks=blocks,
        ),
        Message(role="tool", tool_result=ToolResult(call_id="t1", ok=True, content="done")),
    ]
    out = _to_anthropic_messages(msgs)
    assert out[1] == {"role": "assistant", "content": blocks}
    assert out[2]["content"][0]["tool_use_id"] == "t1"


def test_assistant_turn_without_provider_blocks_is_rebuilt():
    msgs = [Message(
        role="assistant", content="writing",
        tool_calls=[ToolCall(id="t1", name="write_file", arguments={})],
    )]
    out = _to_anthropic_messages(msgs)
    assert [b["type"] for b in out[0]["content"]] == ["text", "tool_use"]


def test_empty_assistant_turn_is_dropped():
    out = _to_anthropic_messages([
        Message(role="user", content="hi"),
        Message(role="assistant", content=""),
    ])
    assert out == [{"role": "user", "content": "hi"}]


def test_provider_blocks_survive_a_session_round_trip():
    m = Message(role="assistant", provider_blocks=[{"type": "text", "text": "x"}])
    assert Message.model_validate(m.model_dump()).provider_blocks == m.provider_blocks
    # Transcripts saved before the field existed still load.
    assert Message.model_validate({"role": "assistant", "content": "x"}).provider_blocks is None


class _Spy:
    def __init__(self):
        self.calls = []

    async def complete(self, **kwargs):
        self.calls.append(kwargs)
        return LLMResponse(text="ok")


@pytest.mark.asyncio
async def test_router_sends_each_model_to_its_vendor():
    claude, gpt = _Spy(), _Spy()
    router = RoutingLLMClient(anthropic=claude, openai=gpt)
    await router.complete(model="claude-opus-5-5", system="", messages=[], tools=[], effort="high")
    await router.complete(model="gpt-5", system="", messages=[], tools=[], effort="high")
    assert [c["model"] for c in claude.calls] == ["claude-opus-5-5"]
    assert [c["model"] for c in gpt.calls] == ["gpt-5"]
    assert claude.calls[0]["effort"] == "high"
    assert "effort" not in gpt.calls[0]


@pytest.mark.asyncio
async def test_runtime_reports_a_refusal_instead_of_passing_it_off_as_done(
    recorded_llm, sandbox, event_stream,
):
    recorded_llm.script = [LLMResponse(text="", stop_reason="refusal")]
    seen = []

    async def collect():
        async for ev in event_stream.subscribe():
            seen.append(ev)
            if ev.type == "agent.finished":
                break

    import asyncio
    task = asyncio.create_task(collect())
    await asyncio.sleep(0.01)
    runtime = ConversationRuntime(
        agent_name="Coder", system_prompt="s", llm=recorded_llm,
        tools=default_registry, sandbox=sandbox, events=event_stream,
        config=RuntimeConfig(),
    )
    run = await runtime.run(user="build it")
    await asyncio.wait_for(task, timeout=5)
    assert "declined" in run.final_message.content
    assert any(e.type == "error" and "declined" in e.payload["message"] for e in seen)
    assert recorded_llm.calls[0]["effort"] == "high"
    assert recorded_llm.calls[0]["max_tokens"] >= 16000
