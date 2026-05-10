"""ConversationRuntime tool-loop tests."""
from __future__ import annotations

import pytest

from genie_swarm.runtime import ConversationRuntime, RuntimeConfig
from genie_swarm.tools import ToolRegistry
from genie_swarm.tools.filesystem import ReadFile, WriteFile


def _registry() -> ToolRegistry:
    r = ToolRegistry()
    r.register(ReadFile()); r.register(WriteFile())
    return r


@pytest.mark.asyncio
async def test_runtime_returns_text_when_no_tool_calls(sandbox, event_stream, recorded_llm, assistant_text):
    recorded_llm.script = [assistant_text("done")]
    rt = ConversationRuntime(
        agent_name="tester",
        system_prompt="you are a tester",
        llm=recorded_llm,
        tools=_registry(),
        sandbox=sandbox,
        events=event_stream,
        config=RuntimeConfig(max_steps=4),
    )
    run = await rt.run(user="hello")
    assert run.final_message.content == "done"
    assert run.tool_calls == 0
    assert len(recorded_llm.calls) == 1


@pytest.mark.asyncio
async def test_runtime_executes_tool_then_finalises(
    sandbox, event_stream, recorded_llm, assistant_text, assistant_tool
):
    recorded_llm.script = [
        assistant_tool("write_file", {"path": "out.txt", "body": "ok"}),
        assistant_text("written"),
    ]
    rt = ConversationRuntime(
        agent_name="tester",
        system_prompt="...",
        llm=recorded_llm,
        tools=_registry(),
        sandbox=sandbox,
        events=event_stream,
        config=RuntimeConfig(max_steps=4),
    )
    run = await rt.run(user="please")
    assert run.final_message.content == "written"
    assert run.tool_calls == 1
    assert sandbox.read_text("out.txt") == "ok"
    # tool_call + tool_result events should have been emitted
    # (we don't subscribe here, just verify the runtime didn't crash).


@pytest.mark.asyncio
async def test_runtime_hits_max_steps(
    sandbox, event_stream, recorded_llm, assistant_tool
):
    # Loop forever — the runtime must abort cleanly.
    recorded_llm.script = [
        assistant_tool("write_file", {"path": f"f{i}.txt", "body": "x"})
        for i in range(20)
    ]
    rt = ConversationRuntime(
        agent_name="tester",
        system_prompt="...",
        llm=recorded_llm,
        tools=_registry(),
        sandbox=sandbox,
        events=event_stream,
        config=RuntimeConfig(max_steps=3),
    )
    run = await rt.run(user="please")
    assert "max_steps" in run.final_message.content
    # Exactly max_steps LLM calls should have happened.
    assert len(recorded_llm.calls) == 3


@pytest.mark.asyncio
async def test_runtime_tool_failure_does_not_kill_run(
    sandbox, event_stream, recorded_llm, assistant_text, assistant_tool
):
    # First call asks for a bad file (escapes sandbox), second wraps up.
    recorded_llm.script = [
        assistant_tool("read_file", {"path": "../escape.txt"}),
        assistant_text("recovered"),
    ]
    rt = ConversationRuntime(
        agent_name="tester",
        system_prompt="...",
        llm=recorded_llm,
        tools=_registry(),
        sandbox=sandbox,
        events=event_stream,
        config=RuntimeConfig(max_steps=4),
    )
    run = await rt.run(user="please")
    assert run.final_message.content == "recovered"
    # The runtime must have appended the failed tool_result to the transcript
    # so the LLM can see what went wrong.
    tool_msgs = [m for m in run.transcript if m.role == "tool"]
    assert len(tool_msgs) == 1
    assert tool_msgs[0].tool_result is not None
    assert not tool_msgs[0].tool_result.ok
