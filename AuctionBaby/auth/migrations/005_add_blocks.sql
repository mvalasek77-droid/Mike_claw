-- Migration 005 — slice 4c1a (server-enforced blocks).
-- A directional edge: (blocker_id, blocked_id, reason?). A blocked pair
-- can't see each other on the floor, can't send bids either way, and can't
-- send new messages on existing matches. Idempotent (IF NOT EXISTS).
-- Skip if you're running the current schema.sql for the first time.

CREATE TABLE IF NOT EXISTS blocks (
  blocker_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      TEXT,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
-- Fast "who blocked me?" for enforcement on inbound bids/messages.
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);
