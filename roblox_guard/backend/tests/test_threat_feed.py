import json

import pytest

from app.threat_feed import FeedManager, ThreatFeed, _parse, normalize_text


class TestNormalization:
    @pytest.mark.parametrize("raw,expected", [
        ("d1sc0rd", "discord"),
        ("SN@P", "snap"),
        ("t3l3gram", "telegram"),
        ("plain text", "plain text"),
    ])
    def test_leet_folding(self, raw, expected):
        assert normalize_text(raw) == expected


class TestMatching:
    def test_plain_match_not_flagged_obfuscated(self, seed_feed):
        found = seed_feed.match_off_platform("add me on discord: cool#1234")
        assert found == [{"platform": "Discord", "obfuscated": False}]

    def test_obfuscated_match_flagged(self, seed_feed):
        found = seed_feed.match_off_platform("d1sc0rd: shadow#1")
        assert found == [{"platform": "Discord", "obfuscated": True}]

    def test_obfuscated_snap(self, seed_feed):
        found = seed_feed.match_off_platform("my sn@p: someone.99")
        assert {"platform": "Snapchat", "obfuscated": True} in found

    def test_grooming_phrases_with_separators(self, seed_feed):
        assert seed_feed.match_grooming_phrases("DMs.open for everyone") == ["dms open"]
        assert "send pics" in seed_feed.match_grooming_phrases("s3nd pics plz")
        assert seed_feed.match_grooming_phrases("I love building obbies") == []

    def test_bad_pattern_skipped_not_fatal(self):
        feed = _parse({
            "version": 1, "updated_at": "x",
            "off_platform_patterns": [
                {"platform": "Broken", "pattern": "([unclosed"},
                {"platform": "Discord", "pattern": "discord"},
            ],
        })
        assert [p for p, _ in feed._compiled] == ["Discord"]


class TestFeedManager:
    def test_seed_loads(self):
        manager = FeedManager()
        assert manager.feed.version >= 1
        assert manager.source == "seed"
        status = manager.status()
        assert status["pattern_count"] > 0 and status["phrase_count"] > 0

    @pytest.mark.asyncio
    async def test_no_remote_url_never_refreshes(self):
        manager = FeedManager(remote_url="")
        assert await manager.maybe_refresh() is False

    @pytest.mark.asyncio
    async def test_remote_refresh_applies_newer_version(self, monkeypatch, tmp_path):
        newer = {
            "version": 99, "updated_at": "2026-08-01",
            "off_platform_patterns": [{"platform": "NewApp", "pattern": "newapp\\s*:"}],
            "watchlist": [{"place_id": 777, "name": "Fresh Condo", "reason": "new intel"}],
        }

        class FakeResponse:
            def raise_for_status(self): pass
            def json(self): return newer

        class FakeClient:
            def __init__(self, **kwargs): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *a): return False
            async def get(self, url): return FakeResponse()

        monkeypatch.setattr("app.threat_feed.httpx.AsyncClient", FakeClient)
        manager = FeedManager(remote_url="https://feed.example/threats.json")
        assert await manager.maybe_refresh() is True
        assert manager.feed.version == 99
        assert manager.source == "remote"
        assert manager.feed.match_off_platform("newapp: someone")
        assert 777 in manager.feed.watchlist_by_place()

    @pytest.mark.asyncio
    async def test_remote_refresh_rejects_stale_and_survives_errors(self, monkeypatch):
        stale = {"version": 0, "updated_at": "old"}

        class FakeResponse:
            def raise_for_status(self): pass
            def json(self): return stale

        class FakeClient:
            def __init__(self, **kwargs): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *a): return False
            async def get(self, url): return FakeResponse()

        monkeypatch.setattr("app.threat_feed.httpx.AsyncClient", FakeClient)
        manager = FeedManager(remote_url="https://feed.example/threats.json")
        original = manager.feed.version
        assert await manager.maybe_refresh() is False
        assert manager.feed.version == original

        class BrokenClient:
            def __init__(self, **kwargs): pass
            async def __aenter__(self): raise ConnectionError("down")
            async def __aexit__(self, *a): return False

        monkeypatch.setattr("app.threat_feed.httpx.AsyncClient", BrokenClient)
        manager2 = FeedManager(remote_url="https://feed.example/threats.json")
        assert await manager2.maybe_refresh() is False
        assert manager2.feed.version == original  # seed still active
