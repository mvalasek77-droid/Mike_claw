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
from .agents.base import ARCHITECT, CODER, DESIGNER, INTEGRATOR, UNIT_TESTER
from .llm import LLMClient
from .memory import Memory
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
    from .tools.memory import RememberFact, RecallMemory, NoteDecision
    from .tools.testflight import TestFlightUpload
    for t in (
        ReadFile(), WriteFile(), EditFile(), ListDir(),
        RunShell(), Grep(),
        XcodeBuild(), SwiftLint(), XcrunSimctl(),
        AppleDocs(),
        RememberFact(), RecallMemory(), NoteDecision(),
        TestFlightUpload(),
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
    # Per-agent model overrides. Keys are AgentRole values
    # ("architect", "coder", ...). Falls back to blueprint.model when a
    # role isn't present. Lets the iOS app route Opus to Reviewer and
    # Haiku to UI-Tester, for example, without code changes here.
    model_overrides: dict[str, str] = field(default_factory=dict)
    # Max times we re-run Coder + Integrator + Unit Tester after the
    # Unit Tester reports failures. 0 disables retries (the test layer
    # still runs, but failing tests don't loop).
    max_retries: int = 3
    # Crash recovery: if an agent throws unexpectedly, restore from
    # the latest checkpoint and retry up to this many times before
    # giving up. Distinct from `max_retries` (which loops on red
    # tests). 0 disables recovery — failures bubble immediately.
    max_crash_recoveries: int = 2
    # Optional ship stage: after the test layer succeeds, upload the
    # built .ipa to TestFlight and watch processing state until Apple
    # marks it VALID/FAILED/INVALID/EXPIRED. None = don't ship.
    ship: ShipConfig | None = None


@dataclass
class ShipConfig:
    """Settings for the orchestrator's optional shipping stage."""
    ipa_path: str                            # workspace-relative .ipa
    bundle_id: str
    apple_id: str | None = None              # for altool BYO-creds path
    app_specific_password: str | None = None
    asc_api_key_id: str | None = None        # preferred: ASC API key
    asc_api_issuer_id: str | None = None
    asc_api_key_path: str | None = None      # workspace-relative .p8
    poll_after_upload: bool = True
    poll_timeout_s: float = 60 * 60
    poll_interval_s: float = 30.0


class SwarmOrchestrator:
    def __init__(self, *, llm: LLMClient, bus: EventBus, config: SwarmConfig | None = None) -> None:
        self.llm = llm
        self.bus = bus
        self.config = config or SwarmConfig()
        self.tools = _bootstrap_registry()
        self.memory = Memory(self.config.workspace_root)

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

            # ---- SHIP (optional) ----
            if self.config.ship:
                await self._run_ship_stage(session, events)

            # ---- DONE ----
            session.update_state(JobState.succeeded)
            session.job.summary = (
                f"{job.spec.title} built successfully — "
                f"{int((time.time() - (job.started_at or job.created_at)))}s end-to-end."
            )
            self.memory.record_project(
                job.id, job.spec.title, job.spec.model_dump(),
                succeeded=True, summary=session.job.summary,
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
            self.memory.record_project(
                job.id, job.spec.title, job.spec.model_dump(),
                succeeded=False, summary=f"failed: {exc}",
            )
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
        """Run one agent. Wraps the inner call in crash-recovery — if
        the agent throws an unexpected exception we restore from the
        most recent checkpoint and try again, up to `max_crash_recoveries`.
        Test-failure retries are handled separately in `_run_test_layer`."""
        attempts_left = max(0, self.config.max_crash_recoveries)
        last_exc: BaseException | None = None
        while True:
            try:
                return await self._run_agent_once(blueprint, session, events, prompt=prompt)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                last_exc = exc
                if attempts_left <= 0:
                    raise
                attempts_left -= 1
                await events.emit(
                    "retry.attempt", agent=blueprint.title,
                    attempt=self.config.max_crash_recoveries - attempts_left,
                    max_retries=self.config.max_crash_recoveries,
                    reason=f"crash: {type(exc).__name__}",
                )
                # Roll back to the latest checkpoint so we don't carry
                # partial state from the crashed turn into the retry.
                if session.checkpoints:
                    session.restore(session.checkpoints[-1])

    async def _run_agent_once(
        self,
        blueprint: AgentBlueprint,
        session: Session,
        events,
        *,
        prompt: str,
    ):
        # Paste a memory briefing on top of the agent's system prompt so
        # past preferences carry across builds. Also surface it to the
        # iOS transcript so the user can *see* what the swarm remembers.
        briefing = self.memory.briefing()
        if briefing:
            await events.emit(
                "memory.briefing",
                agent=blueprint.title,
                text=briefing,
            )
        full_system = (briefing + "\n\n" + blueprint.system_prompt) if briefing else blueprint.system_prompt
        # Per-agent model override beats blueprint default.
        model = self.config.model_overrides.get(blueprint.role.value, blueprint.model)
        runtime = ConversationRuntime(
            agent_name=blueprint.title,
            system_prompt=full_system,
            llm=self.llm,
            tools=blueprint.tools(self.tools),
            sandbox=session.sandbox,
            events=events,
            config=RuntimeConfig(
                model=model,
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
        # Loop: Unit Tester first; if it reports failures, re-run Coder
        # + Integrator + Unit Tester until green or `max_retries` is
        # exceeded. Then run the remaining test agents in parallel.
        unit_run = await self._run_agent(
            UNIT_TESTER, session, events,
            prompt=self._test_prompt(UNIT_TESTER, session.job),
        )
        attempts = 0
        while attempts < self.config.max_retries and self._unit_tests_failed(unit_run):
            attempts += 1
            await events.emit(
                "retry.attempt", agent=UNIT_TESTER.title,
                attempt=attempts, max_retries=self.config.max_retries,
            )
            await self._run_agent(
                CODER, session, events,
                prompt=self._fix_prompt(session.job, unit_run.final_message.content),
            )
            await self._run_agent(
                INTEGRATOR, session, events,
                prompt="Tests just failed. Re-glue anything the Coder changed, "
                       "then run `swift build` / `xcodebuild` until it's green.",
            )
            unit_run = await self._run_agent(
                UNIT_TESTER, session, events,
                prompt=self._test_prompt(UNIT_TESTER, session.job),
            )

        # The other test agents (UI Tester, Reviewer, Security) — same
        # parallel-or-serial knob.
        remaining = tuple(bp for bp in TEST_LAYER if bp is not UNIT_TESTER)
        if self.config.parallel_test:
            await asyncio.gather(*[
                self._run_agent(bp, session, events, prompt=self._test_prompt(bp, session.job))
                for bp in remaining
            ])
        else:
            for bp in remaining:
                await self._run_agent(bp, session, events, prompt=self._test_prompt(bp, session.job))

    @staticmethod
    def _unit_tests_failed(run) -> bool:
        """Heuristic: does the Unit Tester's final message indicate
        red tests? We look for explicit failure markers — xcodebuild's
        `Failing tests:` line, `TEST FAILED`, or an explicit count of
        > 0 failures. The agent is told to say so in plain English."""
        text = (run.final_message.content or "").lower()
        if not text:
            return False
        if "all tests pass" in text or "all green" in text or "0 failures" in text:
            return False
        markers = [
            "failing tests:",
            "test failed",
            "tests failed",
            "** test failed **",
            "build failed",
        ]
        if any(m in text for m in markers):
            return True
        # Numeric "N failure" / "N failures" where N > 0.
        import re as _re
        match = _re.search(r"(\d+)\s+failures?\b", text)
        if match and int(match.group(1)) > 0:
            return True
        return False

    async def ship_only(self, job: BuildJob, ship_config: "ShipConfig") -> Session:
        """Run **only** the ship stage on a previously built job's workspace.

        Used by the `POST /{job}/ship` endpoint so the user can promote
        a green build to TestFlight from the iOS success screen without
        rebuilding. We re-open the session from disk (no transcript
        replay needed — the workspace is the source of truth) and call
        the same `_run_ship_stage` that `execute()` uses, so the wire
        shape is identical."""
        previous_ship = self.config.ship
        self.config.ship = ship_config
        try:
            session = Session.open(job, self.config.workspace_root)
            events = await self.bus.stream_for(job.id)
            await events.emit("job.state", state="shipping", detail="manual ship-only run")
            try:
                await self._run_ship_stage(session, events)
                await events.emit("done", success=True, ship_only=True)
            except Exception as exc:  # noqa: BLE001
                await events.emit("error", message=f"ship failed: {exc}")
                await events.emit("done", success=False, ship_only=True)
                raise
            return session
        finally:
            self.config.ship = previous_ship

    async def _run_ship_stage(self, session: Session, events) -> None:
        """Promote the build to TestFlight, then watch ASC processing.

        This is intentionally not delegated to an agent — the upload
        tool already exists, and a deterministic call gives us tighter
        guarantees than asking an LLM to invoke it correctly. The
        poller runs to completion before we mark the job done so the
        iOS UI can show the final state in the same SSE stream."""
        from .testflight_status import PollerConfig, watch
        from .tools.testflight import TestFlightUpload
        from .tools.base import ToolContext
        from .models import ToolCall

        ship = self.config.ship
        assert ship is not None

        await events.emit(
            "job.state", state="shipping",
            detail=f"uploading {ship.ipa_path} to TestFlight",
        )

        upload = TestFlightUpload()
        ctx = ToolContext(
            job_id=session.job.id, agent="🚀 Shipper",
            workspace=str(session.sandbox.policy.workspace),
        )
        args: dict[str, object] = {"ipa_path": ship.ipa_path, "validate": True}
        for k in ("apple_id", "app_specific_password",
                  "asc_api_key_id", "asc_api_issuer_id", "asc_api_key_path"):
            v = getattr(ship, k)
            if v: args[k] = v

        result = await self.tools.invoke(
            ToolCall(name="testflight_upload", arguments=args),
            session.sandbox, ctx,
        )
        await events.emit(
            "testflight.upload",
            ok=result.ok,
            preview=result.content[-1500:],
        )
        if not result.ok:
            # Don't fail the whole job — record the upload failure and
            # let the user inspect. The Memory layer logs it.
            self.memory.note_decision(
                session.job.id, "shipping",
                f"TestFlight upload failed: {result.content[:300]}",
            )
            return

        if not ship.poll_after_upload:
            return

        # Poll Apple's processing pipeline. ASC API requires the
        # ES256-signed JWT path — only available when the user pre-
        # configured ASC API key creds.
        if not (ship.asc_api_key_id and ship.asc_api_issuer_id and ship.asc_api_key_path):
            await events.emit(
                "testflight.status", state="POLL_SKIPPED",
                detail="No ASC API key configured — upload finished but status polling needs the JWT path.",
            )
            return

        poller_cfg = PollerConfig(
            api_key_id=ship.asc_api_key_id,
            issuer_id=ship.asc_api_issuer_id,
            p8_path=str(session.sandbox.safe_path(ship.asc_api_key_path)),
            bundle_id=ship.bundle_id,
            poll_interval_s=ship.poll_interval_s,
            timeout_s=ship.poll_timeout_s,
        )
        try:
            await watch(poller_cfg, events)
        except Exception as exc:  # noqa: BLE001
            await events.emit("testflight.status", state="POLL_ERROR", detail=str(exc))

    def _fix_prompt(self, job: BuildJob, unit_tester_output: str) -> str:
        return (
            "The Unit Tester reported failures:\n\n"
            f"{unit_tester_output[:4000]}\n\n"
            "Fix the underlying Swift code. Do not modify the tests to make "
            "them pass — change the implementation until the existing "
            "tests are green. Run `swift build` (or `xcodebuild`) until it "
            "succeeds before declaring done."
        )

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
