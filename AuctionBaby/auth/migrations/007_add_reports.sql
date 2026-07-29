-- Migration 007 — slice 5 (server-side reports).
-- Reports are the moderation partner to blocks: blocks stop reach, reports
-- flag content for admin review. Both are shared-D1 tables; the auth Worker
-- owns the write endpoints. Skip if you're running the current schema.sql
-- for the first time.

CREATE TABLE IF NOT EXISTS reports (
  id           TEXT PRIMARY KEY,
  reporter_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason       TEXT NOT NULL,
  context      TEXT,
  created_at   INTEGER NOT NULL,
  status       TEXT NOT NULL DEFAULT 'open',
  resolved_at  INTEGER,
  resolved_by  TEXT
);
-- Fast "how many open reports on this user?" for admin triage weighting.
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_id, created_at DESC);
-- Admin queue query hits this hardest — open reports, newest first.
CREATE INDEX IF NOT EXISTS idx_reports_open_created ON reports(status, created_at DESC);
