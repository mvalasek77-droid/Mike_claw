"""Retrieves passages from Apple's HIG and SwiftUI docs.

Indexed offline at deploy time; the agents consult this rather than
making cold web fetches inside the sandbox. Keeps determinism high and
avoids accidental network egress.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .base import Tool, ToolContext
from ..sandbox import Sandbox


class AppleDocs(Tool):
    name = "apple_docs"
    description = (
        "Search Apple's Human Interface Guidelines, SwiftUI reference, "
        "and the iOS 26 Liquid Glass overview. Returns the most relevant "
        "passages with titles and source URLs."
    )

    INDEX_PATH = Path(__file__).parent / "_apple_docs_index.json"

    def schema(self) -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer", "default": 5},
            },
            "required": ["query"],
            "additionalProperties": False,
        }

    def _load(self) -> list[dict[str, Any]]:
        if not self.INDEX_PATH.exists():
            return []
        return json.loads(self.INDEX_PATH.read_text())

    async def run(self, args, sandbox: Sandbox, ctx: ToolContext) -> str:
        query_terms = {t.lower() for t in args["query"].split() if len(t) > 2}
        passages = self._load()
        if not passages:
            # Tiny inline fallback so the rest of the system stays usable.
            passages = _BUILTIN_PASSAGES

        scored: list[tuple[int, dict[str, Any]]] = []
        for p in passages:
            blob = (p.get("title", "") + " " + p.get("body", "")).lower()
            score = sum(blob.count(term) for term in query_terms)
            if score > 0:
                scored.append((score, p))
        scored.sort(key=lambda x: -x[0])

        out = []
        for _, p in scored[: int(args.get("limit", 5))]:
            out.append(f"### {p['title']}\n{p['body']}\nsource: {p.get('url', '—')}")
        return "\n\n".join(out) or "(no matching passages)"


# Tiny seed corpus — replace with the full offline index in production.
_BUILTIN_PASSAGES = [
    {
        "title": "Liquid Glass — overview",
        "body": (
            "Liquid Glass is the iOS 26 material system. It composites "
            "blurred backdrop + tint + thin specular highlight, with depth "
            "implied by parallax-aware shadows. Use .glassEffect(.regular) "
            "on rounded surfaces; combine with subtle inner highlights and "
            "a 0.5–1pt white stroke at low opacity for the glass edge."
        ),
        "url": "https://developer.apple.com/design/human-interface-guidelines/materials",
    },
    {
        "title": "Touch targets",
        "body": "Minimum tappable area is 44×44 pt. Even icon-only buttons need padding to reach this.",
        "url": "https://developer.apple.com/design/human-interface-guidelines/buttons",
    },
    {
        "title": "Dark Mode",
        "body": (
            "Use semantic colors (Color.primary, Color(.systemBackground)) "
            "and asset-catalog appearances. Test every screen in both modes "
            "and ensure contrast ≥ 4.5:1 for body text."
        ),
        "url": "https://developer.apple.com/design/human-interface-guidelines/dark-mode",
    },
    {
        "title": "Accessibility",
        "body": (
            "Every interactive view needs an accessibilityLabel. Group "
            "decorative elements with .accessibilityHidden(true). Support "
            "Dynamic Type by avoiding fixed font sizes for body copy."
        ),
        "url": "https://developer.apple.com/design/human-interface-guidelines/accessibility",
    },
    {
        "title": "App icon requirements",
        "body": (
            "1024×1024 PNG, sRGB, no alpha channel, no rounded corners. "
            "Apple applies the rounded mask. Submitting alpha = automatic "
            "rejection."
        ),
        "url": "https://developer.apple.com/design/human-interface-guidelines/app-icons",
    },
]
