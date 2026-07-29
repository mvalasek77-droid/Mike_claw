"""FastAPI application — the API the parent's iOS app talks to.

Consent model: linking a child requires an explicit parental attestation in
the request body. The attestation (who, when) is stored with the child record
and unlinking erases all derived data, matching COPPA's consent + deletion
expectations.
"""

import logging
import os
import traceback
from contextlib import asynccontextmanager
from typing import Optional
from uuid import UUID

import hmac

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, PlainTextResponse
from pydantic import BaseModel, Field

from . import mailer
from .config import Settings, settings as default_settings
from .db import Database
from .education import education_payload
from .evidence import EvidenceVault
from .glossary import explain as glossary_explain
from .intel import IntelService
from .logging_config import configure_logging
from .monitor import Monitor
from .push import APNsService
from .report import build_report_html, build_report_markdown
from .resources import RESOURCES
from .roblox_client import RobloxClient

MAX_UPLOAD_BYTES = 15 * 1024 * 1024

log = logging.getLogger("roblox_guard.api")


class LinkChildRequest(BaseModel):
    roblox_username: str = Field(min_length=3, max_length=20)
    # Explicit parental attestation — the iOS app shows the full consent text
    # and only sets this true after the parent confirms.
    parent_attestation: bool
    parent_name: str = Field(min_length=1, max_length=100)


class ChildResponse(BaseModel):
    id: int
    roblox_user_id: int
    roblox_username: str
    display_name: str
    last_poll_at: Optional[str] = None
    last_poll_status: str = ""
    report_access_token: str


class FeedbackRequest(BaseModel):
    verdict: str = Field(pattern="^(confirmed|dismissed)$")


class BugReportRequest(BaseModel):
    summary: str = Field(min_length=1, max_length=200)
    details: str = Field(default="", max_length=5000)
    contact_email: str = Field(default="", max_length=200)
    app_version: str = Field(default="", max_length=40)
    platform: str = Field(default="", max_length=40)


class DeviceRegisterRequest(BaseModel):
    token: str = Field(min_length=16, max_length=200)
    platform: str = Field(default="ios", max_length=20)


def create_app(settings: Optional[Settings] = None,
               client: Optional[RobloxClient] = None,
               start_monitor: bool = True) -> FastAPI:
    settings = settings or default_settings
    configure_logging(settings.log_dir)
    db = Database(settings.db_path)
    roblox = client or RobloxClient(spacing_seconds=settings.request_spacing_seconds)
    evidence_dir = os.environ.get(
        "RG_EVIDENCE_DIR", os.path.join(os.path.dirname(settings.db_path) or ".", "evidence"))
    vault = EvidenceVault(db, evidence_dir)
    push = APNsService(settings)
    monitor = Monitor(db, roblox, settings, vault=vault, push=push)
    intel = IntelService(db, monitor.feeds)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if start_monitor:
            monitor.start()
            intel.start()
        yield
        if start_monitor:
            await intel.stop()
            await monitor.stop()
        await roblox.aclose()

    async def require_auth(request: Request):
        """Authenticate the app and bind each request to one installation.

        The API bearer token limits generic abuse; the random per-installation
        UUID provides tenant isolation. Report/evidence share links carry a
        narrower per-child token and validate it inside their route.
        """
        if request.url.path == "/health":
            return

        share_path = (
            request.url.path.startswith("/children/")
            and request.url.path.endswith("/report")
        ) or (
            request.url.path.startswith("/evidence/")
            and request.url.path.endswith("/file")
        )
        if share_path and request.query_params.get("share_token"):
            return

        header = request.headers.get("Authorization", "")
        if settings.admin_token:
            expected_admin = f"Bearer {settings.admin_token}"
            if hmac.compare_digest(header.encode(), expected_admin.encode()):
                request.state.client_id = "operator"
                return

        if settings.api_token:
            expected = f"Bearer {settings.api_token}"
            if not hmac.compare_digest(header.encode(), expected.encode()):
                raise HTTPException(status_code=401, detail="Missing or invalid API token.")

        raw_client_id = request.headers.get("X-RobloxGuard-Client-ID", "")
        if not raw_client_id:
            if settings.api_token:
                raise HTTPException(status_code=400, detail="Missing installation identifier.")
            request.state.client_id = "local-development"
            return
        try:
            request.state.client_id = str(UUID(raw_client_id))
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid installation identifier.")

    async def require_admin(request: Request):
        """Protect operator-wide endpoints with a credential not in the app."""
        if not settings.api_token and not settings.admin_token:
            return
        if not settings.admin_token:
            raise HTTPException(status_code=503, detail="Operator access is not configured.")
        header = request.headers.get("Authorization", "")
        expected = f"Bearer {settings.admin_token}"
        if not hmac.compare_digest(header.encode(), expected.encode()):
            raise HTTPException(status_code=401, detail="Missing or invalid operator token.")

    def client_id(request: Request) -> str:
        value = getattr(request.state, "client_id", None)
        if not value or value == "operator":
            raise HTTPException(status_code=400, detail="Missing installation identifier.")
        return value

    app = FastAPI(title="RobloxGuard", version="0.1.0", lifespan=lifespan,
                  dependencies=[Depends(require_auth)])
    app.state.db = db
    app.state.monitor = monitor
    app.state.roblox = roblox

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        """Every unhandled error is logged AND persisted to the bug log.

        The response never leaks internals to the client; the traceback goes
        to the rotating log file and the bug_reports table (visible at
        GET /support/bug-reports) so a crash is discoverable without a parent
        having to notice and report it themselves.
        """
        log.exception("Unhandled error on %s %s", request.method, request.url.path)
        try:
            db.log_backend_error(
                f"{type(exc).__name__} on {request.method} {request.url.path}",
                traceback.format_exc(),
                context={"method": request.method, "path": request.url.path},
            )
        except Exception:
            log.exception("Failed to persist backend_error bug report")
        return JSONResponse(status_code=500, content={"detail": "Internal server error."})

    @app.get("/health")
    async def health():
        return {"status": "ok", "threat_feed": monitor.feeds.status()}

    @app.get("/threat-feed/status")
    async def threat_feed_status():
        return monitor.feeds.status()

    @app.post("/children", response_model=ChildResponse, status_code=201)
    async def link_child(req: LinkChildRequest, request: Request):
        owner = client_id(request)
        if not req.parent_attestation:
            raise HTTPException(
                status_code=422,
                detail="Parental attestation is required to link a child account.",
            )
        try:
            user_id = await roblox.resolve_username(req.roblox_username)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Roblox API unavailable; try again.")
        if user_id is None:
            raise HTTPException(status_code=404, detail="No Roblox account with that username.")
        if db.get_child_by_roblox_id(user_id, client_id=owner):
            raise HTTPException(status_code=409, detail="That account is already linked.")
        try:
            profile = await roblox.get_profile(user_id)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Roblox API unavailable; try again.")
        child_id = db.add_child(
            user_id,
            profile.username,
            profile.display_name,
            req.parent_name,
            client_id=owner,
        )
        child = db.get_child(child_id, client_id=owner)
        return ChildResponse(id=child_id, roblox_user_id=user_id,
                             roblox_username=profile.username,
                             display_name=profile.display_name,
                             report_access_token=child["share_token"])

    @app.get("/children", response_model=list[ChildResponse])
    async def list_children(request: Request):
        owner = client_id(request)
        return [ChildResponse(id=c["id"], roblox_user_id=c["roblox_user_id"],
                              roblox_username=c["roblox_username"],
                              display_name=c["display_name"],
                              last_poll_at=c.get("last_poll_at"),
                              last_poll_status=c.get("last_poll_status") or "",
                              report_access_token=c["share_token"])
                for c in db.list_children(owner)]

    @app.delete("/children/{child_id}", status_code=204)
    async def unlink_child(child_id: int, request: Request):
        owner = client_id(request)
        if not db.get_child(child_id, client_id=owner):
            raise HTTPException(status_code=404, detail="Unknown child.")
        # Full erasure includes evidence files on disk, not just DB rows.
        for item in db.list_evidence(child_id):
            try:
                os.remove(item["path"])
            except OSError:
                pass
        db.remove_child(child_id, client_id=owner)

    @app.post("/children/{child_id}/refresh")
    async def refresh_child(child_id: int, request: Request):
        owner = client_id(request)
        if not db.get_child(child_id, client_id=owner):
            raise HTTPException(status_code=404, detail="Unknown child.")
        try:
            created = await monitor.poll_child(child_id)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Roblox API unavailable; try again.")
        return {"new_alerts": created}

    @app.get("/children/{child_id}/alerts")
    async def list_alerts(child_id: int, request: Request,
                          include_acknowledged: bool = False):
        owner = client_id(request)
        if not db.get_child(child_id, client_id=owner):
            raise HTTPException(status_code=404, detail="Unknown child.")
        alerts = db.list_alerts(child_id, include_acknowledged)
        # Attach plain-language definitions for every Roblox term an alert
        # uses, so parents new to Roblox never hit unexplained jargon.
        for alert in alerts:
            alert["explainers"] = glossary_explain(
                alert["title"], alert["guidance"], *alert["facts"],
                feed=monitor.feeds.feed)
        return {"alerts": alerts}

    @app.post("/alerts/{alert_id}/acknowledge")
    async def acknowledge(alert_id: int, request: Request):
        if not db.acknowledge_alert(alert_id, client_id=client_id(request)):
            raise HTTPException(status_code=404, detail="Unknown alert.")
        return {"acknowledged": True}

    @app.post("/alerts/{alert_id}/feedback")
    async def alert_feedback(alert_id: int, req: FeedbackRequest,
                             request: Request):
        """Parent verdict on an alert; drives adaptive tuning.

        'dismissed' x3 (with no confirms) mutes that signal type for that
        child at info/watch level; any 'confirmed' switches the child to
        heightened monitoring. Elevated alerts are never muted.
        """
        if not db.set_alert_feedback(
            alert_id, req.verdict, client_id=client_id(request)
        ):
            raise HTTPException(status_code=404, detail="Unknown alert.")
        return {"feedback": req.verdict}

    @app.get("/resources")
    async def resources():
        return {"resources": RESOURCES}

    @app.get("/education")
    async def education():
        return education_payload(monitor.feeds.feed)

    # -- daily threat intelligence --------------------------------------------

    @app.get("/intel/runs")
    async def intel_runs():
        return {"runs": db.list_intel_runs(),
                "analyzer": intel.analyzer.name,
                "auto_apply": intel.auto_apply,
                "sources_configured": len(intel.sources)}

    @app.post("/intel/run", dependencies=[Depends(require_admin)])
    async def intel_run_now():
        """Run the daily threat search immediately (also fires on schedule)."""
        if not intel.sources:
            raise HTTPException(status_code=409,
                                detail="No intel sources configured (data/intel_sources.json).")
        return await intel.run_once()

    # -- bug reports -----------------------------------------------------------

    @app.post("/support/bug-report", status_code=201)
    async def submit_bug_report(payload: BugReportRequest, request: Request):
        """Customer-facing 'Report a Bug' entry point (see Settings in the app).

        Always persisted to the durable bug log first; email relay to
        RG_SUPPORT_EMAIL (default mvalasek@gmail.com) is attempted on a
        best-effort basis afterward and never blocks the write.
        """
        report_id = db.add_bug_report(
            source="customer",
            summary=payload.summary,
            details=payload.details,
            context={"app_version": payload.app_version, "platform": payload.platform},
            contact_email=payload.contact_email,
            client_id=client_id(request),
        )
        report = db.get_bug_report(report_id)
        emailed = mailer.send_bug_report_email(settings, report)
        if emailed:
            db.mark_bug_report_emailed(report_id)
        return {"id": report_id, "emailed": emailed, "support_email": settings.support_email}

    @app.get("/support/bug-reports", dependencies=[Depends(require_admin)])
    async def list_bug_reports(limit: int = 100):
        """Operator view of the bug log — customer reports and backend errors."""
        return {"reports": db.list_bug_reports(limit=limit)}

    # -- push notifications ------------------------------------------------------

    @app.post("/devices/register", status_code=201)
    async def register_device(payload: DeviceRegisterRequest, request: Request):
        """Called once the app has an APNs device token (Settings > Notifications).

        Device tokens are scoped to the same installation as child records.
        """
        db.register_device_token(
            payload.token, payload.platform, client_id=client_id(request)
        )
        return {"registered": True}

    @app.delete("/devices/{token}", status_code=204)
    async def unregister_device(token: str, request: Request):
        db.remove_device_token(token, client_id=client_id(request))

    @app.get("/notifications/status")
    async def notifications_status(request: Request):
        owner = client_id(request)
        return {"configured": push.configured, "sandbox": settings.apns_use_sandbox,
                "registered_devices": len(db.list_device_tokens(owner))}

    @app.post("/notifications/test")
    async def send_test_notification(request: Request):
        """Fires one push to this installation's registered devices on demand.

        For testing: without this, the only way to see a real push is to
        wait for monitor.py to detect an actual risky signal on a real
        Roblox account, which is slow and hard to reproduce on purpose.
        """
        if not push.configured:
            raise HTTPException(status_code=409,
                                detail="APNs not configured — set RG_APNS_KEY_* env vars first.")
        owner = client_id(request)
        if not db.list_device_tokens(owner):
            raise HTTPException(status_code=409,
                                detail="No devices registered — enable notifications in the app first.")
        return await push.send_to_all(
            db,
            title="RobloxGuard test",
            body="If you see this, push notifications are working.",
            client_id=owner,
        )

    # -- evidence ------------------------------------------------------------

    @app.get("/children/{child_id}/evidence")
    async def list_evidence(child_id: int, request: Request):
        owner = client_id(request)
        if not db.get_child(child_id, client_id=owner):
            raise HTTPException(status_code=404, detail="Unknown child.")
        items = db.list_evidence(child_id)
        for item in items:
            item["filename"] = os.path.basename(item.pop("path"))
        return {"evidence": items}

    @app.get("/evidence/{evidence_id}/file")
    async def get_evidence_file(evidence_id: int, request: Request,
                                share_token: Optional[str] = None):
        item = (
            db.get_evidence(evidence_id, share_token=share_token)
            if share_token
            else db.get_evidence(evidence_id, client_id=client_id(request))
        )
        if not item or not os.path.exists(item["path"]):
            raise HTTPException(status_code=404, detail="Unknown evidence.")
        return FileResponse(item["path"], filename=os.path.basename(item["path"]))

    @app.post("/children/{child_id}/evidence/upload", status_code=201)
    async def upload_evidence(child_id: int, request: Request,
                              file: UploadFile = File(...),
                              note: str = Form("")):
        """Store a screenshot the parent took on the child's device.

        The iOS upload screen shows the CSAM warning before this is called;
        the server cannot inspect content, so the guardrail is procedural.
        """
        owner = client_id(request)
        if not db.get_child(child_id, client_id=owner):
            raise HTTPException(status_code=404, detail="Unknown child.")
        content = await file.read()
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="File too large (15 MB max).")
        try:
            evidence_id = vault.store_parent_upload(
                child_id, file.filename or "upload.png", content, note=note)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc))
        item = db.get_evidence(evidence_id)
        return {"id": evidence_id, "sha256": item["sha256"],
                "captured_at": item["captured_at"]}

    # -- incident report -----------------------------------------------------

    @app.get("/children/{child_id}/report")
    async def incident_report(child_id: int, request: Request,
                              format: str = "html",
                              share_token: Optional[str] = None):
        child = (
            db.get_child(child_id, share_token=share_token)
            if share_token
            else db.get_child(child_id, client_id=client_id(request))
        )
        if not child:
            raise HTTPException(status_code=404, detail="Unknown child.")
        alerts = db.list_alerts(child_id, include_acknowledged=True)
        evidence = db.list_evidence(child_id)
        if format == "md":
            return PlainTextResponse(
                build_report_markdown(child, alerts, evidence, feed=monitor.feeds.feed),
                media_type="text/markdown")
        return HTMLResponse(build_report_html(child, alerts, evidence,
                                              feed=monitor.feeds.feed))

    return app


app = create_app()
