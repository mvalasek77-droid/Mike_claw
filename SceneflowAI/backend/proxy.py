"""
Sceneflow AI proxy — OPTIONAL reference implementation.

You do NOT need this to use the app. By default Sceneflow uses on-device
bring-your-own-key (the user's Anthropic key in the iOS Keychain, calling the
API directly). This proxy is only for the advanced case where you'd rather not
have each user supply a key — e.g. distributing to many non-technical users.
In that case the app POSTs to this server, which holds the key in its
environment and calls the Claude Messages API. Select "My server" in
Settings → AI and set the URL.

Run locally:

    pip install -r requirements.txt
    export ANTHROPIC_API_KEY=sk-ant-...
    uvicorn proxy:app --host 0.0.0.0 --port 8000

Then set the app's AI Backend URL (Settings → AI Backend) to your server's
public URL. In production, put this behind auth (per-user tokens), rate limit
it, and enforce your own AI-usage entitlements before calling Claude.
"""

from __future__ import annotations

import os
from typing import Literal

import anthropic
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Sceneflow AI Proxy")

# The SDK reads ANTHROPIC_API_KEY from the environment. Keep it server-side.
client = anthropic.Anthropic()

# Default to Claude Opus 4.8 — Anthropic's most capable Opus-tier model and a
# strong default for creative writing assistance. The app may request a
# different supported model; we allow-list to avoid arbitrary passthrough.
ALLOWED_MODELS = {"claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5"}
DEFAULT_MODEL = "claude-opus-4-8"


class Message(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class GenerateRequest(BaseModel):
    model: str = DEFAULT_MODEL
    system: str = ""
    messages: list[Message]
    max_tokens: int = Field(default=1500, ge=1, le=8000)
    # The app's "creativity" dial maps to the effort knob.
    effort: Literal["low", "medium", "high", "max"] = "medium"


class GenerateResponse(BaseModel):
    text: str
    model: str
    stop_reason: str | None = None


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/generate", response_model=GenerateResponse)
def generate(req: GenerateRequest) -> GenerateResponse:
    model = req.model if req.model in ALLOWED_MODELS else DEFAULT_MODEL

    try:
        # Adaptive thinking + effort is the recommended setup on Opus 4.8 for
        # anything that benefits from deliberation (coverage, structure work).
        message = client.messages.create(
            model=model,
            max_tokens=req.max_tokens,
            system=req.system,
            thinking={"type": "adaptive"},
            output_config={"effort": req.effort},
            messages=[m.model_dump() for m in req.messages],
        )
    except anthropic.APIStatusError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.message) from exc
    except anthropic.APIConnectionError as exc:
        raise HTTPException(status_code=502, detail="Upstream connection error") from exc

    # A safety classifier may decline the request: HTTP 200, but
    # stop_reason == "refusal" with empty/partial content. Surface it cleanly
    # rather than indexing into an empty content list.
    if message.stop_reason == "refusal":
        raise HTTPException(
            status_code=422,
            detail="The request was declined by the model's safety system.",
        )

    text = "".join(block.text for block in message.content if block.type == "text")
    return GenerateResponse(text=text, model=message.model, stop_reason=message.stop_reason)
