"""
Writing Model Synthesizer
Combines literary analysis + market intelligence into a fully-specified
novel master plan: characters, plot arc, chapter outlines, thematic scaffolding.
This plan is what the generator consumes to produce 70k+ words.
"""

from __future__ import annotations
import json
import anthropic
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Any
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import ANTHROPIC_API_KEY, CLAUDE_MODEL, MAX_CHAPTERS, TARGET_WORD_COUNT
from analysis.literary_analyzer import (
    build_writing_blueprint, WritingBlueprint, PacingCalculator, blueprint_to_dict
)
from market.nyt_tracker import get_market_signals, get_genre_recommendation


SYNTHESIS_DIR = Path(__file__).parent


@dataclass
class Character:
    name: str
    role: str                  # protagonist / antagonist / supporting / foil
    age: int
    background: str
    core_wound: str            # the unresolved damage that drives them
    surface_want: str          # what they think they want
    deep_need: str             # what they actually need
    voice_notes: str           # how they speak and think
    arc: str                   # where they start and end emotionally
    physical_detail: str       # ONE defining sensory detail (not a list)


@dataclass
class NovelPlan:
    title: str
    logline: str               # one sentence
    back_cover_copy: str       # 150 words
    genre: str
    setting: str
    timeframe: str
    pov_character: str
    characters: list[Character]
    themes: list[str]
    chapter_outlines: list[dict]
    opening_line: str
    key_images: list[str]      # recurring motifs
    ending_note: str           # emotional destination (not plot spoiler)
    word_count_target: int
    comparable_titles: list[str]


# ── System prompt for the synthesizer ────────────────────────────────────────

SYNTHESIZER_SYSTEM = """You are a master literary architect with deep knowledge of:
- The 100 greatest novels ever written (Woolf, Morrison, McCarthy, Tolstoy, Achebe, etc.)
- The 100 all-time bestselling novels and their commercial DNA
- The last 40 Pulitzer Prize winners and the craft patterns that win that prize
- Current NYT bestseller trends and book club preferences

Your task is to synthesize ALL of this into a single, specific, publisher-ready novel plan.
You produce CONCRETE plans — actual character names, actual settings, actual chapter summaries.
Never use placeholders like [insert name here]. Every element must be specific and lived-in.

CRITICAL QUALITY REQUIREMENTS:
1. The novel must be publishable WITHOUT an AI disclaimer
2. Prose must sound like a living author with a distinct voice — not a composite
3. Every character must have a specific, concrete core wound — not vague 'trauma'
4. Themes emerge through story, never stated aloud by characters
5. The structure must be borrowed from the Pulitzer winners' toolkit:
   - Non-linear time handling within a clear three-act arc
   - Short-to-medium chapters (3,000-5,000 words) for book-club accessibility
   - Earned emotional payoffs, not manufactured moments
   - Specific place as a character, not generic backdrop

COMMERCIAL REQUIREMENTS (from bestseller analysis):
1. Protagonist must have an immediate, urgent, concrete problem on page 1
2. A love story thread (not necessarily central) must be present
3. The 'dark night of the soul' must genuinely threaten to destroy everything the protagonist wants
4. The ending must be satisfying but not tidy — leave one thread unresolved for the reader's imagination
5. Comparable titles must be from the last 5 years with strong book club track records
"""


# ── Core synthesizer class ─────────────────────────────────────────────────────

class NovelSynthesizer:
    def __init__(self):
        self.client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        self.blueprint: WritingBlueprint | None = None
        self.market: dict[str, Any] = {}

    def load_inputs(self) -> None:
        print("  [synth] Building literary blueprint...")
        self.blueprint = build_writing_blueprint(
            genre_blend=["upmarket literary fiction", "psychological thriller", "women's fiction"],
            market_signals=["book club appeal", "domestic secrets", "redemption arc"],
            target_word_count=TARGET_WORD_COUNT,
        )

        print("  [synth] Fetching market intelligence...")
        self.market = get_market_signals()
        self.genre_rec = get_genre_recommendation()
        print("  [synth] Inputs loaded.")

    def _build_synthesis_prompt(self) -> str:
        bp_dict = blueprint_to_dict(self.blueprint)

        return f"""
Based on the following distilled intelligence from 240 novels across three corpora,
create a COMPLETE, SPECIFIC, PUBLISHABLE novel master plan.

## LITERARY BLUEPRINT (from 100 greatest + 40 Pulitzer winners)
- Optimal structure: {bp_dict['structure']['archetype']}
- POV: {bp_dict['structure']['pov']}
- Time handling: {bp_dict['structure']['time_handling']}
- Chapter length: {bp_dict['structure']['chapter_length']}
- Opening strategy: {bp_dict['structure']['opening_strategy']}
- Resolution style: {bp_dict['structure']['resolution_style']}
- Theme intersection across all corpora: {bp_dict['theme_profile']['intersection']}
- Prose forbidden patterns: (see system prompt rules)
- Pulitzer prose signatures to employ: specificity, interiority, subtext, recurring motif, place-as-character, earned emotion

## COMMERCIAL DNA (from 100 bestsellers)
- Commercial hooks to weave in: {bp_dict['commercial_hooks']}
- Genre recommendation: {self.genre_rec['primary_genre']}
- Protagonist type: {self.genre_rec['protagonist_recommendation']}
- Setting recommendation: {self.genre_rec['setting_recommendation']}

## MARKET SIGNALS (current NYT / 2026)
- Hottest genres: {self.market['hottest_genres'][:5]}
- What book clubs want: {self.market['what_book_clubs_want'][:4]}
- Protagonist trends: {self.market['protagonist_trends'][:3]}
- Theme trends: {self.market['theme_trends'][:4]}
- Plot trends: {self.market['plot_trends'][:3]}
- AVOID: {self.market['avoid_now'][:4]}

## YOUR DELIVERABLE
Produce a complete JSON novel plan with this exact structure:
{{
  "title": "...",
  "logline": "One sentence max — who wants what, what stops them, what's at stake",
  "back_cover_copy": "150 words, present tense, no spoilers, sells the book",
  "genre": "...",
  "setting": "Specific town/region + time period",
  "timeframe": "Specific months/years the novel spans",
  "pov_character": "Name and brief description",
  "themes": ["theme 1", "theme 2", "theme 3", "theme 4"],
  "opening_line": "The actual first sentence of the novel",
  "key_images": ["recurring image 1", "recurring image 2", "recurring image 3"],
  "ending_note": "The emotional landing — what the reader should feel, NOT a plot summary",
  "word_count_target": {TARGET_WORD_COUNT},
  "comparable_titles": ["Title — Author (year)", ...],
  "characters": [
    {{
      "name": "...",
      "role": "protagonist",
      "age": 0,
      "background": "...",
      "core_wound": "Specific, concrete — not 'trauma'",
      "surface_want": "What they think they want",
      "deep_need": "What they actually need",
      "voice_notes": "How they speak, what metaphors they use",
      "arc": "Where they begin emotionally → where they end",
      "physical_detail": "ONE sensory detail that recurs"
    }}
    // include protagonist + 3-5 supporting characters
  ],
  "chapter_outlines": [
    {{
      "chapter": 1,
      "title": "...",
      "pov": "...",
      "beat": "HOOK",
      "target_words": 3500,
      "summary": "3-5 sentences: what happens, what is revealed, what question is raised",
      "opens_with": "The scene, image, or action that starts this chapter",
      "ends_with": "The hook or emotional note that pulls readers forward",
      "character_interiority": "What is the POV character wrestling with internally"
    }}
    // produce outlines for ALL {MAX_CHAPTERS} chapters
  ]
}}

REQUIREMENTS:
- Title must be literary but accessible — not precious, not generic
- Characters must have specific, unusual names that feel real
- Setting must be a specific, named American location with cultural specificity
- Chapter summaries must be specific enough that a writer can produce 3,500 words from them
- The opening line must be the actual first sentence — nothing will disqualify a novel faster than a weak opener
- Themes must emerge from story, never be stated explicitly
- Return ONLY valid JSON, nothing else
"""

    def synthesize(self, save_path: str | None = None) -> dict[str, Any]:
        print("  [synth] Calling Claude to synthesize novel plan...")

        response = self.client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=8096,
            system=SYNTHESIZER_SYSTEM,
            messages=[{"role": "user", "content": self._build_synthesis_prompt()}],
        )

        raw = response.content[0].text.strip()

        # Extract JSON if wrapped in markdown fences
        if raw.startswith("```"):
            lines = raw.split("\n")
            json_lines = [l for l in lines if not l.startswith("```")]
            raw = "\n".join(json_lines)

        plan = json.loads(raw)

        if save_path:
            with open(save_path, "w") as f:
                json.dump(plan, f, indent=2)
            print(f"  [synth] Novel plan saved → {save_path}")

        return plan


def build_novel_plan(save_path: str | None = None) -> dict[str, Any]:
    """Convenience entry point called by the orchestrator."""
    synth = NovelSynthesizer()
    synth.load_inputs()
    return synth.synthesize(save_path=save_path)


if __name__ == "__main__":
    plan = build_novel_plan(save_path=str(SYNTHESIS_DIR / "novel_plan.json"))
    print(f"\n=== NOVEL PLAN ===")
    print(f"Title: {plan.get('title')}")
    print(f"Logline: {plan.get('logline')}")
    print(f"Genre: {plan.get('genre')}")
    print(f"Setting: {plan.get('setting')}")
    print(f"Chapters: {len(plan.get('chapter_outlines', []))}")
