from datetime import datetime

import pytest

from app.config import Settings
from app.db import Database
from app.monitor import Monitor, load_watchlist
from app.roblox_client import RobloxPresence

from .conftest import FakeRobloxClient, make_profile

NOON = datetime(2026, 7, 11, 12, 0)


@pytest.fixture
def env(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "test.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)
    monitor = Monitor(db, fake_client, settings)
    child = make_profile(user_id=1, username="my_kid", display_name="MyKid", age_years=1)
    fake_client.add_user(child)
    child_id = db.add_child(1, "my_kid", "MyKid", "Parent Test")
    return db, fake_client, monitor, child_id


@pytest.mark.asyncio
async def test_baseline_poll_suppresses_info_noise(env):
    db, client, monitor, child_id = env
    client.friends[1] = [make_profile(user_id=2, username="pal", age_years=0.5)]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert created == []  # plain friend on baseline: no alert spam


@pytest.mark.asyncio
async def test_baseline_still_surfaces_risky_bio(env):
    db, client, monitor, child_id = env
    client.friends[1] = [make_profile(user_id=3, username="stranger",
                                      description="hmu on discord: xx#1234")]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert any(a["type"] == "off_platform_handle" for a in created)


@pytest.mark.asyncio
async def test_new_friend_after_baseline_creates_alert(env):
    db, client, monitor, child_id = env
    client.friends[1] = []
    await monitor.poll_child(child_id, local_now=NOON)

    client.friends[1] = [make_profile(user_id=4, username="newpal", age_years=0.4)]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert [a["type"] for a in created] == ["new_friend"]

    stored = db.list_alerts(child_id)
    assert stored[0]["subject_username"] == "newpal"


@pytest.mark.asyncio
async def test_duplicate_alerts_are_suppressed(env):
    db, client, monitor, child_id = env
    client.friends[1] = []
    await monitor.poll_child(child_id, local_now=NOON)
    client.friends[1] = [make_profile(user_id=5, username="pal5", age_years=0.4)]
    first = await monitor.poll_child(child_id, local_now=NOON)
    second = await monitor.poll_child(child_id, local_now=NOON)
    assert len(first) == 1 and second == []


@pytest.mark.asyncio
async def test_rapid_friending_fires_after_baseline(env):
    db, client, monitor, child_id = env
    client.friends[1] = []
    await monitor.poll_child(child_id, local_now=NOON)

    client.friends[1] = [
        make_profile(user_id=10 + i, username=f"pal{i}", age_years=0.3)
        for i in range(6)
    ]
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert any(a["type"] == "rapid_friending" for a in created)


@pytest.mark.asyncio
async def test_flagged_experience_from_watchlist(tmp_path, fake_client):
    watchlist_file = tmp_path / "watchlist.json"
    watchlist_file.write_text(
        '{"experiences": [{"place_id": 99, "name": "Sketchy Hangout",'
        ' "reason": "free-form voice chat with weak moderation"}]}'
    )
    settings = Settings(db_path=str(tmp_path / "t.db"), watchlist_path=str(watchlist_file))
    db = Database(settings.db_path)
    monitor = Monitor(db, fake_client, settings)
    fake_client.add_user(make_profile(user_id=1, username="my_kid"))
    child_id = db.add_child(1, "my_kid", "MyKid", "Parent Test")

    fake_client.presence[1] = RobloxPresence(user_id=1, presence_type=2, place_id=99,
                                             last_location="Sketchy Hangout")
    created = await monitor.poll_child(child_id, local_now=NOON)
    assert any(a["type"] == "flagged_experience" for a in created)


def test_load_watchlist_missing_and_malformed(tmp_path):
    assert load_watchlist(str(tmp_path / "nope.json")) == {}
    f = tmp_path / "w.json"
    f.write_text('{"experiences": [{"name": "no id"}, {"place_id": 7, "name": "ok", "reason": "r"}]}')
    out = load_watchlist(str(f))
    assert list(out) == [7]


@pytest.mark.asyncio
async def test_unlink_erases_everything(env):
    db, client, monitor, child_id = env
    client.friends[1] = [make_profile(user_id=6, username="pal6",
                                      description="snap: someone")]
    await monitor.poll_child(child_id, local_now=NOON)
    assert db.list_alerts(child_id)

    db.remove_child(child_id)
    assert db.get_child(child_id) is None
    assert db.list_alerts(child_id) == []
    assert db.latest_snapshot(child_id) is None
