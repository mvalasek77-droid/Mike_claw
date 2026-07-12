from datetime import datetime

import pytest

from app import glossary
from app import signals as sig
from app.roblox_client import RobloxPresence

from .conftest import make_profile


class TestExplain:
    def test_finds_terms_case_insensitively(self):
        terms = {e["term"] for e in glossary.explain(
            "Profile includes contact details for: Discord.",
            "Has 940 friends on Roblox, close to Roblox's 1,000-friend cap.")}
        assert "Discord" in terms
        assert "friend cap" in terms
        assert "profile" in terms

    def test_alias_matching(self):
        terms = {e["term"] for e in glossary.explain("was active at 23:30 local time")}
        assert "presence" in terms

    def test_no_false_positives_inside_words(self):
        # 'snap' must not match inside 'snapdragon players'
        terms = {e["term"] for e in glossary.explain("snapdragon players unite")}
        assert "Snapchat" not in terms

    def test_ordered_by_first_appearance(self):
        entries = glossary.explain("Robux gifts came before the Discord handle.")
        assert [e["term"] for e in entries][:2] == ["Robux", "Discord"]

    def test_empty_text(self):
        assert glossary.explain("") == []
        assert glossary.explain("nothing jargon-y here at all") == []


class TestCoverageOfSignalWording:
    """Every signal the engine emits must have its Roblox jargon covered by
    the glossary, so no alert ever shows an unexplained term."""

    def test_all_signal_types_produce_explainers(self, seed_feed):
        produced = []
        produced += sig.evaluate_new_friend(
            make_profile(description="d1sc0rd: a#1, dms open",
                         age_years=9, friend_count=950), seed_feed)
        produced += sig.evaluate_new_friend(make_profile(), seed_feed)
        rapid = sig.evaluate_rapid_friending(10, 24, 5)
        assert rapid
        produced.append(rapid)
        produced += sig.evaluate_presence(
            RobloxPresence(user_id=1, presence_type=2, place_id=42),
            {42: {"name": "X", "reason": "weak moderation"}},
            22, 6, local_now=datetime(2026, 7, 11, 23, 0))

        for signal in produced:
            entries = glossary.explain(signal.title, signal.guidance, *signal.facts)
            assert entries, f"signal {signal.type} has no glossary coverage"


class TestFeedContentMerge:
    def _feed_with_content(self):
        from app.threat_feed import _parse
        return _parse({
            "version": 2, "updated_at": "now",
            "glossary": [
                {"term": "ChatterBox", "aliases": ["chatterbox"],
                 "definition": "A new chat app with no child-safety moderation."},
                {"term": "Discord", "aliases": ["discord"],
                 "definition": "UPDATED definition delivered by the feed."},
            ],
            "roblox_basics": [
                {"id": "what_is_roblox", "question": "What is Roblox? (v2)",
                 "answer": "Updated answer."},
                {"id": "new_topic", "question": "What is ChatterBox?",
                 "answer": "A new app to know about."},
            ],
        })

    def test_feed_adds_and_overrides_glossary(self):
        merged = glossary.merged_glossary(self._feed_with_content())
        assert "ChatterBox" in merged
        assert merged["Discord"]["definition"].startswith("UPDATED")
        assert "Robux" in merged  # static entries survive

    def test_explain_uses_feed_terms(self):
        entries = glossary.explain("met them on chatterbox yesterday",
                                   feed=self._feed_with_content())
        assert any(e["term"] == "ChatterBox" for e in entries)

    def test_feed_overrides_basics_by_id(self):
        merged = {b["id"]: b for b in glossary.merged_basics(self._feed_with_content())}
        assert merged["what_is_roblox"]["question"].endswith("(v2)")
        assert "new_topic" in merged
        assert "what_are_robux" in merged  # untouched entries survive

    def test_education_payload_reflects_feed(self):
        from app.education import education_payload
        payload = education_payload(self._feed_with_content())
        terms = {g["term"] for g in payload["glossary"]}
        assert "ChatterBox" in terms

    def test_no_feed_means_static_content(self):
        assert glossary.merged_glossary(None) == glossary.GLOSSARY


class TestBasics:
    def test_basics_answer_core_questions(self):
        questions = " ".join(b["question"].lower() for b in glossary.ROBLOX_BASICS)
        assert "what is roblox" in questions
        assert "robux" in questions
        assert "friends" in questions

    def test_basics_are_plain_language(self):
        # No unexplained insider jargon in the basics themselves.
        for entry in glossary.ROBLOX_BASICS:
            text = entry["answer"].lower()
            for term in ("mdl", "leetspeak", "erp"):
                assert term not in text
