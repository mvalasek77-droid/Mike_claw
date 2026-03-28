"""
Novel Generation Engine
Uses Claude to write each chapter in sequence, maintaining:
- Consistent voice and style
- Pacing beat fidelity (each chapter hits its required beat)
- Character continuity across chapters
- Cumulative word count tracking toward 70k+ target
- Context window management: carries a rolling scene memory
"""

from __future__ import annotations
import json
import time
import re
import anthropic
from pathlib import Path
from dataclasses import dataclass
from typing import Any
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import (
    ANTHROPIC_API_KEY, CLAUDE_MODEL,
    MIN_WORD_COUNT, TARGET_WORD_COUNT, CHAPTER_TARGET_WORDS,
)


GENERATION_DIR = Path(__file__).parent


# ── Writer system prompt (the core creative instruction) ─────────────────────

WRITER_SYSTEM = """You are a Pulitzer-caliber novelist writing a complete, publishable literary novel.

YOUR VOICE PROFILE (derived from analysis of 100 greatest novels + 40 Pulitzer winners):
- Sentence length: HIGH VARIANCE — mix 3-word declarations with 40-word subordinate chains
- Paragraph rhythm: beat-pause-beat — short sharp paragraph, then breath, then long expansion
- Interiority: DEEP — readers live inside the protagonist's mind, but it never becomes navel-gazing
- Sensory priority: tactile and olfactory details carry as much weight as visual
- Dialogue: advances character, not plot — what people DON'T say matters more than what they do
- Subtext: every scene has a surface event and a subterranean emotional current
- Metaphor: drawn from the specific world of the novel — not generic literary device
- Emotion: EARNED, never manufactured — never tell the reader how to feel

FORBIDDEN PATTERNS (will disqualify this as AI-written):
- Transitional adverbs opening paragraphs (Furthermore, Moreover, Additionally, However)
- The words 'tapestry', 'navigate' (as life metaphor), 'delve', 'realm', 'landscape' (as metaphor)
- Perfectly balanced sentence triplets (A, B, and C) used more than once per 5,000 words
- Every character introduced with exactly one physical trait
- Chapter endings that summarize what just happened emotionally
- Dialogue tags beyond 'said'/'asked' more than 15% of dialogue exchanges
- Em-dashes used as stylistic decoration (only for genuine interruption or strong break)
- Back-to-back sentences starting with the same pronoun
- Rhetorical questions directed at the reader
- Uniform paragraph lengths — vary from 1 line to 10 lines

REQUIRED CRAFT ELEMENTS (from Pulitzer analysis):
- SPECIFICITY over generality always: "the smell of cedar and WD-40" not "the familiar workshop smell"
- Place is a character: the setting has mood, history, and pressure that acts on the humans
- Recurring motif: establish one image in chapter 1 that will accumulate meaning through the novel
- Iceberg principle: know 10x more about each character than you write — only show what serves the scene
- Scene-sequel structure: scene (action, conflict, resolution) → sequel (reaction, dilemma, decision)

You write ONLY the chapter text. No preamble, no author's note, no word counts.
Start mid-scene. End on a hook or earned emotional note that pulls readers forward.
"""


def count_words(text: str) -> int:
    return len(text.split())


def extract_chapter_title(text: str) -> str:
    """Extract title from chapter text if it opens with one."""
    first_line = text.strip().split("\n")[0]
    if len(first_line) < 80 and not first_line.endswith("."):
        return first_line
    return ""


# ── Chapter writer ────────────────────────────────────────────────────────────

class ChapterWriter:
    """Writes a single chapter given the novel plan and running context."""

    def __init__(self, client: anthropic.Anthropic, novel_plan: dict[str, Any]):
        self.client = client
        self.plan = novel_plan
        self.characters_summary = self._build_characters_summary()
        self.themes_summary = ", ".join(novel_plan.get("themes", []))
        self.setting = novel_plan.get("setting", "")
        self.key_images = novel_plan.get("key_images", [])
        self.opening_line = novel_plan.get("opening_line", "")
        self.pov_character = novel_plan.get("pov_character", "")

    def _build_characters_summary(self) -> str:
        chars = self.plan.get("characters", [])
        lines = []
        for c in chars:
            lines.append(
                f"{c['name']} ({c['role']}): Core wound = {c['core_wound']}. "
                f"Wants {c['surface_want']}, needs {c['deep_need']}. "
                f"Voice: {c['voice_notes']}. Arc: {c['arc']}."
            )
        return "\n".join(lines)

    def _build_chapter_prompt(
        self,
        outline: dict[str, Any],
        previous_chapters_summary: str,
        chapter_number: int,
        total_chapters: int,
        words_written: int,
    ) -> str:
        words_remaining = TARGET_WORD_COUNT - words_written
        is_first = chapter_number == 1
        is_last = chapter_number == total_chapters

        first_chapter_note = ""
        if is_first:
            first_chapter_note = f"""
CRITICAL — CHAPTER ONE SPECIAL RULES:
- The VERY FIRST SENTENCE of this novel is: "{self.opening_line}"
  Use it exactly. Everything flows from this sentence.
- Establish the protagonist's voice within the first 3 paragraphs
- Ground the reader in a specific physical location in the first 200 words
- The inciting disruption must be present or imminent by the end of this chapter
- Do NOT open with weather, waking up, looking in a mirror, or backstory
"""

        last_chapter_note = ""
        if is_last:
            last_chapter_note = """
CRITICAL — FINAL CHAPTER SPECIAL RULES:
- The ending must be earned, not manufactured
- Leave one image or question unresolved — the reader should close the book in quiet thought
- No triumphant speeches. No explicit statement of theme.
- The final line should resonate against the opening line — circular or contrastive echo
- Characters should feel like they will continue living after the last page
"""

        return f"""
NOVEL: "{self.plan.get('title', 'Untitled')}"
GENRE: {self.plan.get('genre', '')}
SETTING: {self.setting}
TIMEFRAME: {self.plan.get('timeframe', '')}
POV: {self.pov_character}
THEMES: {self.themes_summary}
KEY RECURRING IMAGES: {', '.join(self.key_images)}

CHARACTERS:
{self.characters_summary}

STORY SO FAR (rolling summary):
{previous_chapters_summary if previous_chapters_summary else "This is the opening chapter."}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CHAPTER {chapter_number} OF {total_chapters}
Title: {outline.get('title', f'Chapter {chapter_number}')}
Story beat: {outline.get('beat', 'DEVELOPMENT')}
Target words: {outline.get('target_words', CHAPTER_TARGET_WORDS):,}
POV: {outline.get('pov', self.pov_character)}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CHAPTER BRIEF:
{outline.get('summary', '')}

Opens with: {outline.get('opens_with', '')}
Ends with: {outline.get('ends_with', '')}
Character's internal struggle: {outline.get('character_interiority', '')}

STATISTICS:
Words written so far: {words_written:,} / {TARGET_WORD_COUNT:,} target
Words remaining for this chapter: ~{outline.get('target_words', CHAPTER_TARGET_WORDS):,}

{first_chapter_note}
{last_chapter_note}

Write Chapter {chapter_number} now. Aim for {outline.get('target_words', CHAPTER_TARGET_WORDS):,} words minimum.
Do not include a chapter header in your response — start with the prose directly.
If you must include a chapter title, put it on the very first line with nothing else.
"""

    def write_chapter(
        self,
        outline: dict[str, Any],
        previous_summary: str,
        chapter_number: int,
        total_chapters: int,
        words_written: int,
    ) -> str:
        prompt = self._build_chapter_prompt(
            outline, previous_summary, chapter_number, total_chapters, words_written
        )

        response = self.client.messages.create(
            model=CLAUDE_MODEL,
            max_tokens=6000,
            system=WRITER_SYSTEM,
            messages=[{"role": "user", "content": prompt}],
        )

        return response.content[0].text.strip()


# ── Summary builder (avoids context overflow) ─────────────────────────────────

class RollingSummary:
    """
    Maintains a compressed summary of chapters written so far.
    Prevents context overflow while preserving plot/character continuity.
    """

    def __init__(self, client: anthropic.Anthropic, novel_plan: dict[str, Any]):
        self.client = client
        self.plan = novel_plan
        self.summary = ""
        self.chapters_summarized = 0

    def update(self, chapter_text: str, chapter_number: int) -> None:
        """Add a new chapter to the rolling summary."""
        update_prompt = f"""
You are maintaining a story continuity log for a novel.

EXISTING SUMMARY (of chapters 1-{self.chapters_summarized}):
{self.summary if self.summary else "No chapters written yet."}

NEW CHAPTER {chapter_number}:
{chapter_text[:3000]}  ← (first 3,000 words)

Update the story continuity log to include chapter {chapter_number}.
Keep the total log under 800 words.
Focus on: what happened, what was revealed, where each character is emotionally,
what questions were raised, what images or motifs appeared.
Return ONLY the updated log, nothing else.
"""
        response = self.client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1024,
            messages=[{"role": "user", "content": update_prompt}],
        )
        self.summary = response.content[0].text.strip()
        self.chapters_summarized = chapter_number


# ── Main generator ────────────────────────────────────────────────────────────

class NovelGenerator:
    """
    Orchestrates chapter-by-chapter generation of a full 70k+ word novel.
    Saves progress after each chapter so generation can be resumed on failure.
    """

    def __init__(self, novel_plan: dict[str, Any], output_dir: Path | None = None):
        self.plan = novel_plan
        self.client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        self.output_dir = output_dir or GENERATION_DIR / "drafts"
        self.output_dir.mkdir(parents=True, exist_ok=True)

        self.chapter_writer = ChapterWriter(self.client, novel_plan)
        self.rolling_summary = RollingSummary(self.client, novel_plan)

        self.chapters: list[dict[str, Any]] = []
        self.total_words = 0

        title_slug = re.sub(r"[^a-z0-9]+", "_", novel_plan.get("title", "untitled").lower())
        self.draft_file = self.output_dir / f"{title_slug}_draft.json"
        self.text_file  = self.output_dir / f"{title_slug}_manuscript.txt"

    def _load_progress(self) -> int:
        """Returns the chapter number to resume from (1-indexed)."""
        if self.draft_file.exists():
            with open(self.draft_file) as f:
                data = json.load(f)
            self.chapters = data.get("chapters", [])
            self.total_words = sum(c.get("word_count", 0) for c in self.chapters)
            self.rolling_summary.summary = data.get("rolling_summary", "")
            self.rolling_summary.chapters_summarized = len(self.chapters)
            resume_from = len(self.chapters) + 1
            print(f"  [gen] Resuming from chapter {resume_from} ({self.total_words:,} words written)")
            return resume_from
        return 1

    def _save_progress(self) -> None:
        data = {
            "plan_title": self.plan.get("title"),
            "total_words": self.total_words,
            "chapters": self.chapters,
            "rolling_summary": self.rolling_summary.summary,
        }
        with open(self.draft_file, "w") as f:
            json.dump(data, f, indent=2)

    def _save_manuscript(self) -> None:
        with open(self.text_file, "w", encoding="utf-8") as f:
            f.write(f"{self.plan.get('title', 'UNTITLED').upper()}\n")
            f.write(f"A Novel\n\n")
            f.write("─" * 60 + "\n\n")
            for i, ch in enumerate(self.chapters, 1):
                title = ch.get("title", f"Chapter {i}")
                f.write(f"\n{title.upper()}\n\n")
                f.write(ch["text"])
                f.write("\n\n" + "─" * 60 + "\n")
        print(f"  [gen] Manuscript saved → {self.text_file}")

    def generate(self) -> dict[str, Any]:
        """Generate the full novel. Returns the final draft data."""
        outlines = self.plan.get("chapter_outlines", [])
        total_chapters = len(outlines)

        if total_chapters == 0:
            raise ValueError("Novel plan has no chapter outlines. Run synthesizer first.")

        resume_from = self._load_progress()

        print(f"\n  [gen] Starting generation: {self.plan.get('title')}")
        print(f"  [gen] {total_chapters} chapters | {TARGET_WORD_COUNT:,} word target")

        for i, outline in enumerate(outlines):
            ch_num = i + 1

            if ch_num < resume_from:
                continue

            print(f"\n  [gen] Writing chapter {ch_num}/{total_chapters}: {outline.get('title', '')} ...")
            print(f"         Beat: {outline.get('beat', '')}")
            print(f"         Words so far: {self.total_words:,}")

            try:
                text = self.chapter_writer.write_chapter(
                    outline=outline,
                    previous_summary=self.rolling_summary.summary,
                    chapter_number=ch_num,
                    total_chapters=total_chapters,
                    words_written=self.total_words,
                )

                wc = count_words(text)
                self.total_words += wc

                chapter_data = {
                    "chapter": ch_num,
                    "title": outline.get("title", f"Chapter {ch_num}"),
                    "beat": outline.get("beat", ""),
                    "word_count": wc,
                    "text": text,
                }
                self.chapters.append(chapter_data)

                # Update rolling summary
                self.rolling_summary.update(text, ch_num)

                # Save progress after each chapter
                self._save_progress()
                self._save_manuscript()

                print(f"         ✓ Chapter {ch_num} done: {wc:,} words | Total: {self.total_words:,}")

                # Brief pause to respect API rate limits
                if ch_num < total_chapters:
                    time.sleep(2)

            except anthropic.RateLimitError:
                print(f"  [gen] Rate limit hit on chapter {ch_num}. Waiting 60s...")
                time.sleep(60)
                # Will retry on next run (progress was saved)
                break

            except Exception as e:
                print(f"  [gen] Error on chapter {ch_num}: {e}")
                self._save_progress()
                raise

        # Final word count check
        print(f"\n  [gen] Generation complete!")
        print(f"  [gen] Total words: {self.total_words:,} (target: {MIN_WORD_COUNT:,}+)")

        if self.total_words < MIN_WORD_COUNT:
            deficit = MIN_WORD_COUNT - self.total_words
            print(f"  [gen] WARNING: {deficit:,} words short of minimum. Consider expanding chapters.")

        self._save_manuscript()

        return {
            "title": self.plan.get("title"),
            "total_words": self.total_words,
            "chapter_count": len(self.chapters),
            "manuscript_file": str(self.text_file),
            "draft_file": str(self.draft_file),
        }


def generate_novel(
    novel_plan: dict[str, Any],
    output_dir: Path | None = None,
) -> dict[str, Any]:
    """Convenience entry point called by the orchestrator."""
    gen = NovelGenerator(novel_plan, output_dir)
    return gen.generate()


if __name__ == "__main__":
    plan_path = Path(__file__).parent.parent / "synthesis" / "novel_plan.json"
    if not plan_path.exists():
        print("ERROR: Run synthesis/model_synthesizer.py first to generate novel_plan.json")
        sys.exit(1)

    with open(plan_path) as f:
        plan = json.load(f)

    result = generate_novel(plan)
    print(f"\nManuscript: {result['manuscript_file']}")
    print(f"Total words: {result['total_words']:,}")
