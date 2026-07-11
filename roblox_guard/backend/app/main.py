"""FastAPI application — the API the parent's iOS app talks to.

Consent model: linking a child requires an explicit parental attestation in
the request body. The attestation (who, when) is stored with the child record
and unlinking erases all derived data, matching COPPA's consent + deletion
expectations.
"""

import logging
import os
from contextlib import asynccontextmanager
from typing import Optional

import httpx
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse
from pydantic import BaseModel, Field

from .config import Settings, settings as default_settings
from .db import Database
from .education import education_payload
from .evidence import EvidenceVault
from .glossary import explain as glossary_explain
from .monitor import Monitor
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


class FeedbackRequest(BaseModel):
    verdict: str = Field(pattern="^(confirmed|dismissed)$")


def create_app(settings: Optional[Settings] = None,
               client: Optional[RobloxClient] = None,
               start_monitor: bool = True) -> FastAPI:
    settings = settings or default_settings
    db = Database(settings.db_path)
    roblox = client or RobloxClient(spacing_seconds=settings.request_spacing_seconds)
    evidence_dir = os.environ.get(
        "RG_EVIDENCE_DIR", os.path.join(os.path.dirname(settings.db_path) or ".", "evidence"))
    vault = EvidenceVault(db, evidence_dir)
    monitor = Monitor(db, roblox, settings, vault=vault)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        if start_monitor:
            monitor.start()
        yield
        if start_monitor:
            await monitor.stop()
        await roblox.aclose()

    app = FastAPI(title="RobloxGuard", version="0.1.0", lifespan=lifespan)
    app.state.db = db
    app.state.monitor = monitor
    app.state.roblox = roblox

    @app.get("/health")
    async def health():
        return {"status": "ok", "threat_feed": monitor.feeds.status()}

    @app.get("/threat-feed/status")
    async def threat_feed_status():
        return monitor.feeds.status()

    @app.post("/children", response_model=ChildResponse, status_code=201)
    async def link_child(req: LinkChildRequest):
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
        if db.get_child_by_roblox_id(user_id):
            raise HTTPException(status_code=409, detail="That account is already linked.")
        try:
            profile = await roblox.get_profile(user_id)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Roblox API unavailable; try again.")
        child_id = db.add_child(user_id, profile.username, profile.display_name, req.parent_name)
        return ChildResponse(id=child_id, roblox_user_id=user_id,
                             roblox_username=profile.username,
                             display_name=profile.display_name)

    @app.get("/children", response_model=list[ChildResponse])
    async def list_children():
        return [ChildResponse(id=c["id"], roblox_user_id=c["roblox_user_id"],
                              roblox_username=c["roblox_username"],
                              display_name=c["display_name"],
                              last_poll_at=c.get("last_poll_at"),
                              last_poll_status=c.get("last_poll_status") or "")
                for c in db.list_children()]

    @app.delete("/children/{child_id}", status_code=204)
    async def unlink_child(child_id: int):
        if not db.get_child(child_id):
            raise HTTPException(status_code=404, detail="Unknown child.")
        # Full erasure includes evidence files on disk, not just DB rows.
        for item in db.list_evidence(child_id):
            try:
                os.remove(item["path"])
            except OSError:
                pass
        db.remove_child(child_id)

    @app.post("/children/{child_id}/refresh")
    async def refresh_child(child_id: int):
        if not db.get_child(child_id):
            raise HTTPException(status_code=404, detail="Unknown child.")
        try:
            created = await monitor.poll_child(child_id)
        except httpx.HTTPError:
            raise HTTPException(status_code=502, detail="Roblox API unavailable; try again.")
        return {"new_alerts": created}

    @app.get("/children/{child_id}/alerts")
    async def list_alerts(child_id: int, include_acknowledged: bool = False):
        if not db.get_child(child_id):
            raise HTTPException(status_code=404, detail="Unknown child.")
        alerts = db.list_alerts(child_id, include_acknowledged)
        # Attach plain-language definitions for every Roblox term an alert
        # uses, so parents new to Roblox never hit unexplained jargon.
        for alert in alerts:
            alert["explainers"] = glossary_explain(
                alert["title"], alert["guidance"], *alert["facts"])
        return {"alerts": alerts}

    @app.post("/alerts/{alert_id}/acknowledge")
    async def acknowledge(alert_id: int):
        if not db.acknowledge_alert(alert_id):
            raise HTTPException(status_code=404, detail="Unknown alert.")
        return {"acknowledged": True}

    @app.post("/alerts/{alert_id}/feedback")
    async def alert_feedback(alert_id: int, req: FeedbackRequest):
        """Parent verdict on an alert; drives adaptive tuning.

        'dismissed' x3 (with no confirms) mutes that signal type for that
        child at info/watch level; any 'confirmed' switches the child to
        heightened monitoring. Elevated alerts are never muted.
        """
        if not db.set_alert_feedback(alert_id, req.verdict):
            raise HTTPException(status_code=404, detail="Unknown alert.")
        return {"feedback": req.verdict}

    @app.get("/resources")
    async def resources():
        return {"resources": RESOURCES}

    @app.get("/education")
    async def education():
        return education_payload()

    # -- evidence ------------------------------------------------------------

    @app.get("/children/{child_id}/evidence")
    async def list_evidence(child_id: int):
        if not db.get_child(child_id):
            raise HTTPException(status_code=404, detail="Unknown child.")
        items = db.list_evidence(child_id)
        for item in items:
            item["filename"] = os.path.basename(item.pop("path"))
        return {"evidence": items}

    @app.get("/evidence/{evidence_id}/file")
    async def get_evidence_file(evidence_id: int):
        item = db.get_evidence(evidence_id)
        if not item or not os.path.exists(item["path"]):
            raise HTTPException(status_code=404, detail="Unknown evidence.")
        return FileResponse(item["path"], filename=os.path.basename(item["path"]))

    @app.post("/children/{child_id}/evidence/upload", status_code=201)
    async def upload_evidence(child_id: int, file: UploadFile = File(...),
                              note: str = Form("")):
        """Store a screenshot the parent took on the child's device.

        The iOS upload screen shows the CSAM warning before this is called;
        the server cannot inspect content, so the guardrail is procedural.
        """
        if not db.get_child(child_id):
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
    async def incident_report(child_id: int, format: str = "html"):
        child = db.get_child(child_id)
        if not child:
            raise HTTPException(status_code=404, detail="Unknown child.")
        alerts = db.list_alerts(child_id, include_acknowledged=True)
        evidence = db.list_evidence(child_id)
        if format == "md":
            return PlainTextResponse(
                build_report_markdown(child, alerts, evidence),
                media_type="text/markdown")
        return HTMLResponse(build_report_html(child, alerts, evidence))

    return app


app = create_app()
