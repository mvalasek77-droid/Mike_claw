"""Pydantic models shared across the Genie Swarm runtime, agents, and API.

These types are the contract between the iOS client, the FastAPI routes,
and the swarm orchestrator. Keep them small and JSON-friendly so the
streaming layer can serialise them efficiently.
"""
from __future__ import annotations

import time
import uuid
from enum import Enum
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Identity / addressing
# ---------------------------------------------------------------------------

def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


# ---------------------------------------------------------------------------
# Build request / job
# ---------------------------------------------------------------------------

class AppSpec(BaseModel):
    """The user's prompt, normalised. Produced by the API layer before the
    orchestrator runs so every agent works against the same contract."""
    title: str
    prompt: str
    category: str = "utility"
    style: str = "liquidGlass"
    target_ios: str = "17.0"
    bundle_id: str | None = None
    features: list[str] = Field(default_factory=list)


class BuildRequest(BaseModel):
    spec: AppSpec
    workspace_root: str | None = None
    parallel: bool = True
    skip_tests: bool = False
    model_overrides: dict[str, str] = Field(default_factory=dict)


class JobState(str, Enum):
    queued       = "queued"
    planning     = "planning"
    building     = "building"
    testing      = "testing"
    reviewing    = "reviewing"
    succeeded    = "succeeded"
    failed       = "failed"
    cancelled    = "cancelled"


class BuildJob(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("job"))
    spec: AppSpec
    state: JobState = JobState.queued
    created_at: float = Field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    workspace: str | None = None
    artifact_path: str | None = None
    summary: str | None = None
    error: str | None = None


# ---------------------------------------------------------------------------
# Runtime turn / message protocol  (Claude-Code-flavoured)
# ---------------------------------------------------------------------------

class ToolCall(BaseModel):
    id: str = Field(default_factory=lambda: _new_id("call"))
    name: str
    arguments: dict[str, Any]


class ToolResult(BaseModel):
    call_id: str
    ok: bool
    content: str
    duration_ms: int = 0
    metadata: dict[str, Any] = Field(default_factory=dict)


class Message(BaseModel):
    role: Literal["system", "user", "assistant", "tool"]
    content: str = ""
    tool_calls: list[ToolCall] = Field(default_factory=list)
    tool_result: ToolResult | None = None
    agent: str | None = None
    ts: float = Field(default_factory=time.time)


# ---------------------------------------------------------------------------
# Streaming events  — what the iOS client subscribes to over SSE
# ---------------------------------------------------------------------------

class SwarmEvent(BaseModel):
    """Discriminated by `type`. We use a flat shape so the iOS Swift decoder
    stays trivial and the wire format is debuggable in `curl`."""
    type: Literal[
        "job.created",
        "job.state",
        "agent.started",
        "agent.finished",
        "agent.thought",
        "tool.call",
        "tool.result",
        "log",
        "diff",
        "test.result",
        "review.finding",
        "artifact",
        "error",
        "done",
    ]
    ts: float = Field(default_factory=time.time)
    job_id: str
    agent: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Diffs / artifacts
# ---------------------------------------------------------------------------

class FileDiff(BaseModel):
    path: str
    operation: Literal["create", "modify", "delete"]
    before: Optional[str] = None
    after: Optional[str] = None
    additions: int = 0
    deletions: int = 0


class TestResult(BaseModel):
    suite: str
    passed: int
    failed: int
    skipped: int
    duration_ms: int
    details: list[str] = Field(default_factory=list)


class ReviewFinding(BaseModel):
    severity: Literal["info", "warning", "error", "critical"]
    title: str
    body: str
    file: str | None = None
    line: int | None = None
    autofix: str | None = None
