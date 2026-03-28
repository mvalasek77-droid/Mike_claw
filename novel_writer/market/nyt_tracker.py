"""
Market Intelligence Module
- Fetches live NYT Bestseller lists (requires NYT_API_KEY)
- Falls back to curated trend knowledge when no API key is available
- Identifies what the market wants RIGHT NOW and surfaces actionable signals
  for the novel generator
"""

from __future__ import annotations
import json
import os
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
import urllib.request
import urllib.error

# ── Constants ─────────────────────────────────────────────────────────────────
NYT_API_KEY   = os.environ.get("NYT_API_KEY", "")
CACHE_DIR     = Path(__file__).parent / "cache"
CACHE_TTL_H   = 24
LIST_NAMES    = [
    "hardcover-fiction",
    "trade-fiction-paperback",
    "young-adult-hardcover",
    "audio-fiction",
]

# ── Hardcoded trend knowledge (always-on fallback / supplement) ───────────────
CURRENT_MARKET_INTELLIGENCE = {
    "as_of": "2026-Q1",
    "hottest_genres": [
        "romantasy",            # fantasy + romance hybrid, explosive growth
        "dark academia",        # gothic campus, intellectual obsession
        "cozy mystery",         # low-stakes, community-centered
        "literary thriller",    # psychological depth + propulsive plot
        "women's fiction upmarket",  # relationship + identity + place
        "climate fiction",      # ecological crisis as backdrop
        "historical fiction with modern resonance",
    ],
    "protagonist_trends": [
        "flawed female protagonist in her 30s-40s — not 'girlboss', authentically complex",
        "male protagonist showing emotional vulnerability without performative sensitivity",
        "outsider / immigrant perspective navigating American institutions",
        "neurodivergent protagonist whose difference is a superpower AND a limitation",
    ],
    "setting_trends": [
        "small-town / rural settings with hidden depth (Where the Crawdads effect)",
        "specific international settings with cultural specificity — not generic 'Europe'",
        "institutions: schools, hospitals, law firms, publishing houses",
        "nature as active antagonist or moral mirror",
    ],
    "plot_trends": [
        "domestic secrets + unreliable memory (domestic thriller baseline)",
        "multi-generational family reckoning",
        "morally gray choices with lasting consequences",
        "friendships as complex as romantic relationships",
        "community-level problems — not just individual arc",
    ],
    "theme_trends": [
        "grief and slow healing (not tidy resolution)",
        "who gets to tell which stories (meta-narrative)",
        "class anxiety in millennial/Gen-Z characters",
        "motherhood without sentimentality",
        "racial identity + code-switching exhaustion",
        "climate grief and eco-anxiety",
        "the internet and identity fracture",
    ],
    "prose_trends": [
        "intimate second person rare but effective",
        "short punchy chapters under 3,000 words drive book club engagement",
        "alternating timelines with a 'then' and 'now' structure",
        "epistolary elements woven in (texts, emails, diary) — feels contemporary",
        "autofiction-adjacent voice even in pure fiction",
    ],
    "what_book_clubs_want": [
        "moral ambiguity — readers should be able to disagree",
        "characters who feel like people you know",
        "questions with no easy answers",
        "cultural specificity that teaches without being a lecture",
        "an ending that provokes discussion rather than closes debate",
        "emotional intensity without wallowing — cathartic not exploitative",
    ],
    "what_agents_want": [
        "strong first page that establishes voice immediately",
        "a plot that can be described in one sentence",
        "identifiable comp titles from the last 3 years",
        "a protagonist with a specific, urgent need and a concrete obstacle",
        "10% in: the inciting incident must have occurred",
    ],
    "avoid_now": [
        "chosen-one narratives without subverting the trope",
        "love triangles as primary tension",
        "villain with a 'tragic backstory' that excuses everything",
        "twist endings that depend on information withheld from the reader unfairly",
        "contemporary satire that will date in 18 months",
        "overly explained metaphors",
        "passive protagonist who things happen TO for more than one act",
    ],
}

# ── NYT API client ─────────────────────────────────────────────────────────────

class NYTBestsellerClient:
    BASE_URL = "https://api.nytimes.com/svc/books/v3/lists/current/{list_name}.json"

    def __init__(self, api_key: str = NYT_API_KEY):
        self.api_key = api_key
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

    def _cache_path(self, list_name: str) -> Path:
        return CACHE_DIR / f"{list_name}.json"

    def _is_cache_fresh(self, list_name: str) -> bool:
        p = self._cache_path(list_name)
        if not p.exists():
            return False
        age = datetime.now() - datetime.fromtimestamp(p.stat().st_mtime)
        return age < timedelta(hours=CACHE_TTL_H)

    def fetch(self, list_name: str) -> dict[str, Any] | None:
        if self._is_cache_fresh(list_name):
            with open(self._cache_path(list_name)) as f:
                return json.load(f)

        if not self.api_key:
            print(f"  [market] No NYT_API_KEY — using curated intelligence only.")
            return None

        url = self.BASE_URL.format(list_name=list_name) + f"?api-key={self.api_key}"
        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                data = json.loads(resp.read().decode())
            with open(self._cache_path(list_name), "w") as f:
                json.dump(data, f, indent=2)
            print(f"  [market] Fetched {list_name} from NYT API")
            return data
        except urllib.error.URLError as e:
            print(f"  [market] NYT fetch error ({list_name}): {e}")
            return None

    def fetch_all(self) -> list[dict[str, Any]]:
        results = []
        for name in LIST_NAMES:
            data = self.fetch(name)
            if data:
                results.append(data)
            time.sleep(0.5)   # rate limit courtesy
        return results


# ── Market signal extractor ───────────────────────────────────────────────────

class MarketAnalyzer:
    """
    Combines live NYT data (if available) with curated intelligence to produce
    a prioritized list of market signals the novel should incorporate.
    """

    def __init__(self):
        self.client = NYTBestsellerClient()
        self.live_data: list[dict] = []

    def refresh(self) -> None:
        self.live_data = self.client.fetch_all()

    def _extract_live_signals(self) -> dict[str, list[str]]:
        """Pull genre/theme/format signals from live NYT data."""
        if not self.live_data:
            return {}

        signals: dict[str, list[str]] = defaultdict(list)
        for dataset in self.live_data:
            books = dataset.get("results", {}).get("books", [])
            for book in books:
                desc = book.get("description", "").lower()
                title = book.get("title", "")
                # Simple keyword extraction from descriptions
                for keyword in ["grief", "secrets", "family", "thriller", "romance",
                                 "mystery", "identity", "survival", "war", "love",
                                 "redemption", "dark", "historical", "magic", "fantasy"]:
                    if keyword in desc:
                        signals["live_themes"].append(keyword)
                signals["live_titles"].append(title)

        # Deduplicate and count
        theme_counts = Counter(signals.get("live_themes", []))
        signals["top_live_themes"] = [t for t, _ in theme_counts.most_common(8)]
        return dict(signals)

    def get_market_signals(self) -> dict[str, Any]:
        """Return a combined market intelligence dict for the synthesizer."""
        live = self._extract_live_signals()

        signals = {
            **CURRENT_MARKET_INTELLIGENCE,
            "live_nyt_themes": live.get("top_live_themes", []),
            "live_nyt_titles_on_list": live.get("live_titles", [])[:15],
            "generated_at": datetime.now().isoformat(),
        }

        # Merge live themes into hottest_genres if they confirm a trend
        if "romance" in live.get("top_live_themes", []) and "romantasy" not in signals["hottest_genres"]:
            signals["hottest_genres"].insert(0, "romantasy (live confirmation)")

        return signals

    def synthesize_genre_recommendation(self, author_preference: str | None = None) -> dict[str, str]:
        """
        Given current market conditions, recommend the single best genre strategy
        for a new novel aiming at both literary quality and commercial success.
        """
        return {
            "primary_genre": "Upmarket Women's Fiction / Literary Thriller",
            "tone": "emotionally immersive, intelligent, propulsive",
            "setting_recommendation": "Small American town with secrets / or international with deep specificity",
            "protagonist_recommendation": "Woman in her late 30s, professional expertise, unresolved wound from the past",
            "market_rationale": (
                "Book club appeal drives sustained sales. Literary thrillers with emotional depth "
                "hit #1 consistently (Where the Crawdads Sing, Big Little Lies, The Girl on the Train). "
                "Female protagonist with professional credibility + personal crisis is the top-selling archetype. "
                "Small-town setting allows nature as mirror + hidden-community-secret plot engine."
            ),
            "comp_titles": [
                "Where the Crawdads Sing — Delia Owens (2018)",
                "Olive Kitteridge — Elizabeth Strout (2008, Pulitzer)",
                "Big Little Lies — Liane Moriarty (2014)",
                "The Midnight Library — Matt Haig (2020)",
                "Demon Copperhead — Barbara Kingsolver (2022, Pulitzer)",
            ],
        }


def get_market_signals() -> dict[str, Any]:
    """Convenience function called by the orchestrator."""
    analyzer = MarketAnalyzer()
    analyzer.refresh()
    return analyzer.get_market_signals()


def get_genre_recommendation() -> dict[str, str]:
    """Convenience function called by the orchestrator."""
    analyzer = MarketAnalyzer()
    return analyzer.synthesize_genre_recommendation()


if __name__ == "__main__":
    signals = get_market_signals()
    print("\n=== MARKET INTELLIGENCE ===")
    print(f"As of: {signals['as_of']}")
    print(f"Hottest genres: {signals['hottest_genres'][:4]}")
    print(f"What book clubs want: {signals['what_book_clubs_want'][:3]}")
    print(f"What agents want: {signals['what_agents_want'][:3]}")
    print(f"Avoid: {signals['avoid_now'][:3]}")
