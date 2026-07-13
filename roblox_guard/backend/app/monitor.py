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
from .threat_feed import FeedManager
from . import signals as sig

# Parent-feedback tuning: a signal type is muted for a child once the parent
# has dismissed it this many times without ever confirming it. Elevated
# alerts are never muted. A confirmed alert switches the child to heightened
# monitoring (shorter dedupe window, so repeat behavior re-alerts sooner).
DISMISSALS_TO_MUTE = 3
DEDUPE_HOURS_NORMAL = 12
DEDUPE_HOURS_HEIGHTENED = 2

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
    def __init__(self, db: Database, client: RobloxClient, settings: Settings,
                 vault=None, feeds: Optional[FeedManager] = None, push=None):
        self.db = db
        self.client = client
        self.settings = settings
        self.vault = vault  # EvidenceVault; optional so tests can omit it
        self.feeds = feeds or FeedManager()
        self.push = push  # APNsService; optional, no-ops when unconfigured
        self.local_watchlist = load_watchlist(settings.watchlist_path)
        self._task: Optional[asyncio.Task] = None

    @property
    def watchlist(self) -> dict[int, dict]:
        """Operator-local watchlist merged with the threat feed's (feed wins)."""
        merged = dict(self.local_watchlist)
        merged.update(self.feeds.feed.watchlist_by_place())
        return merged

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
            except Exception as error:
                log.exception("poll cycle failed")
                self.db.log_backend_error(
                    f"Poll cycle failed: {type(error).__name__}", str(error))
            await asyncio.sleep(self.settings.poll_interval_seconds)

    # -- polling -------------------------------------------------------------

    async def poll_all(self) -> None:
        await self.feeds.maybe_refresh()
        for child in self.db.list_children():
            try:
                await self.poll_child(child["id"])
            except Exception as error:
                log.exception("polling child %s failed", child["id"])
                self.db.update_child_poll_status(
                    child["id"], f"error: {type(error).__name__}")
                self.db.log_backend_error(
                    f"Poll failed for child {child['id']}: {type(error).__name__}",
                    str(error), context={"child_id": child["id"]})

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
                self.feeds.feed,
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

        # Parent-feedback tuning: heightened mode after any confirmed alert;
        # per-type muting after repeated dismissals (never for elevated).
        heightened = self.db.child_has_confirmed_alert(child_id)
        dedupe_hours = DEDUPE_HOURS_HEIGHTENED if heightened else DEDUPE_HOURS_NORMAL

        created: list[dict] = []
        dedupe_since = (datetime.now(timezone.utc) - timedelta(hours=dedupe_hours)).isoformat()
        for s in produced:
            sig.validate_wording(s)
            if s.severity != sig.Severity.ELEVATED:
                confirmed, dismissed = self.db.feedback_counts(child_id, s.type.value)
                if dismissed >= DISMISSALS_TO_MUTE and confirmed == 0:
                    continue
            if self.db.recent_alert_exists(child_id, s.type.value, s.subject_user_id, dedupe_since):
                continue
            alert_id = self.db.add_alert(child_id, s)
            created.append({"id": alert_id, "type": s.type.value, "severity": s.severity.value,
                            "title": s.title})
            await self._capture_evidence(child_id, alert_id, s, presence)
            await self._push_alert(child, s)
        self.db.update_child_poll_status(child_id, "ok")
        return created

    async def _push_alert(self, child: dict, s: sig.Signal) -> None:
        """Notifies every registered parent device — the whole point of a
        push is hearing about a threat without having the app open. INFO
        alerts are baseline noise and don't warrant an interruption."""
        if self.push is None or s.severity == sig.Severity.INFO:
            return
        name = child["display_name"] or child["roblox_username"]
        try:
            await self.push.send_to_all(self.db, title=f"{s.severity.value.title()} alert: {name}",
                                        body=s.title)
        except Exception:
            log.exception("push notification failed for alert on child %s", child["id"])

    async def _capture_evidence(self, child_id: int, alert_id: int,
                                s: sig.Signal, presence) -> None:
        """Preserve what we observed the moment an alert fires.

        Every non-info alert gets a machine-readable data snapshot; alerts
        about a specific account also get a screenshot of that account's
        public profile page (bios get edited fast once someone feels watched).
        Evidence failures never block the alert itself.
        """
        if self.vault is None or s.severity == sig.Severity.INFO:
            return
        try:
            self.vault.record_data_snapshot(
                child_id, alert_id,
                payload={
                    "alert_type": s.type.value,
                    "severity": s.severity.value,
                    "title": s.title,
                    "facts": s.facts,
                    "subject_user_id": s.subject_user_id,
                    "subject_username": s.subject_username,
                    "presence": {
                        "presence_type": presence.presence_type,
                        "place_id": presence.place_id,
                        "last_location": presence.last_location,
                    },
                },
                note=f"Observed data at the moment alert #{alert_id} fired",
            )
        except Exception:
            log.exception("data snapshot failed for alert %s", alert_id)
        if s.subject_user_id:
            try:
                await self.vault.capture_profile_screenshot(
                    child_id, alert_id, s.subject_user_id, s.subject_username or "",
                )
            except Exception:
                log.exception("profile screenshot failed for alert %s", alert_id)
