"""Versioned, remotely-updatable threat definitions.

The threat landscape moves faster than app releases: new chat apps become
grooming funnels, new slang evades yesterday's regexes, condo games respawn
under new place ids. Everything the detector matches against therefore lives
in a versioned feed document rather than in code:

  * ships with a bundled seed (data/threat_feed.json) so the app works offline
  * optionally refreshes from an operator-controlled URL (RG_FEED_URL) on a
    TTL, so new threat patterns deploy to every install within hours
  * merges the experience watchlist, so condo-game intel arrives the same way

A malformed or unreachable remote feed can never break detection: the last
good feed stays active, and the bundled seed is the floor.
"""

import json
import logging
import os
import re
import time
from dataclasses import dataclass, field
from typing import Optional

import httpx

log = logging.getLogger("roblox_guard.threat_feed")

SEED_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "threat_feed.json")

# Obfuscation normalization: predators write "d1sc0rd" and "sn@p" to slip past
# keyword filters. We fold common substitutions before matching, and matching
# only on the normalized form of a term that required folding is itself
# meaningful — deliberate evasion demonstrates intent.
LEET_MAP = str.maketrans({
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
    "@": "a", "$": "s", "!": "i", "|": "l",
})


def normalize_text(text: str) -> str:
    return (text or "").lower().translate(LEET_MAP)


@dataclass
class ThreatFeed:
    version: int
    updated_at: str
    # platform label -> regex applied to raw AND normalized text
    off_platform_patterns: list[dict] = field(default_factory=list)
    # bio phrases that warrant a watch signal on their own (kept factual)
    grooming_phrases: list[str] = field(default_factory=list)
    # thresholds the signal engine consults (falls back to Settings defaults)
    thresholds: dict = field(default_factory=dict)
    # condo/experience watchlist entries, same schema as the local watchlist
    watchlist: list[dict] = field(default_factory=list)
    # Content updates ride the same versioned feed, so parent-facing language
    # stays current without app releases:
    # glossary entries: {term, aliases: [...], definition} — add or override
    glossary: list[dict] = field(default_factory=list)
    # Roblox-101 entries: {id, question, answer} — add or override by id
    roblox_basics: list[dict] = field(default_factory=list)

    _compiled: list[tuple[str, re.Pattern]] = field(default_factory=list, repr=False)
    _compiled_phrases: list[tuple[str, re.Pattern]] = field(default_factory=list, repr=False)

    def compile(self) -> "ThreatFeed":
        self._compiled = []
        for entry in self.off_platform_patterns:
            try:
                self._compiled.append(
                    (entry["platform"], re.compile(entry["pattern"], re.I)))
            except (KeyError, re.error) as error:
                log.warning("skipping bad feed pattern %r: %s", entry, error)
        self._compiled_phrases = []
        for phrase in self.grooming_phrases:
            # match the phrase with arbitrary separators between words
            words = [re.escape(w) for w in phrase.lower().split()]
            if words:
                self._compiled_phrases.append(
                    (phrase, re.compile(r"[\s._-]*".join(words), re.I)))
        return self

    # -- matching ------------------------------------------------------------

    def match_off_platform(self, text: str) -> list[dict]:
        """Return [{platform, obfuscated}] found in text (raw or de-leeted)."""
        raw = text or ""
        normalized = normalize_text(raw)
        found: dict[str, bool] = {}
        for platform, pattern in self._compiled:
            if pattern.search(raw):
                found.setdefault(platform, False)
            elif normalized != raw.lower() and pattern.search(normalized):
                # only matched after de-leeting -> deliberate obfuscation
                found[platform] = True
        return [{"platform": p, "obfuscated": o} for p, o in found.items()]

    def match_grooming_phrases(self, text: str) -> list[str]:
        normalized = normalize_text(text)
        return [phrase for phrase, pattern in self._compiled_phrases
                if pattern.search(normalized)]

    def watchlist_by_place(self) -> dict[int, dict]:
        out = {}
        for entry in self.watchlist:
            try:
                out[int(entry["place_id"])] = entry
            except (KeyError, TypeError, ValueError):
                continue
        return out


def _parse(data: dict) -> ThreatFeed:
    return ThreatFeed(
        version=int(data.get("version", 0)),
        updated_at=str(data.get("updated_at", "")),
        off_platform_patterns=list(data.get("off_platform_patterns", [])),
        grooming_phrases=list(data.get("grooming_phrases", [])),
        thresholds=dict(data.get("thresholds", {})),
        watchlist=list(data.get("watchlist", [])),
        glossary=list(data.get("glossary", [])),
        roblox_basics=list(data.get("roblox_basics", [])),
    ).compile()


class FeedManager:
    """Holds the active feed; refreshes from RG_FEED_URL on a TTL."""

    def __init__(self, seed_path: str = SEED_PATH,
                 remote_url: Optional[str] = None,
                 refresh_ttl_seconds: int = 6 * 3600):
        self.remote_url = remote_url if remote_url is not None \
            else os.environ.get("RG_FEED_URL") or None
        self.refresh_ttl = refresh_ttl_seconds
        self._last_refresh: Optional[float] = None  # monotonic; None = never
        self.source = "seed"
        with open(seed_path) as f:
            self.feed = _parse(json.load(f))

    async def maybe_refresh(self) -> bool:
        """Refresh from the remote URL if configured and TTL expired.
        Returns True if a newer feed was applied."""
        if not self.remote_url:
            return False
        now = time.monotonic()
        if self._last_refresh is not None and now - self._last_refresh < self.refresh_ttl:
            return False
        self._last_refresh = now
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.get(self.remote_url)
                resp.raise_for_status()
                candidate = _parse(resp.json())
        except Exception:
            log.exception("threat feed refresh failed; keeping feed v%s",
                          self.feed.version)
            return False
        if candidate.version <= self.feed.version:
            return False
        log.info("threat feed updated v%s -> v%s", self.feed.version, candidate.version)
        self.feed = candidate
        self.source = "remote"
        return True

    def status(self) -> dict:
        return {
            "version": self.feed.version,
            "updated_at": self.feed.updated_at,
            "source": self.source,
            "remote_url_configured": bool(self.remote_url),
            "pattern_count": len(self.feed._compiled),
            "phrase_count": len(self.feed._compiled_phrases),
            "watchlist_count": len(self.feed.watchlist),
            "glossary_override_count": len(self.feed.glossary),
            "basics_override_count": len(self.feed.roblox_basics),
        }
