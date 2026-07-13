"""APNs push notifications: JWT signing, device token storage, delivery,
dead-token pruning, and the monitor hook that fires a push per new alert."""

import httpx
import pytest

from app.config import Settings
from app.db import Database
from app.monitor import Monitor
from app.push import APNsService
from app.signals import Severity, Signal, SignalType

from .conftest import FakeRobloxClient, make_profile


def _real_test_key() -> str:
    """A freshly generated EC private key in the .p8 PEM format APNs expects
    — this one is thrown away after the test run, never a real Apple key."""
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    key = ec.generate_private_key(ec.SECP256R1())
    return key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()


def configured_settings(**overrides) -> Settings:
    defaults = dict(
        apns_key_p8=_real_test_key(),
        apns_key_id="TESTKEYID1",
        apns_team_id="TESTTEAMID",
        apns_bundle_id="com.mikeclaw.robloxguard",
    )
    defaults.update(overrides)
    return Settings(**defaults)


# -- configuration & JWT ------------------------------------------------------

def test_unconfigured_by_default():
    service = APNsService(Settings())
    assert service.configured is False


def test_configured_when_key_and_ids_present():
    service = APNsService(configured_settings())
    assert service.configured is True


def test_missing_team_id_is_unconfigured():
    settings = configured_settings(apns_team_id="")
    assert APNsService(settings).configured is False


def test_auth_token_is_valid_jwt_with_expected_claims():
    import jwt as pyjwt

    service = APNsService(configured_settings())
    token = service._auth_token()
    header = pyjwt.get_unverified_header(token)
    assert header["alg"] == "ES256"
    assert header["kid"] == "TESTKEYID1"
    claims = pyjwt.decode(token, options={"verify_signature": False})
    assert claims["iss"] == "TESTTEAMID"


def test_auth_token_is_cached_across_calls():
    service = APNsService(configured_settings())
    first = service._auth_token()
    second = service._auth_token()
    assert first == second


# -- send() / delivery -----------------------------------------------------------

@pytest.mark.asyncio
async def test_send_noop_when_unconfigured():
    service = APNsService(Settings())
    ok = await service.send("deadbeef" * 8, "Watch alert", "Something happened")
    assert ok is False


@pytest.mark.asyncio
async def test_send_success(monkeypatch):
    service = APNsService(configured_settings())

    async def fake_post(self, url, json=None, headers=None):
        assert "/3/device/" in url
        assert headers["apns-topic"] == "com.mikeclaw.robloxguard"
        assert json["aps"]["alert"]["title"] == "Watch alert"
        return httpx.Response(200, request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    ok = await service.send("a" * 64, "Watch alert", "Something happened", badge=3)
    assert ok is True


@pytest.mark.asyncio
async def test_send_failure_returns_false(monkeypatch):
    service = APNsService(configured_settings())

    async def fake_post(self, url, json=None, headers=None):
        return httpx.Response(400, text='{"reason":"BadDeviceToken"}',
                              request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    ok = await service.send("a" * 64, "x", "y")
    assert ok is False


@pytest.mark.asyncio
async def test_send_transport_error_is_caught(monkeypatch):
    service = APNsService(configured_settings())

    async def fake_post(self, url, json=None, headers=None):
        raise httpx.ConnectTimeout("timed out")

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    ok = await service.send("a" * 64, "x", "y")
    assert ok is False


# -- send_to_all() / pruning ------------------------------------------------------

@pytest.mark.asyncio
async def test_send_to_all_prunes_dead_tokens(monkeypatch, tmp_path):
    db = Database(str(tmp_path / "t.db"))
    db.register_device_token("good-token")
    db.register_device_token("dead-token")
    service = APNsService(configured_settings())

    async def fake_post(self, url, json=None, headers=None):
        if "dead-token" in url:
            return httpx.Response(410, request=httpx.Request("POST", url))
        return httpx.Response(200, request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    result = await service.send_to_all(db, "Title", "Body")
    assert result == {"sent": 1, "failed": 1, "pruned": 1, "configured": True}
    assert db.list_device_tokens() == ["good-token"]


@pytest.mark.asyncio
async def test_send_to_all_unconfigured_reports_zero(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    db.register_device_token("some-token")
    service = APNsService(Settings())
    result = await service.send_to_all(db, "Title", "Body")
    assert result == {"sent": 0, "failed": 0, "pruned": 0, "configured": False}
    assert db.list_device_tokens() == ["some-token"]  # nothing pruned when unconfigured


# -- db layer ------------------------------------------------------------------

def test_register_device_token_upserts(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    db.register_device_token("tok1", platform="ios")
    db.register_device_token("tok1", platform="ios")  # re-register, e.g. app relaunch
    assert db.list_device_tokens() == ["tok1"]


def test_remove_device_token(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    db.register_device_token("tok1")
    db.remove_device_token("tok1")
    assert db.list_device_tokens() == []


def test_total_unacknowledged_alerts(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    child_id = db.add_child(1, "kid", "Kid", "Parent")
    assert db.total_unacknowledged_alerts() == 0

    signal = Signal(type=SignalType.OFF_PLATFORM_HANDLE, severity=Severity.ELEVATED,
                    title="Test alert", facts=["fact"], guidance="guidance")
    alert_id = db.add_alert(child_id, signal)
    assert db.total_unacknowledged_alerts() == 1

    db.acknowledge_alert(alert_id)
    assert db.total_unacknowledged_alerts() == 0


# -- monitor hook ------------------------------------------------------------

class RecordingPush:
    def __init__(self):
        self.calls = []
        self.configured = True

    async def send_to_all(self, db, title, body):
        self.calls.append((title, body))
        return {"sent": 1, "failed": 0, "pruned": 0, "configured": True}


@pytest.mark.asyncio
async def test_monitor_pushes_for_non_info_alert(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "t.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)
    push = RecordingPush()
    monitor = Monitor(db, fake_client, settings, push=push)
    fake_client.add_user(make_profile(user_id=1, username="my_kid", age_years=1))
    child_id = db.add_child(1, "my_kid", "MyKid", "Parent Test")

    fake_client.friends[1] = [make_profile(
        user_id=2, username="stranger", description="hmu on discord: xx#1234")]
    await monitor.poll_child(child_id)

    assert len(push.calls) == 1
    assert "MyKid" in push.calls[0][0]


@pytest.mark.asyncio
async def test_monitor_does_not_push_for_info_only_baseline(tmp_path, fake_client):
    settings = Settings(db_path=str(tmp_path / "t.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    db = Database(settings.db_path)
    push = RecordingPush()
    monitor = Monitor(db, fake_client, settings, push=push)
    fake_client.add_user(make_profile(user_id=1, username="my_kid", age_years=1))
    child_id = db.add_child(1, "my_kid", "MyKid", "Parent Test")

    fake_client.friends[1] = [make_profile(user_id=2, username="pal", age_years=0.5)]
    await monitor.poll_child(child_id)

    assert push.calls == []


# -- API endpoints --------------------------------------------------------------

@pytest.fixture
def api(tmp_path):
    from fastapi.testclient import TestClient
    from app.main import create_app

    fake = FakeRobloxClient()
    settings = Settings(db_path=str(tmp_path / "api.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    app = create_app(settings=settings, client=fake, start_monitor=False)
    with TestClient(app) as client:
        yield client


def test_register_device_endpoint(api):
    resp = api.post("/devices/register", json={"token": "a" * 64, "platform": "ios"})
    assert resp.status_code == 201
    assert resp.json() == {"registered": True}

    status = api.get("/notifications/status").json()
    assert status["registered_devices"] == 1
    assert status["configured"] is False  # no APNs key set in this test env


def test_unregister_device_endpoint(api):
    api.post("/devices/register", json={"token": "a" * 64})
    resp = api.delete(f"/devices/{'a' * 64}")
    assert resp.status_code == 204
    assert api.get("/notifications/status").json()["registered_devices"] == 0


def test_register_device_rejects_short_token(api):
    resp = api.post("/devices/register", json={"token": "short"})
    assert resp.status_code == 422


def test_test_notification_requires_apns_configured(api):
    api.post("/devices/register", json={"token": "a" * 64})
    resp = api.post("/notifications/test")
    assert resp.status_code == 409
    assert "not configured" in resp.json()["detail"]


@pytest.fixture
def apns_api(tmp_path):
    from fastapi.testclient import TestClient
    from app.main import create_app

    fake = FakeRobloxClient()
    settings = configured_settings(db_path=str(tmp_path / "apns.db"),
                                   watchlist_path=str(tmp_path / "missing.json"))
    app = create_app(settings=settings, client=fake, start_monitor=False)
    with TestClient(app) as client:
        yield client


def test_test_notification_requires_a_registered_device_endpoint(apns_api):
    resp = apns_api.post("/notifications/test")
    assert resp.status_code == 409
    assert "No devices registered" in resp.json()["detail"]


def test_test_notification_sends_when_configured(apns_api, monkeypatch):
    apns_api.post("/devices/register", json={"token": "a" * 64})

    async def fake_post(self, url, json=None, headers=None):
        return httpx.Response(200, request=httpx.Request("POST", url))

    monkeypatch.setattr(httpx.AsyncClient, "post", fake_post)
    resp = apns_api.post("/notifications/test")
    assert resp.status_code == 200
    body = resp.json()
    assert body["sent"] == 1
    assert body["configured"] is True
