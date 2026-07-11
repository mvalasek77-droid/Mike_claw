"""SQLite persistence.

Data-minimization by design: we store the child's Roblox username/id, snapshot
diffs needed to detect changes, and generated alerts. We do not mirror friends'
full profiles beyond what an alert needs, and nothing here ever contains chat
content (none is collected anywhere in the app).
"""

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS children (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    roblox_user_id INTEGER NOT NULL UNIQUE,
    roblox_username TEXT NOT NULL,
    display_name TEXT NOT NULL DEFAULT '',
    -- Verifiable-parental-consent record: who attested, and when.
    consent_attested_by TEXT NOT NULL,
    consent_attested_at TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    taken_at TEXT NOT NULL,
    friend_ids TEXT NOT NULL,          -- JSON array of ints
    presence_type INTEGER NOT NULL DEFAULT 0,
    place_id INTEGER
);

CREATE TABLE IF NOT EXISTS friend_first_seen (
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    friend_user_id INTEGER NOT NULL,
    first_seen_at TEXT NOT NULL,
    PRIMARY KEY (child_id, friend_user_id)
);

CREATE TABLE IF NOT EXISTS alerts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    severity TEXT NOT NULL,
    title TEXT NOT NULL,
    facts TEXT NOT NULL,               -- JSON array of strings
    guidance TEXT NOT NULL,
    subject_user_id INTEGER,
    subject_username TEXT,
    observed_at TEXT NOT NULL,
    acknowledged INTEGER NOT NULL DEFAULT 0
);
"""


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, path: str):
        self._path = path
        with self._connect() as conn:
            conn.executescript(SCHEMA)

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(self._path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    # -- children ----------------------------------------------------------

    def add_child(self, roblox_user_id: int, username: str, display_name: str,
                  consent_attested_by: str) -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO children (roblox_user_id, roblox_username, display_name,"
                " consent_attested_by, consent_attested_at, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (roblox_user_id, username, display_name, consent_attested_by, utcnow(), utcnow()),
            )
            return cur.lastrowid

    def get_child(self, child_id: int) -> Optional[dict]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM children WHERE id = ?", (child_id,)).fetchone()
            return dict(row) if row else None

    def get_child_by_roblox_id(self, roblox_user_id: int) -> Optional[dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM children WHERE roblox_user_id = ?", (roblox_user_id,)
            ).fetchone()
            return dict(row) if row else None

    def list_children(self) -> list[dict]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute("SELECT * FROM children ORDER BY id")]

    def remove_child(self, child_id: int) -> None:
        """Full erasure — removes the child and all derived data (COPPA deletion right)."""
        with self._connect() as conn:
            conn.execute("DELETE FROM children WHERE id = ?", (child_id,))

    # -- snapshots ---------------------------------------------------------

    def add_snapshot(self, child_id: int, friend_ids: list[int],
                     presence_type: int, place_id: Optional[int]) -> None:
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO snapshots (child_id, taken_at, friend_ids, presence_type, place_id)"
                " VALUES (?, ?, ?, ?, ?)",
                (child_id, utcnow(), json.dumps(sorted(friend_ids)), presence_type, place_id),
            )

    def latest_snapshot(self, child_id: int) -> Optional[dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM snapshots WHERE child_id = ? ORDER BY id DESC LIMIT 1",
                (child_id,),
            ).fetchone()
            if not row:
                return None
            out = dict(row)
            out["friend_ids"] = json.loads(out["friend_ids"])
            return out

    # -- friend first-seen tracking (for rapid-friending windows) -----------

    def record_friends_seen(self, child_id: int, friend_ids: list[int]) -> list[int]:
        """Insert any friends not seen before; returns the newly-seen ids."""
        now = utcnow()
        new_ids: list[int] = []
        with self._connect() as conn:
            for fid in friend_ids:
                cur = conn.execute(
                    "INSERT OR IGNORE INTO friend_first_seen (child_id, friend_user_id, first_seen_at)"
                    " VALUES (?, ?, ?)",
                    (child_id, fid, now),
                )
                if cur.rowcount:
                    new_ids.append(fid)
        return new_ids

    def friends_first_seen_since(self, child_id: int, since_iso: str) -> int:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT COUNT(*) AS n FROM friend_first_seen"
                " WHERE child_id = ? AND first_seen_at >= ?",
                (child_id, since_iso),
            ).fetchone()
            return int(row["n"])

    # -- alerts --------------------------------------------------------------

    def add_alert(self, child_id: int, signal: Any) -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO alerts (child_id, type, severity, title, facts, guidance,"
                " subject_user_id, subject_username, observed_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    child_id,
                    signal.type.value,
                    signal.severity.value,
                    signal.title,
                    json.dumps(signal.facts),
                    signal.guidance,
                    signal.subject_user_id,
                    signal.subject_username,
                    signal.observed_at.isoformat(),
                ),
            )
            return cur.lastrowid

    def list_alerts(self, child_id: int, include_acknowledged: bool = False) -> list[dict]:
        query = "SELECT * FROM alerts WHERE child_id = ?"
        if not include_acknowledged:
            query += " AND acknowledged = 0"
        query += " ORDER BY id DESC"
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(query, (child_id,))]
        for row in rows:
            row["facts"] = json.loads(row["facts"])
            row["acknowledged"] = bool(row["acknowledged"])
        return rows

    def acknowledge_alert(self, alert_id: int) -> bool:
        with self._connect() as conn:
            cur = conn.execute("UPDATE alerts SET acknowledged = 1 WHERE id = ?", (alert_id,))
            return cur.rowcount > 0

    def recent_alert_exists(self, child_id: int, signal_type: str,
                            subject_user_id: Optional[int], since_iso: str) -> bool:
        """Dedupe: has an equivalent alert already fired recently?"""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT 1 FROM alerts WHERE child_id = ? AND type = ?"
                " AND (subject_user_id IS ? OR subject_user_id = ?)"
                " AND observed_at >= ? LIMIT 1",
                (child_id, signal_type, subject_user_id, subject_user_id, since_iso),
            ).fetchone()
            return row is not None
