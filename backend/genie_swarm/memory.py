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

    def confidence_at(self, now: float, half_life_seconds: float) -> float:
        """Exponential decay. A fact stored with confidence C ages so that
        at one half-life it has confidence C/2. Confidence is clamped at
        a small floor so a single recall doesn't accidentally drop the
        fact below the prune threshold."""
        age = max(0.0, now - self.ts)
        decayed = self.confidence * (0.5 ** (age / half_life_seconds))
        return max(0.01, decayed)


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
    lived (one per call) — no global cursor we have to mutex around.

    Confidence on every fact decays exponentially with age. We apply the
    decay lazily — at `recall()` time — and prune anything that has
    fallen below `prune_threshold` so the table doesn't accumulate dead
    weight. Default half-life is 30 days, which roughly maps to "if you
    haven't reinforced this in a month, it should start fading."
    """

    DEFAULT_HALF_LIFE_SECONDS: float = 30 * 24 * 60 * 60
    PRUNE_THRESHOLD: float = 0.05

    def __init__(
        self,
        root: Path,
        *,
        half_life_seconds: float | None = None,
    ) -> None:
        self.path = root / ".codegenie" / "memory.sqlite3"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self.half_life_seconds = half_life_seconds or self.DEFAULT_HALF_LIFE_SECONDS
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
            # FTS5 mirror of facts. Some SQLite builds ship without
            # FTS5 — we degrade to a LIKE-based recall path in that case.
            try:
                c.executescript(
                    """
                    CREATE VIRTUAL TABLE IF NOT EXISTS facts_fts USING fts5(
                        key, value, content='facts', content_rowid='rowid'
                    );
                    CREATE TRIGGER IF NOT EXISTS facts_ai AFTER INSERT ON facts BEGIN
                        INSERT INTO facts_fts(rowid, key, value)
                        VALUES (new.rowid, new.key, new.value);
                    END;
                    CREATE TRIGGER IF NOT EXISTS facts_ad AFTER DELETE ON facts BEGIN
                        INSERT INTO facts_fts(facts_fts, rowid, key, value)
                        VALUES ('delete', old.rowid, old.key, old.value);
                    END;
                    CREATE TRIGGER IF NOT EXISTS facts_au AFTER UPDATE ON facts BEGIN
                        INSERT INTO facts_fts(facts_fts, rowid, key, value)
                        VALUES ('delete', old.rowid, old.key, old.value);
                        INSERT INTO facts_fts(rowid, key, value)
                        VALUES (new.rowid, new.key, new.value);
                    END;
                    -- Decisions get the same treatment so resume's
                    -- prior-decisions briefing can rank by relevance.
                    CREATE VIRTUAL TABLE IF NOT EXISTS decisions_fts USING fts5(
                        context, decision, content='decisions', content_rowid='id'
                    );
                    CREATE TRIGGER IF NOT EXISTS decisions_ai AFTER INSERT ON decisions BEGIN
                        INSERT INTO decisions_fts(rowid, context, decision)
                        VALUES (new.id, new.context, new.decision);
                    END;
                    CREATE TRIGGER IF NOT EXISTS decisions_ad AFTER DELETE ON decisions BEGIN
                        INSERT INTO decisions_fts(decisions_fts, rowid, context, decision)
                        VALUES ('delete', old.id, old.context, old.decision);
                    END;
                    """
                )
                # Seed any pre-existing rows so older sessions get
                # FTS coverage without a manual rebuild.
                c.execute(
                    "INSERT INTO facts_fts(rowid, key, value) "
                    "SELECT f.rowid, f.key, f.value FROM facts f "
                    "WHERE f.rowid NOT IN (SELECT rowid FROM facts_fts)"
                )
                c.execute(
                    "INSERT INTO decisions_fts(rowid, context, decision) "
                    "SELECT d.id, d.context, d.decision FROM decisions d "
                    "WHERE d.id NOT IN (SELECT rowid FROM decisions_fts)"
                )
                self._fts_available = True
            except sqlite3.OperationalError:
                self._fts_available = False

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

    def recall(self, query: str, *, limit: int = 10, now: float | None = None) -> list[Fact]:
        """Tokenized retrieval (FTS5) with lazy decay.

        Pipeline:
          1. Pull candidate rows whose key or value matches the query.
             FTS5's BM25 ranker gives us proper relevance; we fall
             back to LIKE if the host SQLite lacks FTS5.
          2. Apply exponential decay to each row's confidence.
          3. Prune rows below ``PRUNE_THRESHOLD`` from the DB.
          4. Return survivors sorted by decayed-confidence × recency.
        """
        clock = now if now is not None else time.time()
        with self._conn() as c:
            rows = self._search(c, query)
        return self._apply_decay_and_prune(rows, clock=clock, limit=limit)

    def _search(self, conn: sqlite3.Connection, query: str) -> list[sqlite3.Row]:
        """Try FTS5; fall back to LIKE on any FTS error (degraded
        environments, malformed queries, etc.)."""
        if self._fts_available:
            try:
                fts_query = self._build_fts_query(query)
                if fts_query:
                    return conn.execute(
                        """SELECT f.key, f.value, f.confidence, f.source, f.ts
                           FROM facts_fts m
                           JOIN facts f ON f.rowid = m.rowid
                           WHERE facts_fts MATCH ?
                           ORDER BY bm25(facts_fts), f.ts DESC""",
                        (fts_query,),
                    ).fetchall()
            except sqlite3.OperationalError:
                # FTS rejected the query — fall through to LIKE.
                pass
        like = f"%{query.lower()}%"
        return conn.execute(
            """SELECT key, value, confidence, source, ts FROM facts
               WHERE LOWER(key) LIKE ? OR LOWER(value) LIKE ?
               ORDER BY ts DESC""",
            (like, like),
        ).fetchall()

    @staticmethod
    def _build_fts_query(raw: str) -> str:
        """Turn a free-text query into an FTS5 expression. We escape
        each token by wrapping in double quotes so punctuation can't
        flip a token into an operator. Empty tokens are dropped; an
        empty expression returns '' which the caller treats as no
        match (and skips the FTS branch)."""
        tokens = [t for t in raw.split() if t.strip()]
        if not tokens:
            return ""
        # FTS5 doesn't allow embedded double quotes inside a "..." token —
        # they'd open a string. Strip them defensively.
        cleaned = [f'"{t.replace(chr(34), "")}"' for t in tokens if t.replace('"', "").strip()]
        return " ".join(cleaned)

    def all_facts(self, *, now: float | None = None) -> list[Fact]:
        clock = now if now is not None else time.time()
        with self._conn() as c:
            rows = c.execute(
                "SELECT key, value, confidence, source, ts FROM facts ORDER BY ts DESC"
            ).fetchall()
        return self._apply_decay_and_prune(rows, clock=clock, limit=None)

    def _apply_decay_and_prune(
        self,
        rows: list[sqlite3.Row],
        *,
        clock: float,
        limit: int | None,
    ) -> list[Fact]:
        survivors: list[Fact] = []
        to_prune: list[str] = []
        for r in rows:
            fact = Fact(**dict(r))
            decayed = fact.confidence_at(clock, self.half_life_seconds)
            if decayed < self.PRUNE_THRESHOLD:
                to_prune.append(fact.key)
                continue
            # Surface the decayed confidence — callers see the live value.
            survivors.append(Fact(
                key=fact.key, value=fact.value,
                confidence=decayed, source=fact.source, ts=fact.ts,
            ))
        if to_prune:
            with self._conn() as c:
                c.executemany("DELETE FROM facts WHERE key=?", [(k,) for k in to_prune])
        survivors.sort(key=lambda f: (f.confidence, f.ts), reverse=True)
        if limit is not None:
            return survivors[:limit]
        return survivors

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

    def search_decisions(
        self, query: str, *, job_id: str | None = None, limit: int = 20,
    ) -> list[Decision]:
        """FTS5-ranked search across reasoning decisions. Optionally
        scoped to a single job. Falls back to LIKE when FTS5 isn't
        available — same semantics, just slower + less precise."""
        with self._conn() as c:
            if self._fts_available:
                fts_query = self._build_fts_query(query)
                if fts_query:
                    try:
                        sql = (
                            "SELECT d.job_id, d.context, d.decision, d.ts FROM decisions_fts m "
                            "JOIN decisions d ON d.id = m.rowid "
                            "WHERE decisions_fts MATCH ?"
                        )
                        params: list = [fts_query]
                        if job_id is not None:
                            sql += " AND d.job_id = ?"
                            params.append(job_id)
                        sql += " ORDER BY bm25(decisions_fts), d.ts DESC LIMIT ?"
                        params.append(limit)
                        rows = c.execute(sql, params).fetchall()
                        return [Decision(**dict(r)) for r in rows]
                    except sqlite3.OperationalError:
                        pass
            like = f"%{query.lower()}%"
            sql = (
                "SELECT job_id, context, decision, ts FROM decisions "
                "WHERE LOWER(context) LIKE ? OR LOWER(decision) LIKE ?"
            )
            params: list = [like, like]
            if job_id is not None:
                sql += " AND job_id = ?"
                params.append(job_id)
            sql += " ORDER BY ts DESC LIMIT ?"
            params.append(limit)
            rows = c.execute(sql, params).fetchall()
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
