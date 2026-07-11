import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

from .conftest import FakeRobloxClient, make_profile


@pytest.fixture
def api(tmp_path):
    fake = FakeRobloxClient()
    fake.add_user(make_profile(user_id=1, username="my_kid", display_name="MyKid"))
    settings = Settings(db_path=str(tmp_path / "api.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    app = create_app(settings=settings, client=fake, start_monitor=False)
    with TestClient(app) as client:
        yield client, fake


def link(client, username="my_kid", attest=True):
    return client.post("/children", json={
        "roblox_username": username,
        "parent_attestation": attest,
        "parent_name": "Pat Parent",
    })


def test_health(api):
    client, _ = api
    assert client.get("/health").json() == {"status": "ok"}


def test_link_requires_attestation(api):
    client, _ = api
    resp = link(client, attest=False)
    assert resp.status_code == 422


def test_link_unknown_username(api):
    client, _ = api
    assert link(client, username="nobody_here").status_code == 404


def test_link_and_list_and_duplicate(api):
    client, _ = api
    resp = link(client)
    assert resp.status_code == 201
    body = resp.json()
    assert body["roblox_username"] == "my_kid"

    assert link(client).status_code == 409  # already linked

    children = client.get("/children").json()
    assert len(children) == 1


def test_refresh_and_alerts_flow(api):
    client, fake = api
    child_id = link(client).json()["id"]
    fake.friends[1] = [make_profile(user_id=2, username="stranger",
                                    description="discord: xx#1234")]
    resp = client.post(f"/children/{child_id}/refresh")
    assert resp.status_code == 200
    assert any(a["type"] == "off_platform_handle" for a in resp.json()["new_alerts"])

    alerts = client.get(f"/children/{child_id}/alerts").json()["alerts"]
    assert alerts and alerts[0]["acknowledged"] is False

    alert_id = alerts[0]["id"]
    assert client.post(f"/alerts/{alert_id}/acknowledge").status_code == 200
    remaining = client.get(f"/children/{child_id}/alerts").json()["alerts"]
    assert all(a["id"] != alert_id for a in remaining)


def test_unlink_deletes_data(api):
    client, _ = api
    child_id = link(client).json()["id"]
    assert client.delete(f"/children/{child_id}").status_code == 204
    assert client.get("/children").json() == []
    assert client.get(f"/children/{child_id}/alerts").status_code == 404


def test_resources_listed(api):
    client, _ = api
    ids = {r["id"] for r in client.get("/resources").json()["resources"]}
    assert {"roblox_report_abuse", "cybertipline", "roblox_parental_controls"} <= ids
