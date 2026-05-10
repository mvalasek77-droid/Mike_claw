"""Project memory — persistent state the swarm carries across builds.

Stores three kinds of records:

  * `facts`     — key/value preferences the agents learn ("user prefers
                 monochrome icons", "always use SwiftLint config X").
  * `projects`  — every BuildJob that has ever run, with its spec + summary.
  * `decisions` — moments of reasoning we want to recall later.

Backed by a single SQLite database at
`<workspace_root>/.codegenie/memory.sqlite3`. Synchronous on purpose —
SQLite's single-writer model is fine here and lets us avoid an async
cursor library. We wrap every mutating call with a short-lived
connection so the DB stays portable and corruption-safe.
"""
from __future__ import annotations

import json
import sqlite3
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator


@dataclass
class Fact:
    key: str
    value: str
    confidence: float
    source: str
    ts: float


@dataclass
class ProjectRecord:
    job_id: str
    title: str
    spec_json: str
    summary: str
    succeeded: bool
    ts: float


@dataclass
class Decision:
    job_id: str
    context: str
    decision: str
    ts: float


class Memory:
    """Thread-safe wrapper around a SQLite file. Connections are short-
    lived (one per call) — no global cursor we have to mutex around."""

    def __init__(self, root: Path) -> None:
        self.path = root / ".codegenie" / "memory.sqlite3"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self._init_schema()

    @contextmanager
    def _conn(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            conn = sqlite3.connect(self.path)
            conn.row_factory = sqlite3.Row
            try:
                yield conn
                conn.commit()
            finally:
                conn.close()

    def _init_schema(self) -> None:
        with self._conn() as c:
            c.executescript(
                """
                CREATE TABLE IF NOT EXISTS facts (
                    key        TEXT PRIMARY KEY,
                    value      TEXT NOT NULL,
                    confidence REAL NOT NULL DEFAULT 0.5,
                    source     TEXT NOT NULL,
                    ts         REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS projects (
                    job_id    TEXT PRIMARY KEY,
                    title     TEXT NOT NULL,
                    spec_json TEXT NOT NULL,
                    summary   TEXT NOT NULL DEFAULT '',
                    succeeded INTEGER NOT NULL DEFAULT 0,
                    ts        REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS decisions (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    job_id  TEXT NOT NULL,
                    context TEXT NOT NULL,
                    decision TEXT NOT NULL,
                    ts REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_decisions_job ON decisions(job_id);
                CREATE INDEX IF NOT EXISTS idx_facts_source ON facts(source);
                """
            )

    # ------------------------------------------------------------------
    # Facts
    # ------------------------------------------------------------------

    def remember(self, key: str, value: str, *, confidence: float = 0.7, source: str = "agent") -> None:
        with self._conn() as c:
            c.execute(
                """INSERT INTO facts(key, value, confidence, source, ts)
                   VALUES(?,?,?,?,?)
                   ON CONFLICT(key) DO UPDATE SET
                     value=excluded.value,
                     confidence=excluded.confidence,
                     source=excluded.source,
                     ts=excluded.ts""",
                (key, value, confidence, source, time.time()),
            )

    def forget(self, key: str) -> None:
        with self._conn() as c:
            c.execute("DELETE FROM facts WHERE key=?", (key,))

    def recall(self, query: str, *, limit: int = 10) -> list[Fact]:
        """Cheap LIKE-based retrieval. Replace with FTS5 when corpus warrants it."""
        like = f"%{query.lower()}%"
        with self._conn() as c:
            rows = c.execute(
                """SELECT key, value, confidence, source, ts FROM facts
                   WHERE LOWER(key) LIKE ? OR LOWER(value) LIKE ?
                   ORDER BY confidence DESC, ts DESC LIMIT ?""",
                (like, like, limit),
            ).fetchall()
        return [Fact(**dict(r)) for r in rows]

    def all_facts(self) -> list[Fact]:
        with self._conn() as c:
            rows = c.execute(
                "SELECT key, value, confidence, source, ts FROM facts ORDER BY ts DESC"
            ).fetchall()
        return [Fact(**dict(r)) for r in rows]

    # ------------------------------------------------------------------
    # Projects + decisions
    # ------------------------------------------------------------------

    def record_project(self, job_id: str, title: str, spec: dict[str, Any], succeeded: bool, summary: str = "") -> None:
        with self._conn() as c:
            c.execute(
                """INSERT INTO projects(job_id, title, spec_json, summary, succeeded, ts)
                   VALUES(?,?,?,?,?,?)
                   ON CONFLICT(job_id) DO UPDATE SET
                     summary=excluded.summary, succeeded=excluded.succeeded""",
                (job_id, title, json.dumps(spec), summary, int(succeeded), time.time()),
            )

    def recent_projects(self, limit: int = 10) -> list[ProjectRecord]:
        with self._conn() as c:
            rows = c.execute(
                """SELECT job_id, title, spec_json, summary, succeeded, ts
                   FROM projects ORDER BY ts DESC LIMIT ?""",
                (limit,),
            ).fetchall()
        return [
            ProjectRecord(
                job_id=r["job_id"], title=r["title"], spec_json=r["spec_json"],
                summary=r["summary"], succeeded=bool(r["succeeded"]), ts=r["ts"],
            )
            for r in rows
        ]

    def note_decision(self, job_id: str, context: str, decision: str) -> None:
        with self._conn() as c:
            c.execute(
                "INSERT INTO decisions(job_id, context, decision, ts) VALUES(?,?,?,?)",
                (job_id, context, decision, time.time()),
            )

    def decisions_for(self, job_id: str) -> list[Decision]:
        with self._conn() as c:
            rows = c.execute(
                "SELECT job_id, context, decision, ts FROM decisions WHERE job_id=? ORDER BY ts ASC",
                (job_id,),
            ).fetchall()
        return [Decision(**dict(r)) for r in rows]

    # ------------------------------------------------------------------
    # Summary block — what the orchestrator paste-prepends to every agent
    # ------------------------------------------------------------------

    def briefing(self, *, limit: int = 8) -> str:
        """Render the most relevant facts + recent projects as a Markdown
        briefing the orchestrator can paste at the top of an agent's
        system prompt. Empty string when there's nothing useful yet."""
        facts = self.all_facts()[:limit]
        projects = self.recent_projects(limit=3)
        if not facts and not projects:
            return ""

        out: list[str] = ["## What CodeGenie remembers about you", ""]
        if facts:
            out.append("**Preferences:**")
            for f in facts:
                out.append(f"- {f.key}: {f.value}  _(via {f.source}, confidence {f.confidence:.2f})_")
            out.append("")
        if projects:
            out.append("**Recent projects:**")
            for p in projects:
                tick = "✓" if p.succeeded else "✗"
                out.append(f"- {tick} {p.title} — {p.summary[:80]}")
            out.append("")
        return "\n".join(out)
