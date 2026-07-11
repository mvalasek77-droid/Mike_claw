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
    body = client.get("/health").json()
    assert body["status"] == "ok"


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


def test_education_endpoint(api):
    client, _ = api
    payload = client.get("/education").json()
    assert payload["dangers"] and payload["response_playbook"]


def test_health_reports_threat_feed(api):
    client, _ = api
    body = client.get("/health").json()
    assert body["threat_feed"]["version"] >= 1
    assert client.get("/threat-feed/status").json()["pattern_count"] > 0


def test_alert_feedback_endpoint(api):
    client, fake = api
    child_id = link(client).json()["id"]
    fake.friends[1] = [make_profile(user_id=2, username="stranger",
                                    description="discord: xx#1234")]
    client.post(f"/children/{child_id}/refresh")
    alerts = client.get(f"/children/{child_id}/alerts").json()["alerts"]
    alert_id = alerts[0]["id"]

    resp = client.post(f"/alerts/{alert_id}/feedback", json={"verdict": "confirmed"})
    assert resp.status_code == 200

    # feedback also acknowledges, so the alert leaves the open list
    remaining = client.get(f"/children/{child_id}/alerts").json()["alerts"]
    assert all(a["id"] != alert_id for a in remaining)

    assert client.post(f"/alerts/{alert_id}/feedback",
                       json={"verdict": "banana"}).status_code == 422
    assert client.post("/alerts/99999/feedback",
                       json={"verdict": "dismissed"}).status_code == 404


def test_children_include_poll_health(api):
    client, fake = api
    child_id = link(client).json()["id"]
    client.post(f"/children/{child_id}/refresh")
    children = client.get("/children").json()
    assert children[0]["last_poll_status"] == "ok"
    assert children[0]["last_poll_at"]


def test_evidence_upload_list_download(api):
    client, _ = api
    child_id = link(client).json()["id"]

    resp = client.post(
        f"/children/{child_id}/evidence/upload",
        files={"file": ("chat.png", b"\x89PNG fake image bytes", "image/png")},
        data={"note": "chat screenshot from child's iPad"},
    )
    assert resp.status_code == 201
    assert len(resp.json()["sha256"]) == 64

    listed = client.get(f"/children/{child_id}/evidence").json()["evidence"]
    assert listed[0]["kind"] == "parent_upload"
    assert listed[0]["note"] == "chat screenshot from child's iPad"
    assert "path" not in listed[0]  # server paths are not exposed

    evidence_id = listed[0]["id"]
    download = client.get(f"/evidence/{evidence_id}/file")
    assert download.status_code == 200
    assert download.content == b"\x89PNG fake image bytes"


def test_evidence_upload_rejects_non_image(api):
    client, _ = api
    child_id = link(client).json()["id"]
    resp = client.post(
        f"/children/{child_id}/evidence/upload",
        files={"file": ("notes.pdf", b"%PDF", "application/pdf")},
    )
    assert resp.status_code == 422


def test_report_endpoint_html_and_md(api):
    client, fake = api
    child_id = link(client).json()["id"]
    fake.friends[1] = [make_profile(user_id=2, username="stranger",
                                    description="discord: xx#1234")]
    client.post(f"/children/{child_id}/refresh")

    html_resp = client.get(f"/children/{child_id}/report")
    assert html_resp.status_code == 200
    assert html_resp.headers["content-type"].startswith("text/html")
    assert "@stranger" in html_resp.text

    md_resp = client.get(f"/children/{child_id}/report?format=md")
    assert md_resp.headers["content-type"].startswith("text/markdown")
    assert "# RobloxGuard incident report" in md_resp.text
    assert "report.cybertip.org" in md_resp.text


def test_unlink_removes_evidence_files(api, tmp_path):
    client, _ = api
    child_id = link(client).json()["id"]
    client.post(
        f"/children/{child_id}/evidence/upload",
        files={"file": ("chat.png", b"bytes", "image/png")},
    )
    listed = client.get(f"/children/{child_id}/evidence").json()["evidence"]
    evidence_id = listed[0]["id"]
    assert client.delete(f"/children/{child_id}").status_code == 204
    assert client.get(f"/evidence/{evidence_id}/file").status_code == 404
