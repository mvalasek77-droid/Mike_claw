"""Agent blueprints — pure data: the role, the system prompt, the tool set.

Prompts live as ``prompts/*.md`` files alongside this package so they
can be edited and reviewed like documentation. We load them lazily and
fall back to a small inline string if the file is missing — that way
the package still works when installed from a wheel without the data
files (rare, but possible).
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from ..tools import ToolRegistry, default_registry


class AgentRole(str, Enum):
    architect    = "architect"
    coder        = "coder"
    designer     = "designer"
    integrator   = "integrator"
    unit_tester  = "unit_tester"
    ui_tester    = "ui_tester"
    reviewer     = "reviewer"
    security     = "security"


@dataclass
class AgentBlueprint:
    role: AgentRole
    title: str           # human-friendly, e.g. "🏗️ Architect"
    prompt_file: str     # filename under prompts/, e.g. "architect.md"
    fallback_prompt: str # used if the file is missing
    model: str = "claude-opus-4-7"
    temperature: float = 0.2
    tool_names: tuple[str, ...] = ()           # subset of registry; empty = all
    layer: str = "build"                       # "build" | "test"

    @property
    def system_prompt(self) -> str:
        path = _PROMPTS_DIR / self.prompt_file
        if path.exists():
            try:
                return path.read_text(encoding="utf-8")
            except OSError:
                pass
        return self.fallback_prompt

    def tools(self, registry: ToolRegistry = default_registry) -> ToolRegistry:
        if not self.tool_names:
            return registry
        sub = ToolRegistry()
        for name in self.tool_names:
            sub.register(registry.get(name))
        return sub


_PROMPTS_DIR = Path(__file__).resolve().parent.parent / "prompts"


# ---------------------------------------------------------------------------
# Blueprints
# ---------------------------------------------------------------------------

ARCHITECT = AgentBlueprint(
    role=AgentRole.architect,
    title="🏗️ Architect",
    layer="build",
    tool_names=("read_file", "list_dir", "apple_docs", "write_file"),
    prompt_file="architect.md",
    fallback_prompt=(
        "You are the Architect. Plan the Xcode project: file map, modules, "
        "screens. Write docs/PLAN.md and docs/plan.json. Stop after writing them."
    ),
)

CODER = AgentBlueprint(
    role=AgentRole.coder,
    title="💻 Coder",
    layer="build",
    tool_names=("read_file", "write_file", "edit_file", "list_dir", "shell", "grep"),
    prompt_file="coder.md",
    fallback_prompt=(
        "You are the Coder. Read docs/plan.json and implement every Swift "
        "source file the plan calls for that isn't a SwiftUI View. Production "
        "quality only."
    ),
)

DESIGNER = AgentBlueprint(
    role=AgentRole.designer,
    title="🎨 Designer",
    layer="build",
    tool_names=("read_file", "write_file", "edit_file", "apple_docs", "list_dir"),
    prompt_file="designer.md",
    fallback_prompt=(
        "You are the Designer. Implement every SwiftUI View the plan calls "
        "for. Liquid Glass, accessibility, dark mode."
    ),
)

INTEGRATOR = AgentBlueprint(
    role=AgentRole.integrator,
    title="🔗 Integrator",
    layer="build",
    tool_names=("read_file", "write_file", "edit_file", "list_dir", "grep", "shell"),
    prompt_file="integrator.md",
    fallback_prompt=(
        "You are the Integrator. Wire navigation, dependency injection, "
        "asset catalog, and Info.plist. Stop when xcodebuild succeeds."
    ),
)

UNIT_TESTER = AgentBlueprint(
    role=AgentRole.unit_tester,
    title="🧪 Unit Tester",
    layer="test",
    tool_names=("read_file", "write_file", "edit_file", "shell", "grep"),
    prompt_file="unit_tester.md",
    fallback_prompt=(
        "You are the Unit Tester. Generate XCTest coverage. Aim for ≥70% "
        "line coverage on non-View files. Run xcodebuild test until green."
    ),
)

UI_TESTER = AgentBlueprint(
    role=AgentRole.ui_tester,
    title="📱 UI Tester",
    layer="test",
    tool_names=("read_file", "write_file", "edit_file", "shell", "simctl", "apple_docs"),
    prompt_file="ui_tester.md",
    fallback_prompt=(
        "You are the UI Tester. Drive simctl, capture screenshots, write "
        "XCUITests for the golden paths."
    ),
)

REVIEWER = AgentBlueprint(
    role=AgentRole.reviewer,
    title="👁️ Code Reviewer",
    layer="test",
    tool_names=("read_file", "list_dir", "grep", "swiftlint", "shell"),
    prompt_file="reviewer.md",
    fallback_prompt=(
        "You are the Code Reviewer. Run swiftlint and review the diff. "
        "Output JSON list of findings."
    ),
)

SECURITY = AgentBlueprint(
    role=AgentRole.security,
    title="🔒 Security Auditor",
    layer="test",
    tool_names=("read_file", "list_dir", "grep", "shell"),
    prompt_file="security.md",
    fallback_prompt=(
        "You are the Security Auditor. Look for hard-coded keys, ATS issues, "
        "input validation, keychain misuse. Block on critical."
    ),
)


BUILD_LAYER: tuple[AgentBlueprint, ...] = (ARCHITECT, CODER, DESIGNER, INTEGRATOR)
TEST_LAYER:  tuple[AgentBlueprint, ...] = (UNIT_TESTER, UI_TESTER, REVIEWER, SECURITY)
ALL_AGENTS:  tuple[AgentBlueprint, ...] = BUILD_LAYER + TEST_LAYER
