"""End-to-end simulation of the full parent journey, as the iPhone app
drives it, plus edge cases and a performance budget.

Accounts are realistic but SYNTHETIC. We deliberately do not test against
real children's accounts found online: monitoring a real minor without their
parent's consent is exactly what the product's consent model forbids, and
"testing" wouldn't make it acceptable.
"""

import time
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

from .conftest import FakeRobloxClient, make_profile

NOON = datetime(2026, 7, 11, 12, 0)


@pytest.fixture
def world(tmp_path):
    """A small synthetic Roblox world with kid-style accounts."""
    fake = FakeRobloxClient()
    fake.add_user(make_profile(user_id=101, username="emma_playz2016",
                               display_name="emma 🦄", age_years=1.2))
    # Ordinary school friends
    fake.friends[101] = [
        make_profile(user_id=201, username="liam.builds", age_years=0.9, friend_count=22),
        make_profile(user_id=202, username="sofia_obby_fan", age_years=1.4, friend_count=31),
    ]
    settings = Settings(db_path=str(tmp_path / "e2e.db"),
                        watchlist_path=str(tmp_path / "missing.json"))
    app = create_app(settings=settings, client=fake, start_monitor=False)
    with TestClient(app) as client:
        yield client, fake


def link(client, username="emma_playz2016"):
    resp = client.post("/children", json={
        "roblox_username": username,
        "parent_attestation": True,
        "parent_name": "Jordan Rivera",
    })
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


class TestFullParentJourney:
    """The complete iPhone flow: onboard -> baseline -> threat appears ->
    alert -> evidence -> report -> feedback -> resolution -> unlink."""

    def test_journey(self, world):
        client, fake = world

        # 1. Parent links the child (onboarding consent done in-app).
        child_id = link(client)

        # 2. Baseline scan: two ordinary school friends -> no alert noise.
        assert client.post(f"/children/{child_id}/refresh").json()["new_alerts"] == []

        # 3. Days later, a predatory-patterned account friends the child:
        #    8-year-old account, 940 friends, obfuscated Discord handle and
        #    a grooming phrase in the bio.
        fake.friends[101].append(make_profile(
            user_id=666, username="xX_DarkTrader_Xx", display_name="GiftMaster",
            description="free robux dm · d1sc0rd: gift4u#0001", age_years=8.2,
            friend_count=940))
        created = client.post(f"/children/{child_id}/refresh").json()["new_alerts"]
        types = {a["type"] for a in created}
        assert {"off_platform_handle", "grooming_phrase"} <= types

        # 4. The alert explains itself in plain language for a Roblox-novice.
        alerts = client.get(f"/children/{child_id}/alerts").json()["alerts"]
        elevated = next(a for a in alerts if a["type"] == "off_platform_handle")
        assert elevated["subject_username"] == "xX_DarkTrader_Xx"
        assert any("character substitutions" in f for f in elevated["facts"])
        assert {e["term"] for e in elevated["explainers"]} & {"Discord", "profile"}

        # 5. Evidence was captured automatically (data snapshot at minimum;
        #    profile screenshot depends on network, degrades gracefully).
        evidence = client.get(f"/children/{child_id}/evidence").json()["evidence"]
        assert any(e["kind"] == "data_snapshot" for e in evidence)

        # 6. Parent adds a chat screenshot from the child's iPad.
        upload = client.post(
            f"/children/{child_id}/evidence/upload",
            files={"file": ("chat.png", b"\x89PNG synthetic", "image/png")},
            data={"note": "Chat asking Emma to install Discord"})
        assert upload.status_code == 201

        # 7. Incident report is complete and readable by a novice/officer.
        report = client.get(f"/children/{child_id}/report?format=md").text
        for required in ("@emma_playz2016", "@xX_DarkTrader_Xx",
                         "For readers new to Roblox", "Terms used in this report",
                         "report.cybertip.org", "SHA-256",
                         "Chat asking Emma to install Discord"):
            assert required in report, f"report missing: {required}"

        # 8. Parent confirms it was real -> heightened monitoring kicks in.
        client.post(f"/alerts/{elevated['id']}/feedback", json={"verdict": "confirmed"})

        # 9. Case closed: unlink erases everything, including evidence files.
        evidence_id = evidence[0]["id"]
        assert client.delete(f"/children/{child_id}").status_code == 204
        assert client.get("/children").json() == []
        assert client.get(f"/evidence/{evidence_id}/file").status_code == 404


class TestEdgeCases:
    def test_unicode_and_hostile_bio_content(self, world):
        client, fake = world
        child_id = link(client)
        fake.friends[101].append(make_profile(
            user_id=301, username="weird_bio_kid",
            description=("émojis 🎮🎮 ‮ reversed \x00 null "
                         "<script>alert(1)</script> " + "长" * 500),
            age_years=0.5, friend_count=10))
        resp = client.post(f"/children/{child_id}/refresh")
        assert resp.status_code == 200  # never crashes on hostile input

        # HTML report escapes hostile content
        html = client.get(f"/children/{child_id}/report").text
        assert "<script>alert(1)</script>" not in html

    def test_username_validation(self, world):
        client, _ = world
        assert client.post("/children", json={
            "roblox_username": "ab",  # too short
            "parent_attestation": True, "parent_name": "P"}).status_code == 422
        assert client.post("/children", json={
            "roblox_username": "no_such_kid_9999",
            "parent_attestation": True, "parent_name": "P"}).status_code == 404

    def test_friend_list_shrinks_no_crash(self, world):
        client, fake = world
        child_id = link(client)
        client.post(f"/children/{child_id}/refresh")
        fake.friends[101] = []  # child unfriended everyone
        assert client.post(f"/children/{child_id}/refresh").status_code == 200

    def test_double_feedback_and_unknown_ids(self, world):
        client, fake = world
        child_id = link(client)
        fake.friends[101].append(make_profile(user_id=400, username="s",
                                              description="snap: xyz"))
        client.post(f"/children/{child_id}/refresh")
        alert_id = client.get(f"/children/{child_id}/alerts").json()["alerts"][0]["id"]
        assert client.post(f"/alerts/{alert_id}/feedback",
                           json={"verdict": "dismissed"}).status_code == 200
        # changing your mind is allowed
        assert client.post(f"/alerts/{alert_id}/feedback",
                           json={"verdict": "confirmed"}).status_code == 200
        assert client.get("/children/9999/alerts").status_code == 404
        assert client.post("/children/9999/refresh").status_code == 404

    def test_oversized_upload_rejected(self, world):
        client, _ = world
        child_id = link(client)
        big = b"x" * (15 * 1024 * 1024 + 1)
        resp = client.post(f"/children/{child_id}/evidence/upload",
                           files={"file": ("big.png", big, "image/png")})
        assert resp.status_code == 413


class TestPerformance:
    def test_large_friend_list_snapshot_budget(self, world):
        """A 250-friend account (heavy but realistic) must poll fast; the
        fake client removes network so this measures our own pipeline."""
        client, fake = world
        child_id = link(client)
        fake.friends[101] = [
            make_profile(user_id=1000 + i, username=f"classmate_{i}",
                         age_years=0.5 + (i % 20) / 10, friend_count=20 + i % 50)
            for i in range(250)
        ]
        start = time.monotonic()
        resp = client.post(f"/children/{child_id}/refresh")
        elapsed = time.monotonic() - start
        assert resp.status_code == 200
        assert elapsed < 5.0, f"snapshot pipeline too slow: {elapsed:.2f}s"

        # Second poll (no changes) must be near-instant and alert-free.
        start = time.monotonic()
        assert client.post(f"/children/{child_id}/refresh").json()["new_alerts"] == []
        assert time.monotonic() - start < 2.0


class TestAuth:
    def test_token_required_when_configured(self, tmp_path):
        fake = FakeRobloxClient()
        fake.add_user(make_profile(user_id=1, username="kid"))
        settings = Settings(db_path=str(tmp_path / "auth.db"),
                            watchlist_path=str(tmp_path / "missing.json"),
                            api_token="s3cret-token")
        app = create_app(settings=settings, client=fake, start_monitor=False)
        with TestClient(app) as client:
            # health stays open for load balancers
            assert client.get("/health").status_code == 200
            # everything else requires the bearer token
            assert client.get("/children").status_code == 401
            assert client.get("/children",
                              headers={"Authorization": "Bearer wrong"}).status_code == 401
            assert client.get(
                "/children",
                headers={
                    "Authorization": "Bearer s3cret-token",
                    "X-RobloxGuard-Client-ID": "11111111-1111-4111-8111-111111111111",
                }).status_code == 200
