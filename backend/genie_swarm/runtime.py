"""ConversationRuntime — the tool-use loop.

Inspired by Claude Code's runtime: an agent calls the model, gets back
either a final answer or a list of tool calls, executes the calls in the
sandbox, appends the results to the transcript, and loops until the
model decides it's done (or we hit `max_steps`).

Each step emits streaming events via the bus so the iOS client can show
live tool calls, log lines, and diffs as they happen.
"""
from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field

from .llm import LLMClient, LLMResponse
from .models import Message, ToolCall, ToolResult
from .sandbox import Sandbox
from .streaming import EventStream
from .tools import ToolRegistry
from .tools.base import ToolContext


@dataclass
class RuntimeConfig:
    model: str = "claude-opus-4-7"
    max_steps: int = 32
    max_parallel_tool_calls: int = 4
    temperature: float = 0.2
    max_tokens: int = 4096


@dataclass
class AgentRun:
    """The output of a single ConversationRuntime.run() invocation."""
    final_message: Message
    transcript: list[Message] = field(default_factory=list)
    tool_calls: int = 0
    duration_ms: int = 0
    usage: dict[str, int] = field(default_factory=dict)


class ConversationRuntime:
    """Drives one agent through a tool-use loop until the LLM stops calling tools."""

    def __init__(
        self,
        *,
        agent_name: str,
        system_prompt: str,
        llm: LLMClient,
        tools: ToolRegistry,
        sandbox: Sandbox,
        events: EventStream,
        config: RuntimeConfig | None = None,
    ) -> None:
        self.agent = agent_name
        self.system = system_prompt
        self.llm = llm
        self.tools = tools
        self.sandbox = sandbox
        self.events = events
        self.config = config or RuntimeConfig()

    async def run(self, *, user: str, transcript: list[Message] | None = None) -> AgentRun:
        msgs: list[Message] = list(transcript or [])
        msgs.append(Message(role="user", content=user, agent=self.agent))

        await self.events.emit("agent.started", agent=self.agent)
        started = time.time()
        usage = {"input_tokens": 0, "output_tokens": 0}
        tool_calls_total = 0

        for step in range(self.config.max_steps):
            response = await self._call_llm(msgs)
            usage["input_tokens"]  += response.usage.get("input_tokens", 0)
            usage["output_tokens"] += response.usage.get("output_tokens", 0)

            # Append the assistant turn (text + any tool requests).
            assistant_msg = Message(
                role="assistant",
                content=response.text,
                tool_calls=response.tool_calls,
                agent=self.agent,
            )
            msgs.append(assistant_msg)

            if response.text:
                await self.events.emit(
                    "agent.thought", agent=self.agent, text=response.text
                )

            if not response.tool_calls:
                duration = int((time.time() - started) * 1000)
                await self.events.emit(
                    "agent.finished",
                    agent=self.agent,
                    duration_ms=duration,
                    tool_calls=tool_calls_total,
                    **usage,
                )
                return AgentRun(
                    final_message=assistant_msg,
                    transcript=msgs,
                    tool_calls=tool_calls_total,
                    duration_ms=duration,
                    usage=usage,
                )

            # Execute the model's tool calls in parallel — Cursor-style.
            tool_calls_total += len(response.tool_calls)
            results = await self._execute_tools(response.tool_calls)
            for r in results:
                msgs.append(Message(role="tool", tool_result=r, agent=self.agent))

        # Hit the step ceiling. Surface a clear error rather than looping.
        await self.events.emit(
            "error", agent=self.agent,
            message=f"runtime hit max_steps={self.config.max_steps}",
        )
        duration = int((time.time() - started) * 1000)
        return AgentRun(
            final_message=Message(
                role="assistant",
                content="(max_steps exceeded)",
                agent=self.agent,
            ),
            transcript=msgs,
            tool_calls=tool_calls_total,
            duration_ms=duration,
            usage=usage,
        )

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    async def _call_llm(self, msgs: list[Message]) -> LLMResponse:
        return await self.llm.complete(
            model=self.config.model,
            system=self.system,
            messages=msgs,
            tools=[t.as_anthropic() for t in self.tools.all()],
            max_tokens=self.config.max_tokens,
            temperature=self.config.temperature,
        )

    async def _execute_tools(self, calls: list[ToolCall]) -> list[ToolResult]:
        sem = asyncio.Semaphore(self.config.max_parallel_tool_calls)
        ctx = ToolContext(
            job_id=self.events.job_id,
            agent=self.agent,
            workspace=str(self.sandbox.policy.workspace),
        )

        async def _one(call: ToolCall) -> ToolResult:
            async with sem:
                await self.events.emit(
                    "tool.call", agent=self.agent,
                    tool=call.name, arguments=call.arguments, call_id=call.id,
                )
                result = await self.tools.invoke(call, self.sandbox, ctx)
                await self.events.emit(
                    "tool.result", agent=self.agent,
                    tool=call.name,
                    ok=result.ok,
                    duration_ms=result.duration_ms,
                    call_id=call.id,
                    content_preview=result.content[:600],
                )
                return result

        return await asyncio.gather(*(_one(c) for c in calls))
