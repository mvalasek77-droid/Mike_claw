"""SQLite persistence.

Data-minimization by design: we store the child's Roblox username/id, snapshot
diffs needed to detect changes, and generated alerts. We do not mirror friends'
full profiles beyond what an alert needs, and nothing here ever contains chat
content (none is collected anywhere in the app).
"""

import json
import secrets
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Iterator, Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS children (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id TEXT NOT NULL,
    share_token TEXT NOT NULL UNIQUE,
    roblox_user_id INTEGER NOT NULL,
    roblox_username TEXT NOT NULL,
    display_name TEXT NOT NULL DEFAULT '',
    -- Verifiable-parental-consent record: who attested, and when.
    consent_attested_by TEXT NOT NULL,
    consent_attested_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_poll_at TEXT,
    last_poll_status TEXT NOT NULL DEFAULT '',
    UNIQUE(client_id, roblox_user_id)
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

CREATE TABLE IF NOT EXISTS evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    alert_id INTEGER,
    kind TEXT NOT NULL,                -- profile_screenshot | data_snapshot | parent_upload
    path TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    captured_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS intel_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ran_at TEXT NOT NULL,
    analyzer TEXT NOT NULL,
    findings_count INTEGER NOT NULL,
    proposal_counts TEXT NOT NULL,     -- JSON object of category -> count
    summary TEXT NOT NULL DEFAULT '',
    applied INTEGER NOT NULL DEFAULT 0,
    proposal_path TEXT NOT NULL DEFAULT ''
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
    acknowledged INTEGER NOT NULL DEFAULT 0,
    feedback TEXT NOT NULL DEFAULT ''   -- '' | 'confirmed' | 'dismissed'
);

CREATE TABLE IF NOT EXISTS bug_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    client_id TEXT NOT NULL DEFAULT 'system',
    created_at TEXT NOT NULL,
    source TEXT NOT NULL,               -- 'customer' | 'backend_error'
    summary TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    context TEXT NOT NULL DEFAULT '{}', -- JSON object: app_version, platform, path, etc.
    contact_email TEXT NOT NULL DEFAULT '',
    emailed INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS device_tokens (
    token TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios',
    registered_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL
);
"""

# Columns added after first release; applied to pre-existing databases.
MIGRATIONS = [
    "ALTER TABLE children ADD COLUMN last_poll_at TEXT",
    "ALTER TABLE children ADD COLUMN last_poll_status TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE alerts ADD COLUMN feedback TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE children ADD COLUMN client_id TEXT NOT NULL DEFAULT 'legacy'",
    "ALTER TABLE children ADD COLUMN share_token TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE bug_reports ADD COLUMN client_id TEXT NOT NULL DEFAULT 'system'",
    "ALTER TABLE device_tokens ADD COLUMN client_id TEXT NOT NULL DEFAULT 'legacy'",
]


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self, path: str):
        self._path = path
        with self._connect() as conn:
            conn.executescript(SCHEMA)
            for statement in MIGRATIONS:
                try:
                    conn.execute(statement)
                except sqlite3.OperationalError:
                    pass  # column already exists (fresh schema or migrated)
            rows = conn.execute(
                "SELECT id FROM children WHERE share_token = ''"
            ).fetchall()
            for row in rows:
                conn.execute(
                    "UPDATE children SET share_token = ? WHERE id = ?",
                    (secrets.token_urlsafe(32), row["id"]),
                )

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
                  consent_attested_by: str,
                  client_id: str = "local-development") -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO children (client_id, share_token, roblox_user_id,"
                " roblox_username, display_name,"
                " consent_attested_by, consent_attested_at, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    client_id,
                    secrets.token_urlsafe(32),
                    roblox_user_id,
                    username,
                    display_name,
                    consent_attested_by,
                    utcnow(),
                    utcnow(),
                ),
            )
            return cur.lastrowid

    def get_child(self, child_id: int, client_id: Optional[str] = None,
                  share_token: Optional[str] = None) -> Optional[dict]:
        query = "SELECT * FROM children WHERE id = ?"
        params: list[Any] = [child_id]
        if client_id is not None:
            query += " AND client_id = ?"
            params.append(client_id)
        if share_token is not None:
            query += " AND share_token = ?"
            params.append(share_token)
        with self._connect() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    def get_child_by_roblox_id(self, roblox_user_id: int,
                               client_id: Optional[str] = None) -> Optional[dict]:
        query = "SELECT * FROM children WHERE roblox_user_id = ?"
        params: list[Any] = [roblox_user_id]
        if client_id is not None:
            query += " AND client_id = ?"
            params.append(client_id)
        with self._connect() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    def list_children(self, client_id: Optional[str] = None) -> list[dict]:
        query = "SELECT * FROM children"
        params: tuple = ()
        if client_id is not None:
            query += " WHERE client_id = ?"
            params = (client_id,)
        query += " ORDER BY id"
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(query, params)]

    def update_child_poll_status(self, child_id: int, status: str) -> None:
        with self._connect() as conn:
            conn.execute(
                "UPDATE children SET last_poll_at = ?, last_poll_status = ? WHERE id = ?",
                (utcnow(), status, child_id),
            )

    def remove_child(self, child_id: int, client_id: Optional[str] = None) -> None:
        """Full erasure — removes the child and all derived data (COPPA deletion right)."""
        query = "DELETE FROM children WHERE id = ?"
        params: list[Any] = [child_id]
        if client_id is not None:
            query += " AND client_id = ?"
            params.append(client_id)
        with self._connect() as conn:
            conn.execute(query, params)

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
        """New friends within the window, excluding the baseline scan.

        Friends recorded when monitoring started aren't 'added in the last N
        hours' — the child had them before we were watching — so anything
        first seen at (or before) the first snapshot is excluded.
        """
        with self._connect() as conn:
            first = conn.execute(
                "SELECT friend_ids FROM snapshots WHERE child_id = ?"
                " ORDER BY id ASC LIMIT 1", (child_id,),
            ).fetchone()
            baseline_ids = set(json.loads(first["friend_ids"])) if first else set()
            rows = conn.execute(
                "SELECT friend_user_id FROM friend_first_seen"
                " WHERE child_id = ? AND first_seen_at >= ?",
                (child_id, since_iso),
            ).fetchall()
            return sum(1 for r in rows if r["friend_user_id"] not in baseline_ids)

    # -- evidence ------------------------------------------------------------

    def add_evidence(self, child_id: int, alert_id: Optional[int], kind: str,
                     path: str, sha256: str, note: str = "") -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO evidence (child_id, alert_id, kind, path, sha256, note, captured_at)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (child_id, alert_id, kind, path, sha256, note, utcnow()),
            )
            return cur.lastrowid

    def list_evidence(self, child_id: int) -> list[dict]:
        with self._connect() as conn:
            return [dict(r) for r in conn.execute(
                "SELECT * FROM evidence WHERE child_id = ? ORDER BY id DESC", (child_id,)
            )]

    def get_evidence(self, evidence_id: int, client_id: Optional[str] = None,
                     share_token: Optional[str] = None) -> Optional[dict]:
        query = (
            "SELECT evidence.* FROM evidence"
            " JOIN children ON children.id = evidence.child_id"
            " WHERE evidence.id = ?"
        )
        params: list[Any] = [evidence_id]
        if client_id is not None:
            query += " AND children.client_id = ?"
            params.append(client_id)
        if share_token is not None:
            query += " AND children.share_token = ?"
            params.append(share_token)
        with self._connect() as conn:
            row = conn.execute(query, params).fetchone()
            return dict(row) if row else None

    # -- intel runs ----------------------------------------------------------

    def add_intel_run(self, analyzer: str, findings_count: int,
                      proposal_counts: dict, summary: str, applied: bool,
                      proposal_path: str) -> int:
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO intel_runs (ran_at, analyzer, findings_count,"
                " proposal_counts, summary, applied, proposal_path)"
                " VALUES (?, ?, ?, ?, ?, ?, ?)",
                (utcnow(), analyzer, findings_count, json.dumps(proposal_counts),
                 summary, int(applied), proposal_path),
            )
            return cur.lastrowid

    def get_intel_run(self, run_id: int) -> Optional[dict]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM intel_runs WHERE id = ?", (run_id,)).fetchone()
        if not row:
            return None
        out = dict(row)
        out["proposal_counts"] = json.loads(out["proposal_counts"])
        out["applied"] = bool(out["applied"])
        return out

    def list_intel_runs(self, limit: int = 30) -> list[dict]:
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(
                "SELECT * FROM intel_runs ORDER BY id DESC LIMIT ?", (limit,))]
        for row in rows:
            row["proposal_counts"] = json.loads(row["proposal_counts"])
            row["applied"] = bool(row["applied"])
        return rows

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

    def acknowledge_alert(self, alert_id: int,
                          client_id: Optional[str] = None) -> bool:
        query = "UPDATE alerts SET acknowledged = 1 WHERE id = ?"
        params: list[Any] = [alert_id]
        if client_id is not None:
            query += (
                " AND child_id IN"
                " (SELECT id FROM children WHERE client_id = ?)"
            )
            params.append(client_id)
        with self._connect() as conn:
            cur = conn.execute(query, params)
            return cur.rowcount > 0

    # -- parent feedback (adaptive tuning) -------------------------------------

    def set_alert_feedback(self, alert_id: int, verdict: str,
                           client_id: Optional[str] = None) -> bool:
        if verdict not in ("confirmed", "dismissed"):
            raise ValueError("verdict must be 'confirmed' or 'dismissed'")
        query = "UPDATE alerts SET feedback = ?, acknowledged = 1 WHERE id = ?"
        params: list[Any] = [verdict, alert_id]
        if client_id is not None:
            query += (
                " AND child_id IN"
                " (SELECT id FROM children WHERE client_id = ?)"
            )
            params.append(client_id)
        with self._connect() as conn:
            cur = conn.execute(query, params)
            return cur.rowcount > 0

    def feedback_counts(self, child_id: int, signal_type: str) -> tuple[int, int]:
        """(confirmed, dismissed) counts for one signal type of one child."""
        with self._connect() as conn:
            row = conn.execute(
                "SELECT"
                " SUM(CASE WHEN feedback = 'confirmed' THEN 1 ELSE 0 END) AS c,"
                " SUM(CASE WHEN feedback = 'dismissed' THEN 1 ELSE 0 END) AS d"
                " FROM alerts WHERE child_id = ? AND type = ?",
                (child_id, signal_type),
            ).fetchone()
            return int(row["c"] or 0), int(row["d"] or 0)

    def child_has_confirmed_alert(self, child_id: int) -> bool:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT 1 FROM alerts WHERE child_id = ? AND feedback = 'confirmed' LIMIT 1",
                (child_id,),
            ).fetchone()
            return row is not None

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

    # -- bug reports ------------------------------------------------------------
    # The durable bug log: every customer-submitted report and every unhandled
    # backend error lands here, regardless of whether email delivery (mailer.py)
    # succeeds, so nothing depends on SMTP being configured to not be lost.

    def add_bug_report(self, source: str, summary: str, details: str = "",
                       context: Optional[dict] = None, contact_email: str = "",
                       client_id: str = "system") -> int:
        if source not in ("customer", "backend_error"):
            raise ValueError("source must be 'customer' or 'backend_error'")
        with self._connect() as conn:
            cur = conn.execute(
                "INSERT INTO bug_reports (client_id, created_at, source, summary,"
                " details, context, contact_email) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (client_id, utcnow(), source, summary, details,
                 json.dumps(context or {}), contact_email),
            )
            return cur.lastrowid

    def get_bug_report(self, report_id: int) -> Optional[dict]:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM bug_reports WHERE id = ?", (report_id,)
            ).fetchone()
        if not row:
            return None
        out = dict(row)
        out["context"] = json.loads(out["context"])
        out["emailed"] = bool(out["emailed"])
        return out

    def list_bug_reports(self, limit: int = 100) -> list[dict]:
        with self._connect() as conn:
            rows = [dict(r) for r in conn.execute(
                "SELECT * FROM bug_reports ORDER BY id DESC LIMIT ?", (limit,))]
        for row in rows:
            row["context"] = json.loads(row["context"])
            row["emailed"] = bool(row["emailed"])
        return rows

    def mark_bug_report_emailed(self, report_id: int) -> None:
        with self._connect() as conn:
            conn.execute("UPDATE bug_reports SET emailed = 1 WHERE id = ?", (report_id,))

    def log_backend_error(self, summary: str, details: str = "",
                          context: Optional[dict] = None) -> int:
        """Convenience wrapper used by exception handlers (main.py, monitor.py)."""
        return self.add_bug_report("backend_error", summary, details, context)

    # -- push notification device tokens ----------------------------------------
    # Tokens are bound to the same random installation id as child records.

    def register_device_token(self, token: str, platform: str = "ios",
                              client_id: str = "local-development") -> None:
        now = utcnow()
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO device_tokens"
                " (token, client_id, platform, registered_at, last_seen_at)"
                " VALUES (?, ?, ?, ?, ?)"
                " ON CONFLICT(token) DO UPDATE SET"
                " client_id = excluded.client_id,"
                " platform = excluded.platform,"
                " last_seen_at = excluded.last_seen_at",
                (token, client_id, platform, now, now),
            )

    def list_device_tokens(self, client_id: Optional[str] = None) -> list[str]:
        query = "SELECT token FROM device_tokens"
        params: tuple = ()
        if client_id is not None:
            query += " WHERE client_id = ?"
            params = (client_id,)
        with self._connect() as conn:
            return [r["token"] for r in conn.execute(query, params)]

    def remove_device_token(self, token: str,
                            client_id: Optional[str] = None) -> None:
        query = "DELETE FROM device_tokens WHERE token = ?"
        params: list[Any] = [token]
        if client_id is not None:
            query += " AND client_id = ?"
            params.append(client_id)
        with self._connect() as conn:
            conn.execute(query, params)

    def total_unacknowledged_alerts(self,
                                    client_id: Optional[str] = None) -> int:
        """Badge count for one installation, or all installations for ops."""
        query = "SELECT COUNT(*) AS n FROM alerts"
        params: tuple = ()
        if client_id is not None:
            query = (
                "SELECT COUNT(*) AS n FROM alerts"
                " JOIN children ON children.id = alerts.child_id"
                " WHERE alerts.acknowledged = 0 AND children.client_id = ?"
            )
            params = (client_id,)
        else:
            query += " WHERE acknowledged = 0"
        with self._connect() as conn:
            row = conn.execute(query, params).fetchone()
            return int(row["n"])
