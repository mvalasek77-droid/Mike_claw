"""Daily threat-intelligence pipeline.

Once a day the backend searches configured sources (child-safety news feeds,
platform-safety blogs, advisories) for new Roblox-relevant threats and turns
what it finds into a *proposed* threat-feed update:

    sources (RSS) -> findings -> analyzer -> validated proposal -> operator
                                                    |                review
                                                    +--> optional auto-apply
                                                         (additive only)

Two analyzers:

  ClaudeThreatAnalyzer  Uses the Claude API (claude-opus-4-8) to read the
                        findings and extract candidate additions: new
                        off-platform apps + regex patterns, grooming phrases,
                        watchlist entries, and glossary terms. Active when the
                        `anthropic` package and an API key are available.
  KeywordAnalyzer       No-LLM fallback: surfaces relevant findings for the
                        operator to review by hand; proposes nothing itself.

Safety valves, regardless of analyzer:
  * proposals are ADDITIVE only — nothing is ever removed automatically
  * every proposed regex must compile; bad ones are dropped
  * proposed text is wording-checked (no person-labeling)
  * hard caps per run so a poisoned source can't flood the feed
  * auto-apply is off by default (RG_INTEL_AUTOAPPLY=1 to enable); otherwise
    the proposal is stored for operator review and manual publication
"""

import asyncio
import json
import logging
import os
import re
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Optional

import httpx

from .signals import FORBIDDEN_LABELS

log = logging.getLogger("roblox_guard.intel")

DEFAULT_SOURCES_PATH = os.path.join(os.path.dirname(__file__), "..", "data", "intel_sources.json")
MAX_FINDINGS_PER_SOURCE = 25
MAX_NEW_PATTERNS = 5
MAX_NEW_PHRASES = 10
MAX_NEW_WATCHLIST = 10
MAX_NEW_GLOSSARY = 10

RELEVANCE_KEYWORDS = (
    "roblox", "grooming", "sextortion", "predator", "child safety", "csam",
    "minor", "exploitation", "condo game", "discord", "online safety",
)


@dataclass
class Finding:
    source: str
    title: str
    url: str
    summary: str = ""
    published: str = ""


def load_sources(path: str = DEFAULT_SOURCES_PATH) -> list[dict]:
    env = os.environ.get("RG_INTEL_SOURCES")
    if env:
        try:
            return list(json.loads(env))
        except json.JSONDecodeError:
            log.error("RG_INTEL_SOURCES is not valid JSON; ignoring")
    if os.path.exists(path):
        with open(path) as f:
            return list(json.load(f).get("sources", []))
    return []


async def fetch_rss(url: str, http: httpx.AsyncClient) -> list[Finding]:
    """Minimal RSS/Atom reader — titles, links, and summaries only."""
    resp = await http.get(url)
    resp.raise_for_status()
    root = ET.fromstring(resp.text)
    ns = {"atom": "http://www.w3.org/2005/Atom"}
    findings: list[Finding] = []

    for item in root.iter("item"):  # RSS 2.0
        findings.append(Finding(
            source=url,
            title=(item.findtext("title") or "").strip(),
            url=(item.findtext("link") or "").strip(),
            summary=re.sub(r"<[^>]+>", " ", item.findtext("description") or "").strip()[:1000],
            published=(item.findtext("pubDate") or "").strip(),
        ))
    if not findings:  # Atom
        for entry in root.iter("{http://www.w3.org/2005/Atom}entry"):
            link = entry.find("atom:link", ns)
            findings.append(Finding(
                source=url,
                title=(entry.findtext("atom:title", namespaces=ns) or "").strip(),
                url=(link.get("href") if link is not None else "") or "",
                summary=re.sub(r"<[^>]+>", " ",
                               entry.findtext("atom:summary", namespaces=ns) or "").strip()[:1000],
                published=(entry.findtext("atom:updated", namespaces=ns) or "").strip(),
            ))
    return findings[:MAX_FINDINGS_PER_SOURCE]


def relevant(finding: Finding) -> bool:
    text = f"{finding.title} {finding.summary}".lower()
    return any(k in text for k in RELEVANCE_KEYWORDS)


# --------------------------------------------------------------------------
# Analyzers
# --------------------------------------------------------------------------

PROPOSAL_SCHEMA = {
    "type": "object",
    "properties": {
        "off_platform_patterns": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "platform": {"type": "string"},
                    "pattern": {"type": "string"},
                    "rationale": {"type": "string"},
                    "source_url": {"type": "string"},
                },
                "required": ["platform", "pattern", "rationale", "source_url"],
                "additionalProperties": False,
            },
        },
        "grooming_phrases": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "phrase": {"type": "string"},
                    "rationale": {"type": "string"},
                    "source_url": {"type": "string"},
                },
                "required": ["phrase", "rationale", "source_url"],
                "additionalProperties": False,
            },
        },
        "watchlist": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "place_id": {"type": "integer"},
                    "name": {"type": "string"},
                    "reason": {"type": "string"},
                    "source_url": {"type": "string"},
                },
                "required": ["place_id", "name", "reason", "source_url"],
                "additionalProperties": False,
            },
        },
        "glossary": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "term": {"type": "string"},
                    "aliases": {"type": "array", "items": {"type": "string"}},
                    "definition": {"type": "string"},
                    "source_url": {"type": "string"},
                },
                "required": ["term", "aliases", "definition", "source_url"],
                "additionalProperties": False,
            },
        },
        "summary": {"type": "string"},
    },
    "required": ["off_platform_patterns", "grooming_phrases", "watchlist",
                 "glossary", "summary"],
    "additionalProperties": False,
}

ANALYZER_SYSTEM = """\
You maintain the threat-definition feed for a parental-safety app that watches
children's PUBLIC Roblox footprints. From the news findings provided, extract
ONLY concrete, actionable additions:

- off_platform_patterns: NEW apps/platforms predators use to move children's
  chats off Roblox, with a case-insensitive Python regex that matches a handle
  being advertised (e.g. "newapp\\s*[:@-]\\s*[\\w.]{2,}"). Skip platforms the
  feed obviously already covers (Discord, Snapchat, Telegram, Kik, WhatsApp,
  Instagram, Signal, phone numbers).
- grooming_phrases: NEW short text phrases used in profiles/bios to initiate
  private, secret, or image-based contact with children.
- watchlist: Roblox experiences (with a specific numeric place id ONLY if the
  source states one) identified as venues for adult content or predatory
  contact. Never guess place ids.
- glossary: NEW terms parents will encounter (new app names, new slang) with a
  plain-language definition for a reader who knows nothing about Roblox.

Rules: propose nothing you cannot tie to a provided source_url; describe
behavior and platforms, never label or accuse any individual person; when in
doubt, propose nothing — an empty proposal is a good outcome. Write `summary`
as 2-3 sentences for the operator reviewing this proposal."""


class KeywordAnalyzer:
    """No-LLM fallback: flags relevant findings, proposes no changes."""

    name = "keyword"

    async def analyze(self, findings: list[Finding]) -> dict:
        flagged = [asdict(f) for f in findings if relevant(f)]
        return {
            "off_platform_patterns": [], "grooming_phrases": [],
            "watchlist": [], "glossary": [],
            "summary": (f"{len(flagged)} relevant finding(s) collected for manual "
                        "review. Automatic extraction requires the Claude analyzer "
                        "(set RG_ANTHROPIC_API_KEY)."),
            "flagged_findings": flagged,
        }


class ClaudeThreatAnalyzer:
    """Extracts proposed feed additions from findings with the Claude API."""

    name = "claude"
    MODEL = "claude-opus-4-8"

    def __init__(self, client=None):
        if client is not None:
            self._client = client
        else:
            import anthropic
            self._client = anthropic.AsyncAnthropic(
                api_key=os.environ.get("RG_ANTHROPIC_API_KEY") or None)

    @staticmethod
    def available() -> bool:
        try:
            import anthropic  # noqa: F401
        except ImportError:
            return False
        return bool(os.environ.get("RG_ANTHROPIC_API_KEY")
                    or os.environ.get("ANTHROPIC_API_KEY"))

    async def analyze(self, findings: list[Finding]) -> dict:
        relevant_findings = [f for f in findings if relevant(f)] or findings
        digest = "\n\n".join(
            f"SOURCE: {f.url}\nTITLE: {f.title}\nPUBLISHED: {f.published}\n{f.summary}"
            for f in relevant_findings[:40]
        )
        response = await self._client.messages.create(
            model=self.MODEL,
            max_tokens=16000,
            thinking={"type": "adaptive"},
            system=ANALYZER_SYSTEM,
            output_config={"format": {"type": "json_schema", "schema": PROPOSAL_SCHEMA}},
            messages=[{"role": "user", "content": f"Today's findings:\n\n{digest}"}],
        )
        if response.stop_reason == "refusal":
            log.warning("analyzer request refused; returning empty proposal")
            return {"off_platform_patterns": [], "grooming_phrases": [],
                    "watchlist": [], "glossary": [],
                    "summary": "Analyzer declined this batch; no proposal."}
        text = next(b.text for b in response.content if b.type == "text")
        return json.loads(text)


# --------------------------------------------------------------------------
# Validation + merge
# --------------------------------------------------------------------------

def _label_free(*texts: str) -> bool:
    combined = " ".join(t or "" for t in texts).lower()
    return not any(re.search(rf"(?<![a-z]){re.escape(label)}(?![a-z])", combined)
                   for label in FORBIDDEN_LABELS)


def validate_proposal(raw: dict, current_feed) -> dict:
    """Enforce the safety valves on an analyzer proposal."""
    existing_platforms = {p["platform"].lower() for p in current_feed.off_platform_patterns}
    existing_phrases = {p.lower() for p in current_feed.grooming_phrases}
    existing_places = set(current_feed.watchlist_by_place())

    out = {"off_platform_patterns": [], "grooming_phrases": [], "watchlist": [],
           "glossary": [], "summary": str(raw.get("summary", ""))[:2000]}

    for entry in raw.get("off_platform_patterns", [])[:MAX_NEW_PATTERNS * 2]:
        platform, pattern = entry.get("platform", ""), entry.get("pattern", "")
        if not platform or platform.lower() in existing_platforms:
            continue
        try:
            re.compile(pattern, re.I)
        except re.error:
            log.warning("dropping proposal with bad regex: %r", pattern)
            continue
        if _label_free(platform, entry.get("rationale", "")):
            out["off_platform_patterns"].append(entry)
        if len(out["off_platform_patterns"]) >= MAX_NEW_PATTERNS:
            break

    for entry in raw.get("grooming_phrases", [])[:MAX_NEW_PHRASES * 2]:
        phrase = (entry.get("phrase") or "").strip()
        if 2 <= len(phrase) <= 60 and phrase.lower() not in existing_phrases:
            out["grooming_phrases"].append(entry)
        if len(out["grooming_phrases"]) >= MAX_NEW_PHRASES:
            break

    for entry in raw.get("watchlist", [])[:MAX_NEW_WATCHLIST * 2]:
        try:
            place_id = int(entry.get("place_id"))
        except (TypeError, ValueError):
            continue
        if place_id > 0 and place_id not in existing_places \
                and _label_free(entry.get("name", ""), entry.get("reason", "")):
            out["watchlist"].append(entry)
        if len(out["watchlist"]) >= MAX_NEW_WATCHLIST:
            break

    for entry in raw.get("glossary", [])[:MAX_NEW_GLOSSARY * 2]:
        if entry.get("term") and entry.get("definition") \
                and _label_free(entry["term"], entry["definition"]):
            out["glossary"].append(entry)
        if len(out["glossary"]) >= MAX_NEW_GLOSSARY:
            break
    return out


def proposal_is_empty(proposal: dict) -> bool:
    return not any(proposal.get(k) for k in
                   ("off_platform_patterns", "grooming_phrases", "watchlist", "glossary"))


def merge_into_feed_dict(feed, proposal: dict) -> dict:
    """Additive merge of a validated proposal onto the active feed,
    producing the next feed-document version."""
    return {
        "version": feed.version + 1,
        "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "off_platform_patterns": feed.off_platform_patterns + [
            {"platform": e["platform"], "pattern": e["pattern"]}
            for e in proposal["off_platform_patterns"]],
        "grooming_phrases": feed.grooming_phrases + [
            e["phrase"] for e in proposal["grooming_phrases"]],
        "thresholds": feed.thresholds,
        "watchlist": feed.watchlist + [
            {"place_id": e["place_id"], "name": e["name"], "reason": e["reason"]}
            for e in proposal["watchlist"]],
        "glossary": feed.glossary + [
            {"term": e["term"], "aliases": e.get("aliases") or [e["term"].lower()],
             "definition": e["definition"]}
            for e in proposal["glossary"]],
        "roblox_basics": feed.roblox_basics,
    }


# --------------------------------------------------------------------------
# Service
# --------------------------------------------------------------------------

class IntelService:
    def __init__(self, db, feeds, sources: Optional[list[dict]] = None,
                 analyzer=None, proposals_dir: Optional[str] = None,
                 auto_apply: Optional[bool] = None,
                 interval_seconds: Optional[int] = None):
        self.db = db
        self.feeds = feeds
        self.sources = sources if sources is not None else load_sources()
        self.auto_apply = (auto_apply if auto_apply is not None
                           else os.environ.get("RG_INTEL_AUTOAPPLY") == "1")
        self.interval = interval_seconds or int(os.environ.get("RG_INTEL_INTERVAL", 24 * 3600))
        self.proposals_dir = proposals_dir or os.environ.get(
            "RG_PROPOSALS_DIR",
            os.path.join(os.path.dirname(__file__), "..", "data", "proposals"))
        if analyzer is not None:
            self.analyzer = analyzer
        elif ClaudeThreatAnalyzer.available():
            self.analyzer = ClaudeThreatAnalyzer()
        else:
            self.analyzer = KeywordAnalyzer()
        self._task: Optional[asyncio.Task] = None

    def start(self) -> None:
        if not self.sources:
            log.info("no intel sources configured; daily threat search disabled")
            return
        self._task = asyncio.create_task(self._run_loop())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run_loop(self) -> None:
        while True:
            try:
                await self.run_once()
            except Exception:
                log.exception("intel run failed")
            await asyncio.sleep(self.interval)

    async def collect(self) -> list[Finding]:
        findings: list[Finding] = []
        async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as http:
            for source in self.sources:
                if source.get("type") != "rss" or not source.get("url"):
                    continue
                try:
                    findings.extend(await fetch_rss(source["url"], http))
                except Exception:
                    log.exception("intel source failed: %s", source.get("url"))
        return findings

    async def run_once(self) -> dict:
        """One daily cycle. Returns the stored run record."""
        findings = await self.collect()
        raw = await self.analyzer.analyze(findings)
        proposal = validate_proposal(raw, self.feeds.feed)
        proposal["flagged_findings"] = raw.get("flagged_findings", [])

        applied = False
        if self.auto_apply and not proposal_is_empty(proposal):
            from .threat_feed import _parse
            merged = merge_into_feed_dict(self.feeds.feed, proposal)
            self.feeds.feed = _parse(merged)
            self.feeds.source = "intel"
            applied = True
            log.info("intel proposal auto-applied as feed v%s", merged["version"])

        os.makedirs(self.proposals_dir, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = os.path.join(self.proposals_dir, f"proposal_{stamp}.json")
        with open(path, "w") as f:
            json.dump({"proposal": proposal, "applied": applied,
                       "analyzer": self.analyzer.name,
                       "findings_count": len(findings)}, f, indent=2)

        run_id = self.db.add_intel_run(
            analyzer=self.analyzer.name,
            findings_count=len(findings),
            proposal_counts={k: len(proposal.get(k, [])) for k in
                             ("off_platform_patterns", "grooming_phrases",
                              "watchlist", "glossary")},
            summary=proposal.get("summary", ""),
            applied=applied,
            proposal_path=path,
        )
        return self.db.get_intel_run(run_id)
