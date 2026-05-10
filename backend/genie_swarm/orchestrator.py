"""SwarmOrchestrator — runs the 8 agents across the build + test layers.

Layered model:

    [build]    Architect → (Coder ∥ Designer) → Integrator
    [test]     (Unit Tester ∥ UI Tester ∥ Reviewer ∥ Security)

The build layer produces a working Xcode project. The test layer fans
out in parallel against the same workspace and feeds back findings; the
orchestrator decides whether to ship, fix-and-rerun, or escalate.

Inspirations:
  • Claude Code → ConversationRuntime tool-loop (per agent)
  • Cursor       → parallel agent coordination + diff preview
  • Codex        → sandboxed shell, test-gated promotion
"""
from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from pathlib import Path

from .agents import (
    ALL_AGENTS, BUILD_LAYER, TEST_LAYER, AgentBlueprint, AgentRole,
)
from .agents.base import ARCHITECT, CODER, DESIGNER, INTEGRATOR
from .llm import LLMClient
from .models import BuildJob, JobState
from .runtime import ConversationRuntime, RuntimeConfig
from .session import Session
from .streaming import EventBus
from .tools import ToolRegistry
from .tools.base import default_registry


# Wire up the default tool registry once. Idempotent.
def _bootstrap_registry() -> ToolRegistry:
    if default_registry.all():
        return default_registry
    from .tools.filesystem import ReadFile, WriteFile, EditFile, ListDir
    from .tools.shell import RunShell, Grep
    from .tools.xcode import XcodeBuild, SwiftLint, XcrunSimctl
    from .tools.apple_docs import AppleDocs
    for t in (
        ReadFile(), WriteFile(), EditFile(), ListDir(),
        RunShell(), Grep(),
        XcodeBuild(), SwiftLint(), XcrunSimctl(),
        AppleDocs(),
    ):
        default_registry.register(t)
    return default_registry


@dataclass
class SwarmConfig:
    workspace_root: Path = Path("/tmp/genie-swarm")
    parallel_build: bool = True   # run Coder ∥ Designer
    parallel_test: bool = True    # run all four test agents in parallel
    skip_tests: bool = False
    runtime: RuntimeConfig = field(default_factory=RuntimeConfig)


class SwarmOrchestrator:
    def __init__(self, *, llm: LLMClient, bus: EventBus, config: SwarmConfig | None = None) -> None:
        self.llm = llm
        self.bus = bus
        self.config = config or SwarmConfig()
        self.tools = _bootstrap_registry()

    # ------------------------------------------------------------------
    # Public entrypoint
    # ------------------------------------------------------------------

    async def execute(self, job: BuildJob) -> Session:
        events = await self.bus.stream_for(job.id)
        await events.emit("job.created", **job.model_dump())

        session = Session.open(job, self.config.workspace_root)
        session.update_state(JobState.planning)
        await events.emit("job.state", state=session.job.state.value)

        try:
            # ---- BUILD LAYER ----
            await self._run_agent(ARCHITECT, session, events,
                                   prompt=self._architect_prompt(job))
            session.checkpoint("after-architect")

            session.update_state(JobState.building)
            await events.emit("job.state", state=session.job.state.value)

            if self.config.parallel_build:
                await asyncio.gather(
                    self._run_agent(CODER,    session, events, prompt=self._coder_prompt(job)),
                    self._run_agent(DESIGNER, session, events, prompt=self._designer_prompt(job)),
                )
            else:
                await self._run_agent(CODER,    session, events, prompt=self._coder_prompt(job))
                await self._run_agent(DESIGNER, session, events, prompt=self._designer_prompt(job))
            session.checkpoint("after-build-layer")

            await self._run_agent(INTEGRATOR, session, events,
                                   prompt=self._integrator_prompt(job))
            session.checkpoint("after-integrator")

            # ---- TEST LAYER ----
            if not self.config.skip_tests:
                session.update_state(JobState.testing)
                await events.emit("job.state", state=session.job.state.value)
                await self._run_test_layer(session, events)
                session.checkpoint("after-tests")

            # ---- DONE ----
            session.update_state(JobState.succeeded)
            session.job.summary = (
                f"{job.spec.title} built successfully — "
                f"{int((time.time() - (job.started_at or job.created_at)))}s end-to-end."
            )
            await events.emit("job.state", state=session.job.state.value, summary=session.job.summary)
            await events.emit("done", success=True)
        except asyncio.CancelledError:
            session.update_state(JobState.cancelled)
            await events.emit("job.state", state=session.job.state.value)
            await events.emit("done", success=False, reason="cancelled")
            raise
        except Exception as exc:  # noqa: BLE001
            session.update_state(JobState.failed, error=f"{type(exc).__name__}: {exc}")
            await events.emit("error", message=str(exc))
            await events.emit("done", success=False, reason="error")
            raise
        finally:
            session.save()

        return session

    # ------------------------------------------------------------------
    # Agent runner
    # ------------------------------------------------------------------

    async def _run_agent(
        self,
        blueprint: AgentBlueprint,
        session: Session,
        events,
        *,
        prompt: str,
    ):
        runtime = ConversationRuntime(
            agent_name=blueprint.title,
            system_prompt=blueprint.system_prompt,
            llm=self.llm,
            tools=blueprint.tools(self.tools),
            sandbox=session.sandbox,
            events=events,
            config=RuntimeConfig(
                model=blueprint.model,
                max_steps=self.config.runtime.max_steps,
                max_parallel_tool_calls=self.config.runtime.max_parallel_tool_calls,
                temperature=blueprint.temperature,
                max_tokens=self.config.runtime.max_tokens,
            ),
        )
        run = await runtime.run(user=prompt, transcript=session.transcript)
        session.transcript = run.transcript
        return run

    async def _run_test_layer(self, session: Session, events) -> None:
        if self.config.parallel_test:
            await asyncio.gather(*[
                self._run_agent(bp, session, events, prompt=self._test_prompt(bp, session.job))
                for bp in TEST_LAYER
            ])
        else:
            for bp in TEST_LAYER:
                await self._run_agent(bp, session, events, prompt=self._test_prompt(bp, session.job))

    # ------------------------------------------------------------------
    # Prompt templating
    # ------------------------------------------------------------------

    def _spec_block(self, job: BuildJob) -> str:
        s = job.spec
        feats = "\n".join(f"  - {f}" for f in s.features) or "  (none specified)"
        return (
            f"App: {s.title}\n"
            f"Category: {s.category}\n"
            f"Style: {s.style}\n"
            f"Target iOS: {s.target_ios}\n"
            f"Bundle ID: {s.bundle_id or 'auto'}\n"
            f"Prompt: {s.prompt}\n"
            f"Features:\n{feats}\n"
        )

    def _architect_prompt(self, job: BuildJob) -> str:
        return (
            f"{self._spec_block(job)}\n"
            "Plan the Xcode project. Write `docs/PLAN.md` and `docs/plan.json` "
            "to the workspace, then stop."
        )

    def _coder_prompt(self, job: BuildJob) -> str:
        return (
            "Implement every Swift file the Architect's plan calls for. "
            "Use the plan at `docs/plan.json`. Production quality only."
        )

    def _designer_prompt(self, job: BuildJob) -> str:
        return (
            "Implement every SwiftUI View the plan calls for. Lean on the "
            "Liquid Glass system. Verify accessibility labels, dark mode, "
            "and Dynamic Type on every screen."
        )

    def _integrator_prompt(self, job: BuildJob) -> str:
        return (
            "Glue the project together. Wire navigation, dependency "
            "injection, asset catalog, and bundle config. Run `swift build` "
            "(or xcodebuild) until it passes."
        )

    def _test_prompt(self, bp: AgentBlueprint, job: BuildJob) -> str:
        s = self._spec_block(job)
        if bp.role == AgentRole.unit_tester:
            return f"{s}\nWrite XCTest coverage. Run xcodebuild test until green."
        if bp.role == AgentRole.ui_tester:
            return f"{s}\nDrive simctl, capture screenshots, write XCUITests for the golden paths."
        if bp.role == AgentRole.reviewer:
            return f"{s}\nReview the diff, run swiftlint, output JSON findings."
        if bp.role == AgentRole.security:
            return f"{s}\nAudit for keys, ATS, input validation. Block on critical."
        return s
