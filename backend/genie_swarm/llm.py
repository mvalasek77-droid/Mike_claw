"""LLM provider abstraction.

We support Anthropic's Messages API and OpenAI's Responses/Chat APIs
through a single `LLMClient` interface. The runtime calls `complete()`
with a transcript and a tool list and gets back a normalised response —
either a final assistant message or a list of tool calls to execute.

In tests we swap in `RecordedLLMClient` which replays canned transcripts.
"""
from __future__ import annotations

import os
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

from .models import Message, ToolCall


# ---------------------------------------------------------------------------
# Result type
# ---------------------------------------------------------------------------

@dataclass
class LLMResponse:
    text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    stop_reason: str = "end_turn"   # end_turn | tool_use | max_tokens
    usage: dict[str, int] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Interface
# ---------------------------------------------------------------------------

class LLMClient(ABC):
    @abstractmethod
    async def complete(
        self,
        *,
        model: str,
        system: str,
        messages: list[Message],
        tools: list[dict[str, Any]],
        max_tokens: int = 4096,
        temperature: float = 0.2,
    ) -> LLMResponse:
        ...


# ---------------------------------------------------------------------------
# Anthropic — Claude (default)
# ---------------------------------------------------------------------------

class AnthropicClient(LLMClient):
    def __init__(self, api_key: str | None = None) -> None:
        self.api_key = api_key or os.environ.get("ANTHROPIC_API_KEY", "")

    async def complete(self, **kwargs) -> LLMResponse:
        try:
            from anthropic import AsyncAnthropic  # type: ignore[import-not-found]
        except ImportError as e:  # pragma: no cover
            raise RuntimeError("install `anthropic` to use AnthropicClient") from e

        client = AsyncAnthropic(api_key=self.api_key)
        ans = await client.messages.create(
            model=kwargs["model"],
            system=kwargs["system"],
            messages=_to_anthropic_messages(kwargs["messages"]),
            tools=kwargs["tools"],
            max_tokens=kwargs.get("max_tokens", 4096),
            temperature=kwargs.get("temperature", 0.2),
        )

        text_parts: list[str] = []
        calls: list[ToolCall] = []
        for block in ans.content:
            kind = getattr(block, "type", None)
            if kind == "text":
                text_parts.append(block.text)
            elif kind == "tool_use":
                calls.append(ToolCall(id=block.id, name=block.name, arguments=dict(block.input)))

        return LLMResponse(
            text="".join(text_parts),
            tool_calls=calls,
            stop_reason=ans.stop_reason or "end_turn",
            usage={
                "input_tokens": getattr(ans.usage, "input_tokens", 0),
                "output_tokens": getattr(ans.usage, "output_tokens", 0),
            },
        )


def _to_anthropic_messages(msgs: list[Message]) -> list[dict[str, Any]]:
    """Translate our internal transcript into Anthropic's content-block schema."""
    out: list[dict[str, Any]] = []
    for m in msgs:
        if m.role == "system":
            continue   # system goes on the request, not in messages
        if m.role == "tool" and m.tool_result is not None:
            out.append({
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": m.tool_result.call_id,
                    "content": m.tool_result.content,
                    "is_error": not m.tool_result.ok,
                }],
            })
            continue
        if m.role == "assistant" and m.tool_calls:
            blocks: list[dict[str, Any]] = []
            if m.content:
                blocks.append({"type": "text", "text": m.content})
            for tc in m.tool_calls:
                blocks.append({
                    "type": "tool_use",
                    "id": tc.id,
                    "name": tc.name,
                    "input": tc.arguments,
                })
            out.append({"role": "assistant", "content": blocks})
            continue
        out.append({"role": m.role, "content": m.content})
    return out


# ---------------------------------------------------------------------------
# OpenAI — used for ranking / second-opinion (Cursor-style head-to-head)
# ---------------------------------------------------------------------------

class OpenAIClient(LLMClient):
    def __init__(self, api_key: str | None = None) -> None:
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY", "")

    async def complete(self, **kwargs) -> LLMResponse:
        try:
            from openai import AsyncOpenAI  # type: ignore[import-not-found]
        except ImportError as e:  # pragma: no cover
            raise RuntimeError("install `openai` to use OpenAIClient") from e

        client = AsyncOpenAI(api_key=self.api_key)
        msgs: list[dict[str, Any]] = [{"role": "system", "content": kwargs["system"]}]
        for m in kwargs["messages"]:
            msgs.append({"role": m.role, "content": m.content})

        # We map our tool list to OpenAI's `tools=` shape.
        tools = [t if t.get("type") == "function" else {"type": "function", "function": t}
                 for t in kwargs["tools"]]

        ans = await client.chat.completions.create(
            model=kwargs["model"],
            messages=msgs,
            tools=tools or None,
            max_completion_tokens=kwargs.get("max_tokens", 4096),
            temperature=kwargs.get("temperature", 0.2),
        )
        choice = ans.choices[0]
        calls: list[ToolCall] = []
        for tc in choice.message.tool_calls or []:
            calls.append(ToolCall(
                id=tc.id,
                name=tc.function.name,
                arguments=_parse_args(tc.function.arguments),
            ))
        return LLMResponse(
            text=choice.message.content or "",
            tool_calls=calls,
            stop_reason="tool_use" if calls else "end_turn",
            usage={
                "input_tokens": getattr(ans.usage, "prompt_tokens", 0),
                "output_tokens": getattr(ans.usage, "completion_tokens", 0),
            },
        )


def _parse_args(s: str) -> dict[str, Any]:
    import json
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        return {}


class ProviderRoutingLLMClient(LLMClient):
    """Route model ids to the matching provider client.

    The API layer uses this for real Anthropic/OpenAI runs. Tests that
    install a recorded fake client bypass it, so deterministic test
    transcripts stay untouched.
    """

    def __init__(
        self,
        *,
        anthropic_key: str | None = None,
        openai_key: str | None = None,
        fallback: LLMClient | None = None,
    ) -> None:
        self.anthropic = AnthropicClient(api_key=anthropic_key)
        self.openai = OpenAIClient(api_key=openai_key)
        self.fallback = fallback

    async def complete(self, **kwargs) -> LLMResponse:
        model = str(kwargs.get("model", ""))
        if model.startswith("gpt-"):
            return await self.openai.complete(**kwargs)
        if model.startswith("claude-"):
            return await self.anthropic.complete(**kwargs)
        if self.fallback is not None:
            return await self.fallback.complete(**kwargs)
        return await self.anthropic.complete(**kwargs)
