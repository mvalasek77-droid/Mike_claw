import json

import httpx
import pytest

from app import intel
from app.db import Database
from app.threat_feed import FeedManager, _parse

RSS_FIXTURE = """<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item>
    <title>New app 'ChatterBox' used to lure Roblox kids off-platform</title>
    <link>https://news.example/chatterbox</link>
    <description>Investigators warn of grooming via a new chat app.</description>
    <pubDate>Fri, 10 Jul 2026 08:00:00 GMT</pubDate>
  </item>
  <item>
    <title>Local bakery wins award</title>
    <link>https://news.example/bakery</link>
    <description>Unrelated news.</description>
  </item>
</channel></rss>"""


@pytest.mark.asyncio
async def test_fetch_rss_parses_items():
    transport = httpx.MockTransport(lambda req: httpx.Response(200, text=RSS_FIXTURE))
    async with httpx.AsyncClient(transport=transport) as http:
        findings = await intel.fetch_rss("https://news.example/feed", http)
    assert len(findings) == 2
    assert findings[0].title.startswith("New app 'ChatterBox'")
    assert findings[0].url == "https://news.example/chatterbox"


def test_relevance_filter():
    hit = intel.Finding(source="s", title="Roblox grooming case", url="u")
    miss = intel.Finding(source="s", title="Bakery wins award", url="u")
    assert intel.relevant(hit) and not intel.relevant(miss)


class TestValidation:
    def _feed(self):
        return FeedManager().feed

    def test_bad_regex_dropped(self):
        raw = {"off_platform_patterns": [
            {"platform": "Broken", "pattern": "([oops", "rationale": "r", "source_url": "u"},
            {"platform": "ChatterBox", "pattern": "chatterbox\\s*[:@-]\\s*\\S+",
             "rationale": "r", "source_url": "u"},
        ], "grooming_phrases": [], "watchlist": [], "glossary": [], "summary": "s"}
        out = intel.validate_proposal(raw, self._feed())
        assert [e["platform"] for e in out["off_platform_patterns"]] == ["ChatterBox"]

    def test_existing_platform_not_duplicated(self):
        raw = {"off_platform_patterns": [
            {"platform": "Discord", "pattern": "discord", "rationale": "r", "source_url": "u"},
        ], "grooming_phrases": [], "watchlist": [], "glossary": [], "summary": ""}
        assert intel.validate_proposal(raw, self._feed())["off_platform_patterns"] == []

    def test_labeling_text_dropped(self):
        raw = {"off_platform_patterns": [], "grooming_phrases": [], "watchlist": [
            {"place_id": 5, "name": "Some Game",
             "reason": "run by a known predator", "source_url": "u"},
        ], "glossary": [], "summary": ""}
        assert intel.validate_proposal(raw, self._feed())["watchlist"] == []

    def test_caps_enforced(self):
        raw = {"off_platform_patterns": [], "watchlist": [], "glossary": [],
               "grooming_phrases": [
                   {"phrase": f"phrase number {i}", "rationale": "r", "source_url": "u"}
                   for i in range(30)],
               "summary": ""}
        out = intel.validate_proposal(raw, self._feed())
        assert len(out["grooming_phrases"]) == intel.MAX_NEW_PHRASES

    def test_guessed_place_ids_rejected(self):
        raw = {"off_platform_patterns": [], "grooming_phrases": [], "glossary": [],
               "watchlist": [{"place_id": 0, "name": "X", "reason": "r", "source_url": "u"},
                             {"place_id": "not-a-number", "name": "X", "reason": "r",
                              "source_url": "u"}],
               "summary": ""}
        assert intel.validate_proposal(raw, self._feed())["watchlist"] == []


def test_merge_is_additive_and_bumps_version():
    feeds = FeedManager()
    proposal = {
        "off_platform_patterns": [{"platform": "ChatterBox",
                                   "pattern": "chatterbox\\s*[:@-]\\s*\\S+",
                                   "rationale": "r", "source_url": "u"}],
        "grooming_phrases": [{"phrase": "add me for gift", "rationale": "r", "source_url": "u"}],
        "watchlist": [{"place_id": 999, "name": "Hangout X", "reason": "weak moderation",
                       "source_url": "u"}],
        "glossary": [{"term": "ChatterBox", "aliases": ["chatterbox"],
                      "definition": "A new chat app with no child-safety moderation.",
                      "source_url": "u"}],
        "summary": "s",
    }
    original = feeds.feed
    merged = _parse(intel.merge_into_feed_dict(original, proposal))
    assert merged.version == original.version + 1
    # everything old still present
    assert len(merged.off_platform_patterns) == len(original.off_platform_patterns) + 1
    assert set(original.grooming_phrases) <= set(merged.grooming_phrases)
    # new detections active
    assert merged.match_off_platform("chatterbox: luvskids99")
    assert 999 in merged.watchlist_by_place()


class FakeSource:
    pass


class FakeAnalyzer:
    name = "fake"

    def __init__(self, result):
        self._result = result

    async def analyze(self, findings):
        return self._result


@pytest.fixture
def service(tmp_path, monkeypatch):
    db = Database(str(tmp_path / "i.db"))
    feeds = FeedManager()
    result = {
        "off_platform_patterns": [{"platform": "ChatterBox",
                                   "pattern": "chatterbox\\s*[:@-]\\s*\\S+",
                                   "rationale": "r", "source_url": "u"}],
        "grooming_phrases": [], "watchlist": [], "glossary": [],
        "summary": "one new platform found",
    }
    svc = intel.IntelService(
        db, feeds, sources=[{"type": "rss", "url": "https://news.example/feed"}],
        analyzer=FakeAnalyzer(result), proposals_dir=str(tmp_path / "proposals"),
        auto_apply=False)

    async def fake_collect(self):
        return [intel.Finding(source="s", title="Roblox grooming via ChatterBox", url="u")]
    monkeypatch.setattr(intel.IntelService, "collect", fake_collect)
    return db, feeds, svc, tmp_path


@pytest.mark.asyncio
async def test_run_once_stores_proposal_without_applying(service):
    db, feeds, svc, tmp_path = service
    original_version = feeds.feed.version
    run = await svc.run_once()
    assert run["applied"] is False
    assert run["proposal_counts"]["off_platform_patterns"] == 1
    assert feeds.feed.version == original_version  # not applied
    with open(run["proposal_path"]) as f:
        stored = json.load(f)
    assert stored["proposal"]["off_platform_patterns"][0]["platform"] == "ChatterBox"
    assert db.list_intel_runs()[0]["id"] == run["id"]


@pytest.mark.asyncio
async def test_run_once_auto_apply(service):
    db, feeds, svc, _ = service
    svc.auto_apply = True
    original_version = feeds.feed.version
    run = await svc.run_once()
    assert run["applied"] is True
    assert feeds.feed.version == original_version + 1
    assert feeds.source == "intel"
    assert feeds.feed.match_off_platform("chatterbox: someone")


@pytest.mark.asyncio
async def test_keyword_analyzer_proposes_nothing():
    analyzer = intel.KeywordAnalyzer()
    out = await analyzer.analyze([
        intel.Finding(source="s", title="Roblox sextortion warning", url="u"),
        intel.Finding(source="s", title="Bakery award", url="u"),
    ])
    assert intel.proposal_is_empty(out)
    assert len(out["flagged_findings"]) == 1


@pytest.mark.asyncio
async def test_claude_analyzer_parses_structured_response():
    class FakeBlock:
        type = "text"
        text = json.dumps({
            "off_platform_patterns": [], "grooming_phrases": [],
            "watchlist": [], "glossary": [], "summary": "nothing new today",
        })

    class FakeResponse:
        stop_reason = "end_turn"
        content = [FakeBlock()]

    class FakeMessages:
        async def create(self, **kwargs):
            assert kwargs["model"] == "claude-opus-4-8"
            assert kwargs["output_config"]["format"]["type"] == "json_schema"
            return FakeResponse()

    class FakeClient:
        messages = FakeMessages()

    analyzer = intel.ClaudeThreatAnalyzer(client=FakeClient())
    out = await analyzer.analyze([intel.Finding(source="s", title="roblox news", url="u")])
    assert out["summary"] == "nothing new today"


def test_service_without_sources_does_not_start(tmp_path):
    db = Database(str(tmp_path / "n.db"))
    svc = intel.IntelService(db, FeedManager(), sources=[],
                             analyzer=FakeAnalyzer({}), auto_apply=False)
    svc.start()
    assert svc._task is None
