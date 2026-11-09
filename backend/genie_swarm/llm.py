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
    stop_reason: str = "end_turn"   # end_turn | tool_use | max_tokens | refusal
    usage: dict[str, int] = field(default_factory=dict)
    # The provider's own content blocks for this turn, verbatim. Claude
    # returns `thinking` blocks that must be replayed unchanged on the
    # next request of a tool loop, so the runtime stores these on the
    # assistant `Message` instead of rebuilding the turn from `text`.
    provider_blocks: list[dict[str, Any]] | None = None


# ---------------------------------------------------------------------------
# Model ids
# ---------------------------------------------------------------------------

DEFAULT_MODEL = "claude-opus-5-5"
COACH_MODEL = "claude-sonnet-5-5"

# Ids an older app build may still have saved in its per-agent routing.
# Resolved here so a stale phone setting cannot break a build.
_SUPERSEDED_MODELS: dict[str, str] = {
    "claude-opus-4-7": "claude-opus-5-5",
    "claude-opus-4-8": "claude-opus-5-5",
    "claude-opus-5": "claude-opus-5-5",
    "claude-sonnet-4-6": "claude-sonnet-5-5",
    "claude-sonnet-5": "claude-sonnet-5-5",
    "claude-haiku-4-5": "claude-haiku-5-5",
}

# Models whose policy declines can be rescued server-side.
_SERVER_FALLBACK_MODELS = frozenset({"claude-opus-5-5", "claude-sonnet-5-5"})
_FALLBACK_BETA = "server-side-fallback-2026-07-01"


def canonical_model(model: str) -> str:
    return _SUPERSEDED_MODELS.get(model, model)


def is_openai_model(model: str) -> bool:
    return model.startswith(("gpt-", "o1", "o3", "o4"))


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
        max_tokens: int = 16000,
        temperature: float = 0.2,
        effort: str | None = None,
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

        # No api_key argument when none was injected: the SDK then
        # resolves credentials from the environment on its own.
        client = AsyncAnthropic(api_key=self.api_key) if self.api_key else AsyncAnthropic()
        model = canonical_model(kwargs["model"])
        request: dict[str, Any] = {
            "model": model,
            "system": kwargs["system"],
            "messages": _to_anthropic_messages(kwargs["messages"]),
            "max_tokens": kwargs.get("max_tokens", 16000),
        }
        if kwargs.get("tools"):
            request["tools"] = kwargs["tools"]
        # Current Claude models reject sampling parameters and run
        # adaptive thinking by default; effort is the depth control.
        if kwargs.get("effort"):
            request["output_config"] = {"effort": kwargs["effort"]}

        if model in _SERVER_FALLBACK_MODELS:
            ans = await client.beta.messages.create(
                betas=[_FALLBACK_BETA], fallbacks="default", **request
            )
        else:
            ans = await client.messages.create(**request)

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
            provider_blocks=[b.model_dump(exclude_none=True) for b in ans.content],
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
        if m.role == "assistant" and m.provider_blocks:
            out.append({"role": "assistant", "content": m.provider_blocks})
            continue
        if m.role == "assistant" and not m.content and not m.tool_calls:
            continue   # an empty turn is rejected by the API
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
            max_completion_tokens=kwargs.get("max_tokens", 16000),
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


# ---------------------------------------------------------------------------
# Routing — one client for the orchestrator, the right vendor per model
# ---------------------------------------------------------------------------

class RoutingLLMClient(LLMClient):
    """Sends each request to the vendor that owns the model id.

    Per-agent routing lets a user put one agent on GPT and the rest on
    Claude; without this every id went to the Anthropic client and the
    GPT ones failed as unknown models."""

    def __init__(
        self,
        anthropic: LLMClient | None = None,
        openai: LLMClient | None = None,
    ) -> None:
        self.anthropic = anthropic or AnthropicClient()
        self.openai = openai or OpenAIClient()

    async def complete(self, **kwargs) -> LLMResponse:
        if is_openai_model(kwargs["model"]):
            kwargs.pop("effort", None)
            return await self.openai.complete(**kwargs)
        return await self.anthropic.complete(**kwargs)
