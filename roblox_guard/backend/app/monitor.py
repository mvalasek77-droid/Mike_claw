"""Polling monitor: snapshot a child's public Roblox footprint, diff against
the previous snapshot, and turn changes into stored alerts.
"""

import asyncio
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from .config import Settings
from .db import Database
from .roblox_client import RobloxClient
from . import signals as sig

log = logging.getLogger("roblox_guard.monitor")


def load_watchlist(path: str) -> dict[int, dict]:
    """Load the curated experience watchlist: placeId -> {name, reason}."""
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        data = json.load(f)
    out: dict[int, dict] = {}
    for entry in data.get("experiences", []):
        try:
            out[int(entry["place_id"])] = entry
        except (KeyError, TypeError, ValueError):
            log.warning("Skipping malformed watchlist entry: %r", entry)
    return out


class Monitor:
    def __init__(self, db: Database, client: RobloxClient, settings: Settings):
        self.db = db
        self.client = client
        self.settings = settings
        self.watchlist = load_watchlist(settings.watchlist_path)
        self._task: Optional[asyncio.Task] = None

    # -- lifecycle -----------------------------------------------------------

    def start(self) -> None:
        self._task = asyncio.create_task(self._run())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        while True:
            try:
                await self.poll_all()
            except Exception:
                log.exception("poll cycle failed")
            await asyncio.sleep(self.settings.poll_interval_seconds)

    # -- polling -------------------------------------------------------------

    async def poll_all(self) -> None:
        for child in self.db.list_children():
            try:
                await self.poll_child(child["id"])
            except Exception:
                log.exception("polling child %s failed", child["id"])

    async def poll_child(self, child_id: int, local_now: Optional[datetime] = None) -> list[dict]:
        """Take a snapshot for one child and store any resulting alerts.

        Returns the alerts created in this cycle (as stored dicts).
        """
        child = self.db.get_child(child_id)
        if child is None:
            return []

        roblox_id = child["roblox_user_id"]
        previous = self.db.latest_snapshot(child_id)
        friends = await self.client.get_friends(roblox_id)
        presence = await self.client.get_presence(roblox_id)

        friend_ids = [f.user_id for f in friends]
        self.db.add_snapshot(child_id, friend_ids, presence.presence_type, presence.place_id)
        newly_seen = set(self.db.record_friends_seen(child_id, friend_ids))

        produced: list[sig.Signal] = []
        is_baseline = previous is None

        # New-friend evaluation. On the very first poll everything is "new",
        # so we suppress INFO-level noise but still surface real risk signals
        # (an off-platform handle in a bio matters whether or not we watched
        # the friendship form).
        for friend in friends:
            if friend.user_id not in newly_seen:
                continue
            for s in sig.evaluate_new_friend(
                friend,
                established_years=self.settings.established_account_years,
                mass_friender_threshold=self.settings.mass_friender_threshold,
            ):
                if is_baseline and s.severity == sig.Severity.INFO:
                    continue
                produced.append(s)

        # Rapid friending (skip on baseline — the whole list is "new").
        if not is_baseline:
            window = self.settings.rapid_friend_window_hours
            since = (datetime.now(timezone.utc) - timedelta(hours=window)).isoformat()
            recent = self.db.friends_first_seen_since(child_id, since)
            rapid = sig.evaluate_rapid_friending(
                recent, window, self.settings.rapid_friend_count
            )
            if rapid:
                produced.append(rapid)

        # Presence-derived signals (flagged experience, quiet hours).
        produced.extend(sig.evaluate_presence(
            presence,
            self.watchlist,
            self.settings.quiet_hours_start,
            self.settings.quiet_hours_end,
            local_now=local_now,
        ))

        created: list[dict] = []
        dedupe_since = (datetime.now(timezone.utc) - timedelta(hours=12)).isoformat()
        for s in produced:
            sig.validate_wording(s)
            if self.db.recent_alert_exists(child_id, s.type.value, s.subject_user_id, dedupe_since):
                continue
            alert_id = self.db.add_alert(child_id, s)
            created.append({"id": alert_id, "type": s.type.value, "severity": s.severity.value,
                            "title": s.title})
        return created
