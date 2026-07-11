from datetime import datetime, timezone

import pytest

from app import signals as sig
from app.roblox_client import RobloxPresence

from .conftest import make_profile


class TestOffPlatformDetection:
    @pytest.mark.parametrize("bio,expected", [
        ("add me on discord: cooldude#1234", ["Discord"]),
        ("dc @ shadow_wolf", ["Discord"]),
        ("snap: jimmy.2011", ["Snapchat"]),
        ("t.me/somechannel", ["Telegram"]),
        ("kik: talk2me99", ["Kik"]),
        ("ig: my.handle", ["Instagram"]),
        ("text me 555-123-4567", ["phone number"]),
        ("I love building obbies with my friends!", []),
        ("", []),
        # 'kik'/'ig' inside ordinary words must not match
        ("wikikid fan, big fan of pig games", []),
    ])
    def test_detection(self, seed_feed, bio, expected):
        assert [m["platform"] for m in seed_feed.match_off_platform(bio)] == expected

    def test_multiple_platforms(self, seed_feed):
        found = {m["platform"] for m in seed_feed.match_off_platform("disc: abc#1 / snap: xyz")}
        assert found == {"Discord", "Snapchat"}


class TestNewFriendEvaluation:
    def test_plain_new_friend_is_info(self, seed_feed):
        friend = make_profile(age_years=0.8, friend_count=15)
        out = sig.evaluate_new_friend(friend, seed_feed)
        assert len(out) == 1
        assert out[0].type == sig.SignalType.NEW_FRIEND
        assert out[0].severity == sig.Severity.INFO

    def test_off_platform_handle_is_elevated(self, seed_feed):
        friend = make_profile(description="add my discord: xx#0001")
        out = sig.evaluate_new_friend(friend, seed_feed)
        types = {s.type for s in out}
        assert sig.SignalType.OFF_PLATFORM_HANDLE in types
        elevated = next(s for s in out if s.type == sig.SignalType.OFF_PLATFORM_HANDLE)
        assert elevated.severity == sig.Severity.ELEVATED
        assert elevated.subject_user_id == friend.user_id

    def test_obfuscated_handle_notes_filter_evasion(self, seed_feed):
        friend = make_profile(description="hmu d1sc0rd: shadow#1")
        out = sig.evaluate_new_friend(friend, seed_feed)
        handle = next(s for s in out if s.type == sig.SignalType.OFF_PLATFORM_HANDLE)
        assert any("character substitutions" in f for f in handle.facts)

    def test_handle_in_display_name_detected(self, seed_feed):
        friend = make_profile(display_name="snap: luretarget", description="")
        out = sig.evaluate_new_friend(friend, seed_feed)
        assert any(s.type == sig.SignalType.OFF_PLATFORM_HANDLE for s in out)

    def test_grooming_phrase_is_elevated(self, seed_feed):
        friend = make_profile(description="new here, dms open, be nice")
        out = sig.evaluate_new_friend(friend, seed_feed)
        phrase = next(s for s in out if s.type == sig.SignalType.GROOMING_PHRASE)
        assert phrase.severity == sig.Severity.ELEVATED
        assert any("dms open" in f for f in phrase.facts)

    def test_established_account_is_watch(self, seed_feed):
        friend = make_profile(age_years=9, friend_count=50)
        out = sig.evaluate_new_friend(friend, seed_feed, established_years=5)
        assert out[0].type == sig.SignalType.ESTABLISHED_ACCOUNT_CONTACT
        assert out[0].severity == sig.Severity.WATCH

    def test_mass_friender_is_watch(self, seed_feed):
        friend = make_profile(age_years=1, friend_count=950)
        out = sig.evaluate_new_friend(friend, seed_feed, mass_friender_threshold=700)
        assert out[0].type == sig.SignalType.LARGE_NETWORK_CONTACT

    def test_young_small_account_no_watch_signal(self, seed_feed):
        friend = make_profile(age_years=1, friend_count=30)
        out = sig.evaluate_new_friend(friend, seed_feed,
                                      established_years=5, mass_friender_threshold=700)
        assert all(s.severity == sig.Severity.INFO for s in out)

    def test_feed_thresholds_override_defaults(self, seed_feed):
        # Seed feed sets established_account_years=5; caller passing 50 is overridden.
        friend = make_profile(age_years=9, friend_count=50)
        out = sig.evaluate_new_friend(friend, seed_feed, established_years=50)
        assert out[0].type == sig.SignalType.ESTABLISHED_ACCOUNT_CONTACT


class TestRapidFriending:
    def test_below_threshold(self):
        assert sig.evaluate_rapid_friending(3, 24, 5) is None

    def test_at_threshold(self):
        s = sig.evaluate_rapid_friending(5, 24, 5)
        assert s is not None and s.type == sig.SignalType.RAPID_FRIENDING


class TestPresence:
    def test_flagged_experience(self):
        presence = RobloxPresence(user_id=1, presence_type=2, place_id=42,
                                  last_location="Hangout")
        watchlist = {42: {"name": "Hangout", "reason": "unmoderated voice lobby"}}
        day = datetime(2026, 7, 11, 14, 0)
        out = sig.evaluate_presence(presence, watchlist, 22, 6, local_now=day)
        assert [s.type for s in out] == [sig.SignalType.FLAGGED_EXPERIENCE]

    def test_quiet_hours_wrapping_midnight(self):
        presence = RobloxPresence(user_id=1, presence_type=2)
        late = datetime(2026, 7, 11, 23, 30)
        out = sig.evaluate_presence(presence, {}, 22, 6, local_now=late)
        assert [s.type for s in out] == [sig.SignalType.QUIET_HOURS_ACTIVITY]

        early = datetime(2026, 7, 11, 5, 30)
        out = sig.evaluate_presence(presence, {}, 22, 6, local_now=early)
        assert [s.type for s in out] == [sig.SignalType.QUIET_HOURS_ACTIVITY]

    def test_daytime_no_quiet_signal(self):
        presence = RobloxPresence(user_id=1, presence_type=2)
        noon = datetime(2026, 7, 11, 12, 0)
        assert sig.evaluate_presence(presence, {}, 22, 6, local_now=noon) == []

    def test_offline_no_signals(self):
        presence = RobloxPresence(user_id=1, presence_type=0)
        late = datetime(2026, 7, 11, 23, 30)
        assert sig.evaluate_presence(presence, {}, 22, 6, local_now=late) == []


class TestWordingPolicy:
    """Every signal the engine can produce must stay factual and label-free."""

    def _all_signals(self, seed_feed):
        out = []
        out += sig.evaluate_new_friend(
            make_profile(description="d1sc0rd: a#1, dms open, our secret",
                         age_years=9, friend_count=950), seed_feed)
        out += sig.evaluate_new_friend(make_profile(), seed_feed)
        s = sig.evaluate_rapid_friending(10, 24, 5)
        assert s
        out.append(s)
        out += sig.evaluate_presence(
            RobloxPresence(user_id=1, presence_type=2, place_id=42),
            {42: {"name": "X", "reason": "weak moderation"}},
            22, 6, local_now=datetime(2026, 7, 11, 23, 0),
        )
        return out

    def test_no_forbidden_labels(self, seed_feed):
        produced = self._all_signals(seed_feed)
        assert len({s.type for s in produced}) >= 6
        for s in produced:
            sig.validate_wording(s)  # raises on violation

    def test_validate_wording_catches_labels(self):
        s = sig.Signal(
            type=sig.SignalType.NEW_FRIEND, severity=sig.Severity.INFO,
            title="This user is a predator", facts=[], guidance="",
        )
        with pytest.raises(ValueError):
            sig.validate_wording(s)

    def test_validate_wording_allows_ordinary_words(self):
        s = sig.Signal(
            type=sig.SignalType.NEW_FRIEND, severity=sig.Severity.INFO,
            title="Played a new roadmap game", facts=["Loves treasure maps? no — roadmaps."],
            guidance="",
        )
        sig.validate_wording(s)
