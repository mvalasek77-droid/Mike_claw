"""FastAPI application — the API the parent's iOS app talks to.

Consent model: linking a child requires an explicit parental attestation in
the request body. The attestation (who, when) is stored with the child record
and unlinking erases all derived data, matching COPPA's consent + deletion
expectations.
"""

import logging
from contextlib import asynccontextmanager
from typing import Optional

import httpx
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from .config import Settings, settings as default_settings
from .db import Database
from .monitor import Monitor
from .resources import RESOURCES
from .roblox_client import RobloxClient

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


def create_app(settings: Optional[Settings] = None,
               client: Optional[RobloxClient] = None,
               start_monitor: bool = True) -> FastAPI:
    settings = settings or default_settings
    db = Database(settings.db_path)
    roblox = client or RobloxClient(spacing_seconds=settings.request_spacing_seconds)
    monitor = Monitor(db, roblox, settings)

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
        return {"status": "ok"}

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
                              display_name=c["display_name"])
                for c in db.list_children()]

    @app.delete("/children/{child_id}", status_code=204)
    async def unlink_child(child_id: int):
        if not db.get_child(child_id):
            raise HTTPException(status_code=404, detail="Unknown child.")
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
        return {"alerts": db.list_alerts(child_id, include_acknowledged)}

    @app.post("/alerts/{alert_id}/acknowledge")
    async def acknowledge(alert_id: int):
        if not db.acknowledge_alert(alert_id):
            raise HTTPException(status_code=404, detail="Unknown alert.")
        return {"acknowledged": True}

    @app.get("/resources")
    async def resources():
        return {"resources": RESOURCES}

    return app


app = create_app()
