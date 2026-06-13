"""Prompt formatting — turn a user's rough app description into a clean,
provider-tuned build brief.

CodeGenie users type a free-form description ("a habit tracker that nags
me"). Different LLMs respond best to different prompt SHAPES:

  * Claude (Anthropic) is tuned for explicit XML-style structure —
    `<task>`, `<requirements>`, `<constraints>` — and clear role framing.
  * GPT (OpenAI) is tuned for markdown headers and numbered requirement
    lists with an explicit deliverable section.

This module is deliberately DETERMINISTIC — no LLM round-trip — so the
formatting is instant, free, and unit-testable. The iOS app shows the
formatted result as a live preview before a build, and the orchestrator
feeds the same structured brief to the Architect so the plan starts from
a clean contract instead of a one-liner.
"""
from __future__ import annotations

from .models import AppSpec

# Providers we format for. "anthropic" → Claude shape, "openai" → GPT shape.
CLAUDE = "anthropic"
GPT = "openai"


def provider_for_model(model_id: str) -> str:
    """Map a model id to the provider whose prompt shape suits it.
    Unknown ids default to the Claude shape (the app's default engine)."""
    if model_id.startswith("gpt") or model_id.startswith("o1") or model_id.startswith("o3"):
        return GPT
    return CLAUDE


def _clean(text: str) -> str:
    """Collapse whitespace runs and trim — a paste from Notes shouldn't
    carry stray newlines into the structured brief."""
    return " ".join((text or "").split())


def _requirement_lines(spec: AppSpec) -> list[str]:
    """The concrete, checkable requirements distilled from the spec. Used
    by both provider shapes so the substance is identical and only the
    formatting differs."""
    reqs: list[str] = []
    desc = _clean(spec.prompt)
    if desc:
        reqs.append(desc if desc.endswith(".") else desc + ".")
    for feature in spec.features:
        f = _clean(feature)
        if f:
            reqs.append(f if f.endswith(".") else f + ".")
    # Baseline quality bar every CodeGenie app must clear — stated
    # explicitly so the agents don't have to infer it.
    reqs.append("Ship a first-run experience that explains the app in one screen.")
    reqs.append("Handle empty, loading, and error states for every data view.")
    reqs.append("Persist user data locally so nothing is lost on relaunch.")
    return reqs


def format_app_prompt(spec: AppSpec, provider: str) -> str:
    """Render the spec as a provider-optimized iOS build brief."""
    title = _clean(spec.title) or "Untitled app"
    constraints = [
        f"Target iOS {spec.target_ios} and Swift / SwiftUI only.",
        f"Visual style: {spec.style}.",
        f"App Store category: {spec.category}.",
        "Follow Apple's Human Interface Guidelines; support Dark Mode, "
        "Dynamic Type, and VoiceOver.",
        "No third-party dependencies unless strictly necessary.",
    ]
    reqs = _requirement_lines(spec)

    if provider == GPT:
        return _format_gpt(title, reqs, constraints)
    return _format_claude(title, reqs, constraints)


def _format_claude(title: str, reqs: list[str], constraints: list[str]) -> str:
    req_block = "\n".join(f"  - {r}" for r in reqs)
    con_block = "\n".join(f"  - {c}" for c in constraints)
    return (
        "<task>\n"
        f"Build a production-quality iOS app called \"{title}\".\n"
        "</task>\n\n"
        "<requirements>\n"
        f"{req_block}\n"
        "</requirements>\n\n"
        "<constraints>\n"
        f"{con_block}\n"
        "</constraints>\n\n"
        "<deliverable>\n"
        "  A complete, buildable Xcode project that compiles cleanly, with "
        "the requirements above met and no placeholder TODOs.\n"
        "</deliverable>"
    )


def _format_gpt(title: str, reqs: list[str], constraints: list[str]) -> str:
    req_block = "\n".join(f"{i}. {r}" for i, r in enumerate(reqs, 1))
    con_block = "\n".join(f"- {c}" for c in constraints)
    return (
        f"# Build: {title}\n\n"
        "## Requirements\n"
        f"{req_block}\n\n"
        "## Constraints\n"
        f"{con_block}\n\n"
        "## Deliverable\n"
        "A complete, buildable Xcode project that compiles cleanly, meets "
        "every requirement above, and contains no placeholder TODOs."
    )
