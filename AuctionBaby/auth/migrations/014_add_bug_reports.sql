-- Bug reports: users submit bugs, admins triage them.
CREATE TABLE IF NOT EXISTS bug_reports (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description  TEXT NOT NULL,
  steps        TEXT,
  severity     TEXT NOT NULL DEFAULT 'medium',  -- low | medium | high
  device       TEXT,
  status       TEXT NOT NULL DEFAULT 'open',    -- open | closed
  created_at   INTEGER NOT NULL,
  closed_at    INTEGER,
  closed_by    TEXT
);
CREATE INDEX IF NOT EXISTS idx_bug_reports_status ON bug_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_reports_user ON bug_reports(user_id, created_at DESC);
