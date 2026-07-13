#!/usr/bin/env python3
"""Post-deploy smoke test for a RobloxGuard backend.

Runs the critical path against a RUNNING server and prints PASS/FAIL per
step. Uses Roblox's own official accounts (user 'Roblox', 'builderman') as
the linked "child" — never a real child's account.

Usage:
    RG_SMOKE_URL=https://api.example.com RG_API_TOKEN=... python scripts/smoke_test.py

Exit code 0 = all steps passed; 1 = something failed.
"""

import os
import sys

import httpx

BASE = os.environ.get("RG_SMOKE_URL", "http://localhost:8000").rstrip("/")
TOKEN = os.environ.get("RG_API_TOKEN", "")
# Official Roblox-owned accounts — safe, public, and definitely not children.
SMOKE_USERNAME = os.environ.get("RG_SMOKE_USERNAME", "builderman")

results: list[tuple[str, bool, str]] = []


def step(name: str, ok: bool, detail: str = "") -> None:
    results.append((name, ok, detail))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


def main() -> int:
    headers = {"Authorization": f"Bearer {TOKEN}"} if TOKEN else {}
    client = httpx.Client(base_url=BASE, headers=headers, timeout=60.0)

    # 1. Health + threat feed loaded
    try:
        health = client.get("/health").json()
        step("health", health.get("status") == "ok",
             f"feed v{health.get('threat_feed', {}).get('version')}")
    except Exception as error:
        step("health", False, str(error))
        return finish()

    # 2. Auth is actually enforced (only meaningful when a token is set)
    if TOKEN:
        anon = httpx.get(f"{BASE}/children", timeout=30.0)
        step("auth enforced", anon.status_code == 401, f"got {anon.status_code}")

    # 3. Education + glossary served
    education = client.get("/education").json()
    step("education content", bool(education.get("dangers"))
         and bool(education.get("glossary")))

    # 4. Live Roblox integration: link an official Roblox account
    resp = client.post("/children", json={
        "roblox_username": SMOKE_USERNAME,
        "parent_attestation": True,
        "parent_name": "Smoke Test",
    })
    if resp.status_code == 409:  # left over from a previous run — find it
        child = next(c for c in client.get("/children").json()
                     if c["roblox_username"].lower() == SMOKE_USERNAME.lower())
        child_id = child["id"]
        step("link account", True, "already linked")
    elif resp.status_code == 201:
        child_id = resp.json()["id"]
        step("link account", True, f"@{SMOKE_USERNAME}")
    else:
        step("link account", False,
             f"{resp.status_code}: {resp.text[:120]} — is roblox.com reachable?")
        return finish()

    try:
        # 5. Live snapshot poll (friends + presence via real Roblox API)
        refresh = client.post(f"/children/{child_id}/refresh")
        step("live snapshot poll", refresh.status_code == 200,
             f"{len(refresh.json().get('new_alerts', []))} alerts")

        # 6. Alerts endpoint with explainers
        alerts = client.get(f"/children/{child_id}/alerts").json()["alerts"]
        step("alerts + explainers", all("explainers" in a for a in alerts),
             f"{len(alerts)} open")

        # 7. Evidence upload + hash + download round-trip
        up = client.post(f"/children/{child_id}/evidence/upload",
                         files={"file": ("smoke.png", b"\x89PNG smoke", "image/png")},
                         data={"note": "smoke test artifact"})
        ok = up.status_code == 201 and len(up.json().get("sha256", "")) == 64
        step("evidence upload", ok)
        listing = client.get(f"/children/{child_id}/evidence").json()["evidence"]
        item = next(e for e in listing if e["kind"] == "parent_upload")
        down = client.get(f"/evidence/{item['id']}/file")
        step("evidence download", down.content == b"\x89PNG smoke")

        # 8. Incident report renders (both formats)
        html = client.get(f"/children/{child_id}/report")
        md = client.get(f"/children/{child_id}/report?format=md")
        step("report html", html.status_code == 200
             and "For readers new to Roblox" in html.text)
        step("report markdown", "report.cybertip.org" in md.text)

        # 9. Intel status readable
        intel = client.get("/intel/runs").json()
        step("intel status", "analyzer" in intel,
             f"analyzer={intel.get('analyzer')}, sources={intel.get('sources_configured')}")

        # 10. Bug report round-trip (the durable bug log a parent's
        # "Report a Bug" button in Settings writes to)
        bug = client.post("/support/bug-report", json={
            "summary": "[smoke_test.py] automated bug log check",
            "details": "Posted by scripts/smoke_test.py; safe to ignore/delete.",
            "app_version": "smoke-test",
        })
        bug_ok = bug.status_code == 201 and "support_email" in bug.json()
        step("bug report submitted", bug_ok, f"emailed={bug.json().get('emailed')}"
             if bug_ok else f"{bug.status_code}: {bug.text[:120]}")
        reports = client.get("/support/bug-reports?limit=1").json().get("reports", [])
        step("bug log readable", bool(reports) and reports[0]["source"] == "customer")

        # 11. Push notification device registration round-trip
        smoke_token = "smoke" + "0" * 59
        reg = client.post("/devices/register", json={"token": smoke_token, "platform": "ios"})
        status = client.get("/notifications/status").json()
        step("device registration", reg.status_code == 201
             and status.get("registered_devices", 0) >= 1,
             f"APNs configured={status.get('configured')}")

        # 12. If a real APNs key is configured, actually fire a push — this
        # will fail against the fake "smoke" token above (not a real device),
        # so only check that APNs was *reachable*, not that delivery succeeded.
        if status.get("configured"):
            test_push = client.post("/notifications/test")
            step("push reachable", test_push.status_code == 200,
                 f"{test_push.json()}" if test_push.status_code == 200 else test_push.text[:120])
        else:
            step("push reachable", True, "skipped — APNs not configured on this deployment")

        client.delete(f"/devices/{smoke_token}")
    finally:
        # 13. Erasure — always clean up the smoke child
        deleted = client.delete(f"/children/{child_id}")
        step("full erasure", deleted.status_code == 204)

    return finish()


def finish() -> int:
    failed = [name for name, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed"
          + (f" — FAILED: {', '.join(failed)}" if failed else " — smoke test green"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
