import hashlib
import json
import os

import pytest

from app.config import Settings
from app.db import Database
from app.evidence import EvidenceVault
from app.monitor import Monitor
from app.roblox_client import RobloxPresence

from .conftest import FakeRobloxClient, make_profile

from datetime import datetime

NOON = datetime(2026, 7, 11, 12, 0)


@pytest.fixture
def vault(tmp_path):
    db = Database(str(tmp_path / "e.db"))
    return db, EvidenceVault(db, str(tmp_path / "evidence"))


def test_data_snapshot_recorded_and_hashed(vault):
    db, v = vault
    child_id = db.add_child(1, "kid", "Kid", "Parent")
    evidence_id = v.record_data_snapshot(child_id, None, {"facts": ["x"]}, note="test")
    item = db.get_evidence(evidence_id)
    assert item["kind"] == "data_snapshot"
    assert os.path.exists(item["path"])
    with open(item["path"], "rb") as f:
        assert hashlib.sha256(f.read()).hexdigest() == item["sha256"]
    with open(item["path"]) as f:
        payload = json.load(f)
    assert payload["facts"] == ["x"] and "_captured_at" in payload


def test_parent_upload_stores_image_only(vault):
    db, v = vault
    child_id = db.add_child(1, "kid", "Kid", "Parent")
    evidence_id = v.store_parent_upload(child_id, "chat.PNG", b"fakepng", note="chat screenshot")
    item = db.get_evidence(evidence_id)
    assert item["kind"] == "parent_upload" and item["path"].endswith(".png")

    with pytest.raises(ValueError):
        v.store_parent_upload(child_id, "malware.exe", b"nope")


@pytest.mark.asyncio
async def test_profile_screenshot_captures_local_page(vault, tmp_path):
    """End-to-end browser capture against a local page (Roblox is not
    reachable from CI; the URL override exercises the identical code path)."""
    db, v = vault
    child_id = db.add_child(1, "kid", "Kid", "Parent")
    page = tmp_path / "profile.html"
    page.write_text("<html><body><h1>PublicProfile 555</h1></body></html>")

    evidence_id = await v.capture_profile_screenshot(
        child_id, None, 555, "someuser", url=page.as_uri())
    if evidence_id is None:
        pytest.skip("no usable Chromium in this environment")
    item = db.get_evidence(evidence_id)
    assert item["kind"] == "profile_screenshot"
    assert os.path.getsize(item["path"]) > 1000  # real PNG, not a stub
    assert "someuser" in item["note"]


@pytest.mark.asyncio
async def test_monitor_records_snapshot_evidence_for_risky_alert(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "m.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)

    class NoBrowserVault(EvidenceVault):
        async def capture_profile_screenshot(self, *a, **k):
            self.screenshot_requested = getattr(self, "screenshot_requested", 0) + 1
            return None

    vault = NoBrowserVault(db, str(tmp_path / "evidence"))
    monitor = Monitor(db, fake_client, settings, vault=vault)
    fake_client.add_user(make_profile(user_id=1, username="kid"))
    child_id = db.add_child(1, "kid", "Kid", "Parent")

    fake_client.friends[1] = [make_profile(user_id=9, username="stranger",
                                           description="discord: xx#1")]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert created

    items = db.list_evidence(child_id)
    assert any(i["kind"] == "data_snapshot" for i in items)
    assert vault.screenshot_requested >= 1  # capture attempted for subject


@pytest.mark.asyncio
async def test_monitor_skips_evidence_for_info_alerts(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "m2.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)
    vault = EvidenceVault(db, str(tmp_path / "evidence"))
    monitor = Monitor(db, fake_client, settings, vault=vault)
    fake_client.add_user(make_profile(user_id=1, username="kid"))
    child_id = db.add_child(1, "kid", "Kid", "Parent")

    fake_client.friends[1] = []
    await monitor.poll_child(child_id, local_now=NOON)
    fake_client.friends[1] = [make_profile(user_id=7, username="pal", age_years=0.3)]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert [a["type"] for a in created] == ["new_friend"]
    assert db.list_evidence(child_id) == []
