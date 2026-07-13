"""Bug log (db.bug_reports) and the /support/bug-report endpoint."""

import pytest
from fastapi.testclient import TestClient

from app import mailer
from app.config import Settings
from app.db import Database
from app.main import create_app

from .conftest import FakeRobloxClient


# -- db layer -----------------------------------------------------------------

def test_add_and_get_bug_report(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    report_id = db.add_bug_report(
        source="customer", summary="Alerts never refresh",
        details="Pull to refresh spins forever.",
        context={"app_version": "1.0", "platform": "iOS 17.4"},
        contact_email="parent@example.com",
    )
    report = db.get_bug_report(report_id)
    assert report["source"] == "customer"
    assert report["summary"] == "Alerts never refresh"
    assert report["context"] == {"app_version": "1.0", "platform": "iOS 17.4"}
    assert report["contact_email"] == "parent@example.com"
    assert report["emailed"] is False


def test_add_bug_report_rejects_unknown_source(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    with pytest.raises(ValueError):
        db.add_bug_report(source="carrier_pigeon", summary="x")


def test_list_bug_reports_newest_first(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    first = db.add_bug_report(source="customer", summary="first")
    second = db.add_bug_report(source="backend_error", summary="second")
    reports = db.list_bug_reports()
    assert [r["id"] for r in reports] == [second, first]


def test_mark_bug_report_emailed(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    report_id = db.add_bug_report(source="customer", summary="x")
    db.mark_bug_report_emailed(report_id)
    assert db.get_bug_report(report_id)["emailed"] is True


def test_log_backend_error_convenience(tmp_path):
    db = Database(str(tmp_path / "t.db"))
    report_id = db.log_backend_error("KeyError on /children/9", "traceback here",
                                     context={"path": "/children/9"})
    report = db.get_bug_report(report_id)
    assert report["source"] == "backend_error"
    assert report["context"]["path"] == "/children/9"


# -- mailer (no-op unless SMTP is configured) ----------------------------------

def test_mailer_noop_without_smtp_host():
    settings = Settings(smtp_host="", support_email="mvalasek@gmail.com")
    sent = mailer.send_bug_report_email(settings, {
        "id": 1, "source": "customer", "created_at": "now",
        "summary": "x", "details": "", "context": {},
    })
    assert sent is False


def test_mailer_sends_when_smtp_configured(monkeypatch):
    sent_messages = []

    class FakeSMTP:
        def __init__(self, host, port, timeout=10):
            sent_messages.append({"host": host, "port": port})

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def starttls(self):
            pass

        def login(self, user, password):
            pass

        def send_message(self, msg):
            sent_messages.append(msg)

    monkeypatch.setattr(mailer.smtplib, "SMTP", FakeSMTP)
    settings = Settings(smtp_host="smtp.example.com", smtp_user="bot@example.com",
                        smtp_password="secret", support_email="mvalasek@gmail.com")
    sent = mailer.send_bug_report_email(settings, {
        "id": 7, "source": "customer", "created_at": "now",
        "summary": "Crashes on link", "details": "steps...",
        "context": {"app_version": "1.0"}, "contact_email": "parent@example.com",
    })
    assert sent is True
    assert sent_messages[0]["host"] == "smtp.example.com"
    email = sent_messages[1]
    assert email["To"] == "mvalasek@gmail.com"
    assert email["Reply-To"] == "parent@example.com"
    assert "Crashes on link" in email["Subject"]


def test_mailer_failure_does_not_raise(monkeypatch):
    class ExplodingSMTP:
        def __init__(self, *a, **k):
            raise ConnectionRefusedError("no route to host")

    monkeypatch.setattr(mailer.smtplib, "SMTP", ExplodingSMTP)
    settings = Settings(smtp_host="smtp.example.com", support_email="mvalasek@gmail.com")
    sent = mailer.send_bug_report_email(settings, {
        "id": 1, "source": "customer", "created_at": "now", "summary": "x",
    })
    assert sent is False


# -- API endpoints --------------------------------------------------------------

@pytest.fixture
def api(tmp_path):
    fake = FakeRobloxClient()
    settings = Settings(db_path=str(tmp_path / "api.db"),
                        watchlist_path=str(tmp_path / "missing.json"),
                        smtp_host="")  # no SMTP in tests — bug log persistence only
    app = create_app(settings=settings, client=fake, start_monitor=False)
    with TestClient(app) as client:
        yield client


def test_submit_bug_report(api):
    resp = api.post("/support/bug-report", json={
        "summary": "Evidence upload fails",
        "details": "Spinner never stops on a 4MB PNG.",
        "contact_email": "parent@example.com",
        "app_version": "1.0.0",
        "platform": "iOS 17.5, iPhone 15",
    })
    assert resp.status_code == 201
    body = resp.json()
    assert body["emailed"] is False  # no SMTP configured in this test
    assert body["support_email"] == "mvalasek@gmail.com"

    listing = api.get("/support/bug-reports").json()["reports"]
    assert len(listing) == 1
    assert listing[0]["summary"] == "Evidence upload fails"
    assert listing[0]["source"] == "customer"
    assert listing[0]["context"]["platform"] == "iOS 17.5, iPhone 15"


def test_submit_bug_report_requires_summary(api):
    resp = api.post("/support/bug-report", json={"summary": ""})
    assert resp.status_code == 422


def test_submit_bug_report_optional_fields_default(api):
    resp = api.post("/support/bug-report", json={"summary": "App crashed"})
    assert resp.status_code == 201
    listing = api.get("/support/bug-reports").json()["reports"]
    assert listing[0]["contact_email"] == ""


def test_bug_reports_listing_respects_limit(api):
    for i in range(5):
        api.post("/support/bug-report", json={"summary": f"bug {i}"})
    reports = api.get("/support/bug-reports?limit=2").json()["reports"]
    assert len(reports) == 2
    # newest first
    assert reports[0]["summary"] == "bug 4"
