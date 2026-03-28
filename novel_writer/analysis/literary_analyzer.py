"""
Literary Analysis Engine
Distills structural, tonal, pacing, and thematic patterns from the three corpora
into a unified writing blueprint that the synthesizer and generator can consume.
"""

from __future__ import annotations
import json
from collections import Counter, defaultdict
from dataclasses import dataclass, field, asdict
from typing import Any
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from corpus import (
    GREATEST_NOVELS, STRUCTURAL_ARCHETYPES, UNIVERSAL_THEMES, PACING_BEATS,
    BESTSELLING_NOVELS, COMMERCIAL_HOOKS, COMMERCIAL_TRENDS_BY_DECADE,
    PULITZER_WINNERS, PULITZER_STRUCTURAL_PATTERNS, PULITZER_PROSE_SIGNATURES,
    PULITZER_FORBIDDEN, PULITZER_RECURRING_THEMES,
)


# ── Data classes ──────────────────────────────────────────────────────────────

@dataclass
class ThemeProfile:
    universal: list[str]
    commercial: list[str]
    literary: list[str]
    intersection: list[str]   # appear in all three corpora

@dataclass
class StructureBlueprint:
    archetype: str
    act_count: int
    pov: str
    time_handling: str
    chapter_length: str
    pacing_map: dict[str, tuple[float, float]]
    opening_strategy: str
    climax_placement: float
    resolution_style: str

@dataclass
class ProseStyle:
    sentence_variety: str
    avg_sentence_length: int         # target words per sentence
    paragraph_rhythm: str
    interiority_level: str           # low / medium / high
    dialogue_density: str            # sparse / moderate / frequent
    sensory_register: str            # visual / tactile / olfactory weight
    forbidden_patterns: list[str]
    signature_moves: list[str]

@dataclass
class WritingBlueprint:
    theme_profile: ThemeProfile
    structure: StructureBlueprint
    prose_style: ProseStyle
    commercial_hooks: list[str]
    market_signals: list[str]
    estimated_word_count: int
    chapter_count: int
    genre_blend: list[str]
    target_reader: str
    comparable_titles: list[str]


# ── Analysis functions ────────────────────────────────────────────────────────

def extract_theme_intersection() -> ThemeProfile:
    """Find themes that appear across all three corpora — these are the bedrock."""
    # Gather theme tokens from greatest novels
    greatest_themes: Counter[str] = Counter()
    for entry in GREATEST_NOVELS:
        themes = entry[8] if isinstance(entry[8], list) else list(entry[8])
        for t in themes:
            greatest_themes[t.lower()] += 1

    # Gather from bestsellers
    commercial_themes: Counter[str] = Counter()
    for entry in BESTSELLING_NOVELS:
        for t in entry[5]:
            commercial_themes[t.lower()] += 1

    # Gather from Pulitzer
    literary_themes: Counter[str] = Counter()
    for entry in PULITZER_WINNERS:
        for t in entry[6]:
            literary_themes[t.lower()] += 1

    # Top themes per corpus
    top_greatest = {t for t, _ in greatest_themes.most_common(20)}
    top_commercial = {t for t, _ in commercial_themes.most_common(20)}
    top_literary = {t for t, _ in literary_themes.most_common(20)}

    # Intersection heuristic: themes whose root word appears across all three
    def normalize(s: str) -> str:
        return s.replace("-", " ").replace("_", " ").lower().strip()

    def themes_overlap(a: str, b: str) -> bool:
        na, nb = normalize(a).split(), normalize(b).split()
        return bool(set(na) & set(nb))

    intersection: list[str] = []
    for gt in top_greatest:
        if any(themes_overlap(gt, ct) for ct in top_commercial) and \
           any(themes_overlap(gt, lt) for lt in top_literary):
            intersection.append(gt)

    return ThemeProfile(
        universal=list(top_greatest)[:10],
        commercial=list(top_commercial)[:10],
        literary=list(top_literary)[:10],
        intersection=intersection[:8],
    )


def derive_optimal_structure(market_genre: str = "literary thriller") -> StructureBlueprint:
    """
    Derive the statistically optimal structure for a novel that wins prizes
    AND sells. Based on Pulitzer patterns + bestseller structure analysis.
    """
    # Pulitzer shows 52% non-linear, commercial shows tight three-act wins
    # Sweet spot: three-act backbone with non-linear time within acts
    return StructureBlueprint(
        archetype="three_act_with_braided_timeline",
        act_count=3,
        pov="third_close_single_plus_limited_intrusions",
        time_handling="non_linear_within_linear_acts",
        chapter_length="short_to_medium_3000_to_5000_words",
        pacing_map=PACING_BEATS,
        opening_strategy="in_medias_res_with_immediate_sensory_grounding",
        climax_placement=0.90,
        resolution_style="earned_ambiguous_but_hopeful",
    )


def derive_prose_style() -> ProseStyle:
    """
    Synthesize the prose style signature that:
    - Passes Pulitzer quality bar (specificity, interiority, subtext)
    - Reads like human writing (sentence variety, imperfections)
    - Avoids AI-detectable patterns (uniform sentence length, hollow abstractions)
    """
    return ProseStyle(
        sentence_variety="high_variance_mix_of_3_word_to_40_word_sentences",
        avg_sentence_length=17,
        paragraph_rhythm="beat_pause_beat_expansive_breathe",
        interiority_level="high",
        dialogue_density="moderate_dialogue_advances_character_not_just_plot",
        sensory_register="tactile_and_olfactory_privileged_over_purely_visual",
        forbidden_patterns=PULITZER_FORBIDDEN + [
            # AI-specific tells
            "transitional adverbs as paragraph openers (Furthermore, Moreover, Additionally)",
            "the word 'tapestry' used metaphorically",
            "the word 'navigate' used metaphorically for life challenges",
            "the phrase 'at the end of the day'",
            "the phrase 'in conclusion'",
            "perfectly balanced sentence triplets (A, B, and C) overused",
            "every character having exactly one defining physical trait mentioned on introduction",
            "chapter endings that all close with a reflective summary sentence",
            "dialogue tags beyond 'said' and 'asked' appearing more than 15% of the time",
            "em-dash overuse (more than 2 per page on average)",
            "semicolons used as stylistic flourish rather than grammatical necessity",
            "the word 'suddenly' more than once per 10,000 words",
            "back-to-back sentences starting with 'She/He'",
            "rhetorical questions directed at the reader",
        ],
        signature_moves=list(PULITZER_PROSE_SIGNATURES.values()),
    )


def score_commercial_viability(genre_blend: list[str]) -> list[str]:
    """Return the highest-impact commercial hooks for the given genre blend."""
    relevant_hooks = []
    genre_str = " ".join(genre_blend).lower()

    hook_priority = {
        "thriller": ["ticking_clock", "stakes_immediate", "secret_revealed"],
        "romance":  ["forbidden_desire", "love_story_thread", "moral_dilemma"],
        "literary": ["redemption_arc", "moral_dilemma", "found_family"],
        "mystery":  ["secret_revealed", "ticking_clock", "relatable_protagonist"],
        "fantasy":  ["chosen_one_variant", "found_family", "stakes_immediate"],
    }

    for genre_key, hooks in hook_priority.items():
        if genre_key in genre_str:
            relevant_hooks.extend(hooks)

    # Always include these three — present in 90%+ of bestsellers
    for must_have in ["love_story_thread", "relatable_protagonist", "redemption_arc"]:
        if must_have not in relevant_hooks:
            relevant_hooks.append(must_have)

    return list(dict.fromkeys(relevant_hooks))  # deduplicate preserving order


def build_writing_blueprint(
    genre_blend: list[str] | None = None,
    market_signals: list[str] | None = None,
    target_word_count: int = 85_000,
) -> WritingBlueprint:
    """Master function: produce a complete WritingBlueprint ready for the generator."""
    genre_blend = genre_blend or ["literary fiction", "psychological thriller", "redemption drama"]
    market_signals = market_signals or ["domestic thriller trend", "book-club literary", "female protagonist momentum"]

    theme_profile = extract_theme_intersection()
    structure = derive_optimal_structure(" ".join(genre_blend))
    prose_style = derive_prose_style()
    commercial_hooks = score_commercial_viability(genre_blend)

    chapter_count = max(20, min(30, target_word_count // 3_000))

    comparable_titles = [
        "Where the Crawdads Sing (Delia Owens)",
        "Olive Kitteridge (Elizabeth Strout)",
        "Gone Girl (Gillian Flynn)",
        "The Kite Runner (Khaled Hosseini)",
        "All the Light We Cannot See (Anthony Doerr)",
    ]

    return WritingBlueprint(
        theme_profile=theme_profile,
        structure=structure,
        prose_style=prose_style,
        commercial_hooks=commercial_hooks,
        market_signals=market_signals,
        estimated_word_count=target_word_count,
        chapter_count=chapter_count,
        genre_blend=genre_blend,
        target_reader="Adult literary fiction reader, 25-55, book-club participant",
        comparable_titles=comparable_titles,
    )


def blueprint_to_dict(bp: WritingBlueprint) -> dict[str, Any]:
    return asdict(bp)


def save_blueprint(bp: WritingBlueprint, path: str) -> None:
    with open(path, "w") as f:
        json.dump(blueprint_to_dict(bp), f, indent=2)
    print(f"Blueprint saved → {path}")


def load_blueprint(path: str) -> dict[str, Any]:
    with open(path) as f:
        return json.load(f)


# ── Pacing calculator ─────────────────────────────────────────────────────────

class PacingCalculator:
    """
    Given total word count and chapter count, produces a per-chapter pacing plan
    showing what beat each chapter must hit and its approximate word count.
    """

    BEAT_LABELS = {
        "opening_hook":    "HOOK — sensory/action open, protagonist in motion",
        "world_establish": "ESTABLISH — world, character voice, first tension",
        "first_turn":      "TURN 1 — inciting incident, stakes clarified",
        "midpoint_mirror": "MIDPOINT — false victory or mirror moment",
        "dark_night":      "DARK NIGHT — all-is-lost, protagonist at bottom",
        "climax":          "CLIMAX — confrontation, no return",
        "denouement":      "CLOSE — aftermath, new equilibrium, earned emotion",
    }

    def __init__(self, total_words: int, chapter_count: int):
        self.total_words = total_words
        self.chapter_count = chapter_count
        self.words_per_chapter = total_words // chapter_count

    def chapter_beat(self, chapter_num: int) -> str:
        """Return the dominant story beat for a given chapter number (1-indexed)."""
        progress = (chapter_num - 1) / (self.chapter_count - 1)
        for beat, (start, end) in PACING_BEATS.items():
            if start <= progress <= end:
                return self.BEAT_LABELS.get(beat, beat)
        return "DEVELOPMENT — deepen character, escalate subplot"

    def full_chapter_plan(self) -> list[dict]:
        plan = []
        for i in range(1, self.chapter_count + 1):
            plan.append({
                "chapter": i,
                "target_words": self.words_per_chapter,
                "beat": self.chapter_beat(i),
                "cumulative_words": i * self.words_per_chapter,
            })
        return plan


if __name__ == "__main__":
    bp = build_writing_blueprint()
    print("\n=== WRITING BLUEPRINT ===")
    print(f"Genre blend: {bp.genre_blend}")
    print(f"Target words: {bp.estimated_word_count:,}")
    print(f"Chapters: {bp.chapter_count}")
    print(f"\nTheme intersection: {bp.theme_profile.intersection}")
    print(f"Commercial hooks: {bp.commercial_hooks}")
    print(f"\nForbidden patterns: {len(bp.prose_style.forbidden_patterns)} rules loaded")

    pc = PacingCalculator(bp.estimated_word_count, bp.chapter_count)
    print("\n=== CHAPTER PACING PLAN ===")
    for ch in pc.full_chapter_plan():
        print(f"  Ch {ch['chapter']:02d} | {ch['target_words']:,}w | {ch['beat']}")
