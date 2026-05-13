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


class ShipRequest(BaseModel):
    """Wire-level subset of orchestrator.ShipConfig. The iOS app POSTs
    one of these when the user taps "Submit to App Store" — typed
    separately from the orchestrator's internal dataclass so the API
    layer doesn't leak dataclass-only types."""
    ipa_path: str
    bundle_id: str
    apple_id: str | None = None
    app_specific_password: str | None = None
    asc_api_key_id: str | None = None
    asc_api_issuer_id: str | None = None
    asc_api_key_path: str | None = None
    poll_after_upload: bool = True


class BuildRequest(BaseModel):
    spec: AppSpec
    workspace_root: str | None = None
    parallel: bool = True
    skip_tests: bool = False
    model_overrides: dict[str, str] = Field(default_factory=dict)
    ship: ShipRequest | None = None
    # Halt the build if rolling USD spend crosses this cap. None
    # disables enforcement. Backend computes spend using
    # genie_swarm.cost.DEFAULT_PRICES.
    cost_cap_usd: float | None = None
    # User-defined agents to run after the standard test layer. Each
    # entry: { name, system_prompt, tool_allowlist }.
    custom_agents: list[dict[str, Any]] = Field(default_factory=list)
    # Per-build snapshot-bytes ceiling. None = use SwarmConfig default
    # (256 MiB). The iOS UI lets the user lift this from Settings.
    max_snapshot_bytes: int | None = None


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
        "retry.attempt",
        "memory.briefing",
        "testflight.upload",
        "testflight.upload.progress",
        "testflight.status",
        "cost.update",
        "cost.cap_hit",
        "workspace.full",
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
