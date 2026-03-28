"""
MikeClaw Novel Writer — Master Orchestrator
Runs the full pipeline:
  1. Literary analysis (100 greatest + 40 Pulitzer winners)
  2. Market intelligence (100 bestsellers + live NYT feed)
  3. Synthesis → novel plan (characters, outlines, arc)
  4. Generation → 70k+ word draft (chapter by chapter)
  5. Humanization → 3-pass anti-AI-detection rewrite
  6. Publisher formatting → .docx / .txt / .md + submission package

Usage:
  python orchestrator.py                         # full pipeline
  python orchestrator.py --stage plan            # stop after synthesis
  python orchestrator.py --stage generate        # stop after generation
  python orchestrator.py --stage humanize        # stop after humanization
  python orchestrator.py --resume                # resume interrupted generation
  python orchestrator.py --plan path/to/plan.json  # use existing plan
"""

from __future__ import annotations
import argparse
import json
import os
import sys
import time
from pathlib import Path

BASE_DIR = Path(__file__).parent

# Add novel_writer to path
sys.path.insert(0, str(BASE_DIR))

from config import (
    ANTHROPIC_API_KEY, TARGET_WORD_COUNT, MIN_WORD_COUNT,
)

SYNTHESIS_DIR  = BASE_DIR / "synthesis"
GENERATION_DIR = BASE_DIR / "generation" / "drafts"
HUMANIZER_DIR  = BASE_DIR / "humanizer"
OUTPUT_DIR     = BASE_DIR / "output" / "final"


def check_api_key() -> bool:
    if not ANTHROPIC_API_KEY:
        print("\n  ERROR: ANTHROPIC_API_KEY environment variable not set.")
        print("  Set it with: export ANTHROPIC_API_KEY='your-key-here'")
        return False
    return True


def banner() -> None:
    print("""
╔══════════════════════════════════════════════════════════════════╗
║             MIKECLAW AI NOVEL WRITER  v1.0                      ║
║  Distills 100 greatest + 100 bestsellers + 40 Pulitzer winners  ║
║  into a publisher-ready 70,000+ word manuscript                 ║
╚══════════════════════════════════════════════════════════════════╝
""")


def stage_analyze() -> None:
    """Run the literary + market analysis (no API needed)."""
    print("\n[1/5] LITERARY & MARKET ANALYSIS")
    print("  Distilling 240 novels across three corpora...")

    from analysis.literary_analyzer import build_writing_blueprint, save_blueprint
    from market.nyt_tracker import get_market_signals, get_genre_recommendation

    bp = build_writing_blueprint()
    print(f"  ✓ Blueprint built: {len(bp.theme_profile.intersection)} cross-corpus themes")
    print(f"  ✓ Structure: {bp.structure.archetype}")
    print(f"  ✓ Commercial hooks: {bp.commercial_hooks[:3]}")

    signals = get_market_signals()
    print(f"  ✓ Market signals: {signals['hottest_genres'][:3]}")

    rec = get_genre_recommendation()
    print(f"  ✓ Genre recommendation: {rec['primary_genre']}")


def stage_synthesize(plan_output_path: Path) -> dict:
    """Run Claude synthesis to produce the full novel plan."""
    print("\n[2/5] NOVEL SYNTHESIS (Claude)")
    print("  Building characters, chapter outlines, thematic scaffolding...")

    from synthesis.model_synthesizer import build_novel_plan

    plan = build_novel_plan(save_path=str(plan_output_path))

    title = plan.get("title", "Untitled")
    chapters = len(plan.get("chapter_outlines", []))
    print(f"\n  ✓ Novel plan synthesized!")
    print(f"  ✓ Title: {title}")
    print(f"  ✓ Logline: {plan.get('logline', '')}")
    print(f"  ✓ Genre: {plan.get('genre', '')}")
    print(f"  ✓ Setting: {plan.get('setting', '')}")
    print(f"  ✓ Characters: {len(plan.get('characters', []))}")
    print(f"  ✓ Chapter outlines: {chapters}")
    print(f"  ✓ Saved → {plan_output_path}")

    return plan


def stage_generate(plan: dict, output_dir: Path) -> dict:
    """Run the chapter-by-chapter generation engine."""
    print(f"\n[3/5] NOVEL GENERATION (Claude)")
    print(f"  Target: {TARGET_WORD_COUNT:,} words | {len(plan.get('chapter_outlines', []))} chapters")
    print(f"  (Generation is resumable — safe to interrupt with Ctrl+C)")

    from generation.novel_generator import generate_novel

    result = generate_novel(plan, output_dir=output_dir)

    print(f"\n  ✓ Draft complete: {result['total_words']:,} words")
    print(f"  ✓ Manuscript → {result['manuscript_file']}")

    if result["total_words"] < MIN_WORD_COUNT:
        deficit = MIN_WORD_COUNT - result["total_words"]
        print(f"\n  WARNING: {deficit:,} words short of minimum target.")
        print(f"  Consider adding 1-2 chapters or expanding thin chapters.")

    return result


def stage_humanize(draft_file: Path, output_dir: Path) -> list[dict]:
    """Run the 3-pass anti-AI humanization."""
    print("\n[4/5] HUMANIZATION (3-pass anti-AI rewrite)")

    if not draft_file.exists():
        print(f"  ERROR: Draft file not found: {draft_file}")
        return []

    with open(draft_file) as f:
        draft_data = json.load(f)

    chapters = draft_data.get("chapters", [])
    title = draft_data.get("plan_title", "Untitled")

    print(f"  Processing {len(chapters)} chapters...")

    from humanizer.anti_ai_humanizer import humanize_manuscript

    humanized = humanize_manuscript(chapters, output_dir, title)

    avg_pre  = sum(c.get("ai_score_pre", 0) for c in humanized) / len(humanized)
    avg_post = sum(c.get("ai_score_post", 0) for c in humanized) / len(humanized)
    improvement = avg_pre - avg_post

    print(f"\n  ✓ Humanization complete!")
    print(f"  ✓ AI detectability: {avg_pre:.1f} → {avg_post:.1f} (−{improvement:.1f} points)")

    return humanized


def stage_format(
    chapters: list[dict],
    plan: dict,
    output_dir: Path,
) -> dict[str, str]:
    """Run the publisher-ready formatter."""
    print("\n[5/5] PUBLISHER FORMATTING")

    from output.publisher_formatter import format_manuscript

    outputs = format_manuscript(chapters, plan, output_dir)

    total_words = sum(c.get("word_count", 0) for c in chapters)
    print(f"\n  ✓ Publisher-ready files:")
    for fmt, path in outputs.items():
        print(f"     {fmt.upper()}: {path}")
    print(f"\n  ✓ {total_words:,} words | Publisher-ready manuscript complete")

    return outputs


# ── Main pipeline ─────────────────────────────────────────────────────────────

def run_pipeline(args: argparse.Namespace) -> None:
    banner()

    if not check_api_key():
        sys.exit(1)

    SYNTHESIS_DIR.mkdir(parents=True, exist_ok=True)
    GENERATION_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    plan_path = SYNTHESIS_DIR / "novel_plan.json"
    stop_stage = args.stage  # None = run all

    # ── Stage 1: Analysis (always runs, fast, no API) ─────────────────────────
    stage_analyze()
    if stop_stage == "analyze":
        print("\n  Stopped after analysis stage.")
        return

    # ── Stage 2: Synthesis ────────────────────────────────────────────────────
    if args.plan:
        plan_path = Path(args.plan)
        if not plan_path.exists():
            print(f"  ERROR: Plan file not found: {args.plan}")
            sys.exit(1)
        with open(plan_path) as f:
            plan = json.load(f)
        print(f"\n[2/5] Using existing plan: {plan_path}")
        print(f"  ✓ Title: {plan.get('title', 'Untitled')}")
    elif plan_path.exists() and not args.resynthesize:
        with open(plan_path) as f:
            plan = json.load(f)
        print(f"\n[2/5] Using cached plan: {plan_path}")
        print(f"  ✓ Title: {plan.get('title', 'Untitled')}")
        print(f"  ✓ Chapters: {len(plan.get('chapter_outlines', []))}")
        print(f"  (Use --resynthesize to regenerate the plan)")
    else:
        plan = stage_synthesize(plan_path)

    if stop_stage == "plan":
        print(f"\n  Novel plan saved → {plan_path}")
        print(f"  To continue: python orchestrator.py --plan {plan_path}")
        return

    # ── Stage 3: Generation ───────────────────────────────────────────────────
    title_slug = __import__("re").sub(
        r"[^a-z0-9]+", "_", plan.get("title", "untitled").lower()
    )
    draft_file = GENERATION_DIR / f"{title_slug}_draft.json"

    result = stage_generate(plan, GENERATION_DIR)
    draft_file = Path(result.get("draft_file", str(draft_file)))

    if stop_stage == "generate":
        print(f"\n  Draft saved → {draft_file}")
        print(f"  To continue: python orchestrator.py --plan {plan_path}")
        return

    # ── Stage 4: Humanization ─────────────────────────────────────────────────
    humanized_chapters = stage_humanize(draft_file, OUTPUT_DIR)

    if not humanized_chapters:
        print("  ERROR: Humanization produced no output. Check logs above.")
        sys.exit(1)

    if stop_stage == "humanize":
        return

    # ── Stage 5: Publisher formatting ─────────────────────────────────────────
    outputs = stage_format(humanized_chapters, plan, OUTPUT_DIR)

    # ── Final report ──────────────────────────────────────────────────────────
    total_words = sum(c.get("word_count", 0) for c in humanized_chapters)

    print(f"""
╔══════════════════════════════════════════════════════════════════╗
║                    PIPELINE COMPLETE                            ║
╚══════════════════════════════════════════════════════════════════╝

  Title:       {plan.get('title', 'Untitled')}
  Logline:     {plan.get('logline', '')[:70]}...
  Genre:       {plan.get('genre', '')}
  Word count:  {total_words:,}
  Chapters:    {len(humanized_chapters)}

  Output files:
  {''.join(f"  {fmt.upper():8s} → {path}{chr(10)}" for fmt, path in outputs.items())}
  Comparable titles:
{''.join(f"  • {ct}{chr(10)}" for ct in plan.get('comparable_titles', [])[:3])}
""")


# ── CLI ───────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="MikeClaw AI Novel Writer — publisher-ready 70k+ word manuscript",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--stage",
        choices=["analyze", "plan", "generate", "humanize"],
        default=None,
        help="Stop after this stage (default: run full pipeline)",
    )
    parser.add_argument(
        "--plan",
        type=str,
        default=None,
        metavar="PATH",
        help="Path to existing novel_plan.json (skip synthesis)",
    )
    parser.add_argument(
        "--resynthesize",
        action="store_true",
        help="Force re-synthesis even if novel_plan.json exists",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume interrupted generation from last saved chapter",
    )

    args = parser.parse_args()

    try:
        run_pipeline(args)
    except KeyboardInterrupt:
        print("\n\n  Interrupted. Progress has been saved — run again with the same command to resume.")
        sys.exit(0)


if __name__ == "__main__":
    main()
