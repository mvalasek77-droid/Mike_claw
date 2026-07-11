from datetime import datetime

import pytest

from app import education
from app.config import Settings
from app.db import Database
from app.evidence import EvidenceVault
from app.monitor import Monitor
from app.report import build_report_html, build_report_markdown

from .conftest import make_profile

NOON = datetime(2026, 7, 11, 12, 0)


@pytest.fixture
async def populated(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "r.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)

    class NoBrowserVault(EvidenceVault):
        async def capture_profile_screenshot(self, *a, **k):
            return None

    vault = NoBrowserVault(db, str(tmp_path / "evidence"))
    monitor = Monitor(db, fake_client, settings, vault=vault)
    fake_client.add_user(make_profile(user_id=1, username="my_kid"))
    child_id = db.add_child(1, "my_kid", "MyKid", "Pat Parent")
    fake_client.friends[1] = [make_profile(user_id=9, username="stranger",
                                           description="hmu discord: xx#1")]
    await monitor.poll_child(child_id, local_now=NOON)
    child = db.get_child(child_id)
    return child, db.list_alerts(child_id, include_acknowledged=True), db.list_evidence(child_id)


async def test_report_contains_all_sections(populated):
    child, alerts, evidence = populated
    md = build_report_markdown(child, alerts, evidence)

    assert "# RobloxGuard incident report" in md
    assert "@my_kid" in md
    assert "Pat Parent" in md
    # Situation summary explains the off-platform pivot in plain language
    assert "off Roblox" in md
    # Danger pattern education is woven in for the observed signal types
    assert "The off-platform funnel" in md
    # Timeline includes the subject account and facts
    assert "@stranger" in md
    # Behavioral signs + red flags + playbook + evidence inventory
    assert "Signs to check for at home" in md
    assert "Act the same day" in md
    assert "SHA-256" in md and "data snapshot" in md
    assert "report.cybertip.org" in md
    # Disclaimers present
    assert "does not accuse" in md
    assert "never save, upload, or forward" in md


async def test_report_never_labels_individuals(populated):
    """The report may discuss predatory *patterns* in education sections, but
    every sentence naming the specific account must stay factual."""
    child, alerts, evidence = populated
    md = build_report_markdown(child, alerts, evidence)
    for line in md.splitlines():
        if "@stranger" in line:
            lowered = line.lower()
            assert "predator" not in lowered and "groomer" not in lowered


async def test_html_report_is_standalone(populated):
    child, alerts, evidence = populated
    html_doc = build_report_html(child, alerts, evidence)
    assert html_doc.startswith("<!doctype html>")
    assert "@my_kid" in html_doc
    assert "<script" not in html_doc.lower()


def test_empty_report_still_valid(tmp_path):
    db = Database(str(tmp_path / "empty.db"))
    child_id = db.add_child(1, "quiet_kid", "QuietKid", "Parent")
    md = build_report_markdown(db.get_child(child_id), [], [])
    assert "No safety alerts are currently recorded" in md
    assert "_No alerts recorded._" in md
    assert "_No evidence captured yet._" in md


def test_education_payload_shape():
    payload = education.education_payload()
    assert payload["dangers"] and payload["behavioral_signs"]
    assert payload["immediate_red_flags"] and payload["response_playbook"]
    ids = {d["id"] for d in payload["dangers"]}
    assert {"grooming_contact", "off_platform_funnel", "sextortion"} <= ids

    matched = education.dangers_for_signal_types({"off_platform_handle"})
    assert any(d["id"] == "off_platform_funnel" for d in matched)
    assert education.dangers_for_signal_types(set()) == []
