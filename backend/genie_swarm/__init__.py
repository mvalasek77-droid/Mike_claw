"""Genie Swarm — multi-agent Swift app builder.

Public surface:
    from genie_swarm import SwarmOrchestrator, SwarmConfig
    from genie_swarm.api import router as swarm_router

Mount the router on your FastAPI app:
    app.include_router(swarm_router)
"""
from .models import (
    AppSpec, BuildJob, BuildRequest, JobState, Message, ToolCall, ToolResult,
    SwarmEvent, FileDiff, TestResult, ReviewFinding,
)
from .orchestrator import SwarmConfig, SwarmOrchestrator
from .runtime import ConversationRuntime, RuntimeConfig, AgentRun
from .session import Session, Checkpoint
from .streaming import EventBus, EventStream

__all__ = [
    "AppSpec", "BuildJob", "BuildRequest", "JobState",
    "Message", "ToolCall", "ToolResult", "SwarmEvent",
    "FileDiff", "TestResult", "ReviewFinding",
    "SwarmConfig", "SwarmOrchestrator",
    "ConversationRuntime", "RuntimeConfig", "AgentRun",
    "Session", "Checkpoint",
    "EventBus", "EventStream",
]

__version__ = "0.1.0"
