"""
Anti-AI Detection Humanizer
Multi-pass rewriting system that removes detectable AI prose patterns and
injects authentic human voice characteristics found in Pulitzer Prize winners.

Three passes:
1. SURGICAL PASS — find/replace specific AI tells (regex + LLM)
2. RHYTHM PASS — vary sentence lengths, break uniform patterns (LLM)
3. VOICE PASS — deepen interiority, ground in specific sensory detail (LLM)
"""

from __future__ import annotations
import re
import json
import anthropic
from pathlib import Path
from dataclasses import dataclass
from typing import Any
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import ANTHROPIC_API_KEY, CLAUDE_MODEL, CLAUDE_HAIKU, HUMANIZER_PASSES


HUMANIZER_DIR = Path(__file__).parent

# ── AI tell patterns (regex level) ───────────────────────────────────────────

AI_TELLS_REGEX = [
    # Transitional adverbs at paragraph start
    (r"(?m)^(Furthermore|Moreover|Additionally|Subsequently|Consequently|Nevertheless|Nonetheless|Therefore|Thus|Hence),\s+", ""),
    # Hollow abstractions
    (r"\b(tapestry of|navigate[sd]? (life|grief|trauma|complexity|challenges?)|delve into|realm of|landscape of (emotion|feeling)|myriad of)\b", "[REPHRASE]"),
    # AI intensifiers
    (r"\b(deeply|profoundly|utterly|absolutely|truly|simply|just|quite|rather|very)\s+(important|significant|meaningful|powerful|beautiful|complex|challenging)\b", "[REPHRASE]"),
    # Stilted constructions
    (r"\bIt is worth noting that\b", ""),
    (r"\bIt is important to (note|remember|acknowledge)\b", ""),
    (r"\bin conclusion\b", ""),
    (r"\bIn summary\b", ""),
    (r"\bTo summarize\b", ""),
    (r"\bAt the end of the day\b", ""),
    # Overused phrases
    (r"\b(bear witness to|stand testament to|paint a picture of|speak volumes)\b", "[REPHRASE]"),
    # Em-dash decoration (catch double-spaced em dashes)
    (r" — ([a-z])", r"—\1"),  # normalize spacing first
]

# ── Humanizer prompts ─────────────────────────────────────────────────────────

PASS1_SURGICAL_SYSTEM = """You are an editor removing AI-generated prose patterns from literary fiction.
Your job is SURGICAL — fix specific problems, do NOT rewrite passages that are working.

PATTERNS TO FIX (change these when you see them):
1. Any [REPHRASE] markers left by the pre-processor — rewrite naturally
2. Uniform sentence length (5+ consecutive sentences of the same approximate length) — vary them
3. Back-to-back sentences starting with the same pronoun (She/He/They) — restructure
4. Dialogue tags other than 'said'/'asked' used more than once per scene — simplify
5. Em-dashes used decoratively — convert to comma, period, or rephrase
6. Paragraphs that ALL end with a complete, rounded sentence — break some mid-thought
7. Lists of three (A, B, and C) appearing more than twice in the passage — break the pattern

NEVER:
- Change the story events or character actions
- Alter proper nouns, names, or places
- Add new plot elements
- Remove emotional moments
- Make the prose MORE formal

Return the corrected passage only. No explanation.
"""

PASS2_RHYTHM_SYSTEM = """You are a literary editor tuning prose rhythm for a Pulitzer-caliber novel.

TARGET RHYTHM (from analysis of Toni Morrison, Cormac McCarthy, Elizabeth Strout):
- Short sentences after intense moments: "She left. That was all."
- Long, subordinate sentences for interiority and memory
- One-word or two-word paragraphs for maximum impact at key moments
- Vary first words of sentences — no pattern of same-word starts
- Dialogue must have silence and pauses built into it — what doesn't get said
- Physical action described in short declarative sentences
- Thought and feeling described in longer, more complex sentences

Make micro-edits to rhythm. Do NOT change story content.
Return the edited passage only.
"""

PASS3_VOICE_SYSTEM = """You are a master editor deepening the human voice in literary fiction.
Your goal: make this read like it was written by a specific living author, not a machine.

TECHNIQUES:
1. SPECIFICITY — replace any generic detail with something specific and unexpected
   "the old house" → "the house where the gutters still leaked onto the back steps"
   "she felt sad" → "something behind her sternum went quiet"

2. OBLIQUE EMOTION — never name the emotion directly; find the physical sensation or behavioral tell
   "he was angry" → "he began sorting through the mail twice"

3. IDIOSYNCRATIC OBSERVATION — the narrator notices things other narrators wouldn't
   A clock that's 7 minutes fast. A neighbor who always parks with one wheel on the curb.

4. UNFINISHED THOUGHTS — humans think in fragments; let some thoughts trail off or contradict

5. BODY KNOWLEDGE — sensory experience rooted in the specific body of the protagonist
   Not "she smelled coffee" but "the coffee smell snagged something in her chest"

6. PLACE PRESSURE — the setting should push back on the characters

Fix 3-5 places per passage using these techniques. Mark NO changes visible to reader.
Return the revised passage only.
"""


# ── Utility functions ─────────────────────────────────────────────────────────

def apply_regex_fixes(text: str) -> str:
    """Apply all regex-level AI tell removals."""
    for pattern, replacement in AI_TELLS_REGEX:
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text


def split_into_passages(text: str, max_words: int = 800) -> list[str]:
    """Split text into passages for LLM processing (stays within token limits)."""
    paragraphs = text.split("\n\n")
    passages: list[str] = []
    current: list[str] = []
    current_words = 0

    for para in paragraphs:
        para_words = len(para.split())
        if current_words + para_words > max_words and current:
            passages.append("\n\n".join(current))
            current = [para]
            current_words = para_words
        else:
            current.append(para)
            current_words += para_words

    if current:
        passages.append("\n\n".join(current))

    return passages


def llm_rewrite_passage(
    client: anthropic.Anthropic,
    passage: str,
    system: str,
    model: str = CLAUDE_HAIKU,
) -> str:
    """Run a single LLM rewrite pass on a passage."""
    if len(passage.strip()) < 50:
        return passage

    response = client.messages.create(
        model=model,
        max_tokens=2048,
        system=system,
        messages=[{"role": "user", "content": f"PASSAGE TO EDIT:\n\n{passage}"}],
    )
    return response.content[0].text.strip()


# ── Main humanizer class ──────────────────────────────────────────────────────

class AntiAIHumanizer:
    """
    Takes a raw generated chapter and runs it through three rewriting passes
    to remove AI patterns and deepen human voice.
    """

    def __init__(self):
        self.client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    def humanize_chapter(self, text: str, chapter_num: int) -> str:
        """
        Run the full three-pass humanization on a chapter.
        Returns the humanized chapter text.
        """
        print(f"    [humanizer] Ch {chapter_num} — Pass 1: Surgical fixes...")
        # Regex pass first (fast, deterministic)
        text = apply_regex_fixes(text)

        # LLM surgical pass
        passages = split_into_passages(text, max_words=700)
        fixed_passages = []
        for p in passages:
            fixed = llm_rewrite_passage(self.client, p, PASS1_SURGICAL_SYSTEM)
            fixed_passages.append(fixed)
        text = "\n\n".join(fixed_passages)

        print(f"    [humanizer] Ch {chapter_num} — Pass 2: Rhythm tuning...")
        passages = split_into_passages(text, max_words=700)
        rhythm_passages = []
        for p in passages:
            fixed = llm_rewrite_passage(self.client, p, PASS2_RHYTHM_SYSTEM)
            rhythm_passages.append(fixed)
        text = "\n\n".join(rhythm_passages)

        print(f"    [humanizer] Ch {chapter_num} — Pass 3: Voice deepening...")
        passages = split_into_passages(text, max_words=700)
        voiced_passages = []
        for p in passages:
            # Use CLAUDE_MODEL for voice pass — most important for quality
            fixed = llm_rewrite_passage(self.client, p, PASS3_VOICE_SYSTEM, model=CLAUDE_MODEL)
            voiced_passages.append(fixed)
        text = "\n\n".join(voiced_passages)

        return text

    def score_ai_likelihood(self, text: str) -> dict[str, Any]:
        """
        Heuristic AI detection score based on known pattern frequencies.
        Lower is better (0 = very human-like, 100 = very AI-like).
        """
        word_count = len(text.split())
        if word_count == 0:
            return {"score": 0, "flags": []}

        flags = []
        score = 0

        # Sentence length variance (human writing has HIGH variance)
        sentences = re.split(r"[.!?]+", text)
        sent_lengths = [len(s.split()) for s in sentences if s.strip()]
        if sent_lengths:
            mean_len = sum(sent_lengths) / len(sent_lengths)
            variance = sum((l - mean_len) ** 2 for l in sent_lengths) / len(sent_lengths)
            if variance < 30:
                score += 20
                flags.append(f"Low sentence variance ({variance:.1f}) — AI uniform rhythm")

        # Paragraph ending check (AI tends to round off every paragraph)
        paragraphs = [p for p in text.split("\n\n") if p.strip()]
        complete_endings = sum(1 for p in paragraphs if p.strip().endswith("."))
        if len(paragraphs) > 3 and complete_endings / len(paragraphs) > 0.85:
            score += 15
            flags.append(f"{complete_endings}/{len(paragraphs)} paragraphs end with period — too uniform")

        # AI vocabulary checks
        ai_vocab = ["tapestry", "navigate", "delve", "realm", "landscape", "myriad",
                    "profound", "furthermore", "moreover", "additionally", "subsequently"]
        found_ai_vocab = [w for w in ai_vocab if w.lower() in text.lower()]
        if found_ai_vocab:
            score += len(found_ai_vocab) * 5
            flags.append(f"AI vocabulary found: {found_ai_vocab}")

        # Triplet detection (A, B, and C patterns)
        triplet_pattern = r"\w+,\s+\w+,\s+and\s+\w+"
        triplets = re.findall(triplet_pattern, text, re.IGNORECASE)
        if len(triplets) > (word_count / 1000) * 2:
            score += 10
            flags.append(f"Excessive triplets: {len(triplets)} found")

        # Repeated sentence starters
        sentence_starts = [s.split()[0].lower() for s in sentences if s.split()]
        from collections import Counter
        starter_counts = Counter(sentence_starts)
        for starter, count in starter_counts.most_common(3):
            if count > 5 and starter in ["she", "he", "the", "it", "i"]:
                score += 10
                flags.append(f"Repeated sentence starter '{starter}': {count} times")

        return {
            "score": min(score, 100),
            "rating": "human-like" if score < 25 else "possibly AI" if score < 50 else "AI-detectable",
            "flags": flags,
            "word_count": word_count,
        }

    def humanize_manuscript(
        self,
        chapters: list[dict[str, Any]],
        output_dir: Path,
        novel_title: str,
    ) -> list[dict[str, Any]]:
        """
        Humanize all chapters in a manuscript.
        Returns list of humanized chapter dicts.
        """
        humanized: list[dict[str, Any]] = []
        title_slug = re.sub(r"[^a-z0-9]+", "_", novel_title.lower())
        output_file = output_dir / f"{title_slug}_humanized.txt"

        print(f"\n  [humanizer] Processing {len(chapters)} chapters...")

        for chapter_data in chapters:
            ch_num = chapter_data["chapter"]
            raw_text = chapter_data["text"]

            # Score before
            pre_score = self.score_ai_likelihood(raw_text)
            print(f"  [humanizer] Ch {ch_num} pre-score: {pre_score['score']}/100 ({pre_score['rating']})")

            humanized_text = self.humanize_chapter(raw_text, ch_num)

            # Score after
            post_score = self.score_ai_likelihood(humanized_text)
            print(f"  [humanizer] Ch {ch_num} post-score: {post_score['score']}/100 ({post_score['rating']})")

            humanized.append({
                **chapter_data,
                "text": humanized_text,
                "word_count": len(humanized_text.split()),
                "ai_score_pre": pre_score["score"],
                "ai_score_post": post_score["score"],
            })

        # Save humanized manuscript
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(f"{novel_title.upper()}\nA Novel\n\n{'─'*60}\n\n")
            for ch in humanized:
                f.write(f"\n{ch['title'].upper()}\n\n")
                f.write(ch["text"])
                f.write("\n\n" + "─" * 60 + "\n")

        total_words = sum(c["word_count"] for c in humanized)
        avg_ai_score_pre = sum(c["ai_score_pre"] for c in humanized) / len(humanized)
        avg_ai_score_post = sum(c["ai_score_post"] for c in humanized) / len(humanized)

        print(f"\n  [humanizer] Done!")
        print(f"  [humanizer] Total words: {total_words:,}")
        print(f"  [humanizer] Avg AI score: {avg_ai_score_pre:.1f} → {avg_ai_score_post:.1f}")
        print(f"  [humanizer] Humanized manuscript → {output_file}")

        return humanized


def humanize_manuscript(
    chapters: list[dict[str, Any]],
    output_dir: Path,
    novel_title: str,
) -> list[dict[str, Any]]:
    """Convenience entry point called by the orchestrator."""
    h = AntiAIHumanizer()
    return h.humanize_manuscript(chapters, output_dir, novel_title)


if __name__ == "__main__":
    # Test on a sample AI-style paragraph
    sample = """
Furthermore, the morning light filtered through the curtains in a tapestry of golden hues.
She navigated the complex landscape of her emotions as she sat at the kitchen table.
The coffee was hot. It was aromatic. It was comforting.
She thought about her past. She thought about her future. She thought about her present.
It is worth noting that this moment would prove significant in the days to come.
"""
    h = AntiAIHumanizer()
    pre = h.score_ai_likelihood(sample)
    print(f"Pre-humanization score: {pre}")
    result = apply_regex_fixes(sample)
    print("\nAfter regex pass:")
    print(result)
