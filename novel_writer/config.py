"""
MikeClaw Novel Writer - Master Configuration
Distills 100 greatest novels + 100 bestsellers + 40 Pulitzer winners
into a publisher-ready 70k+ word manuscript.
"""

import os
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent
CORPUS_DIR = BASE_DIR / "corpus"
ANALYSIS_DIR = BASE_DIR / "analysis"
MARKET_DIR = BASE_DIR / "market"
SYNTHESIS_DIR = BASE_DIR / "synthesis"
GENERATION_DIR = BASE_DIR / "generation"
HUMANIZER_DIR = BASE_DIR / "humanizer"
OUTPUT_DIR = BASE_DIR / "output"
UTILS_DIR = BASE_DIR / "utils"

# ── Claude API ─────────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
CLAUDE_MODEL = "claude-opus-4-6"                # Most capable for long-form prose
CLAUDE_HAIKU  = "claude-haiku-4-5-20251001"     # Fast passes (humanizer, analysis)

# ── Generation Targets ─────────────────────────────────────────────────────────
MIN_WORD_COUNT        = 70_000
TARGET_WORD_COUNT     = 85_000
CHAPTER_TARGET_WORDS  = 3_000   # ~3k words per chapter → ~25-28 chapters
MAX_CHAPTERS          = 30

# ── Corpus Sizes ──────────────────────────────────────────────────────────────
GREATEST_NOVELS_COUNT  = 100
BESTSELLER_COUNT       = 100
PULITZER_COUNT         = 40     # last 40 Pulitzer Prize winners (Fiction)

# ── Market Feed ───────────────────────────────────────────────────────────────
NYT_BESTSELLER_URL     = "https://api.nytimes.com/svc/books/v3/lists/current/hardcover-fiction.json"
NYT_API_KEY            = os.environ.get("NYT_API_KEY", "")
MARKET_REFRESH_HOURS   = 24

# ── Anti-AI Detection ─────────────────────────────────────────────────────────
HUMANIZER_PASSES       = 3      # rewrite passes through humanizer
PERPLEXITY_TARGET      = 85     # target Flesch-Kincaid-style complexity score
BURSTINESS_TARGET      = 0.72   # sentence length variance (human writing ≈ 0.7-0.8)

# ── Output ────────────────────────────────────────────────────────────────────
OUTPUT_FORMATS         = ["docx", "pdf", "txt", "md"]
MANUSCRIPT_FONT        = "Times New Roman"
MANUSCRIPT_FONT_SIZE   = 12
MANUSCRIPT_LINE_SPACE  = 2.0    # double-spaced (publisher standard)
