-- Migration 003 — slice 4 (matching backend).
-- Adds bids/matches/messages tables. Idempotent (IF NOT EXISTS).
-- Skip if you're running the current schema.sql for the first time.

CREATE TABLE IF NOT EXISTS bids (
  id           TEXT PRIMARY KEY,
  bidder_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lot_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount       INTEGER NOT NULL,
  note         TEXT,
  status       TEXT NOT NULL DEFAULT 'pending',
  gilded       INTEGER NOT NULL DEFAULT 0,
  insured      INTEGER NOT NULL DEFAULT 0,
  is_whisper   INTEGER NOT NULL DEFAULT 0,
  prompt_ref   TEXT,
  created_at   INTEGER NOT NULL,
  resolved_at  INTEGER
);
CREATE INDEX IF NOT EXISTS idx_bids_lot_status ON bids(lot_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bids_bidder ON bids(bidder_id, created_at DESC);

CREATE TABLE IF NOT EXISTS matches (
  id           TEXT PRIMARY KEY,
  bid_id       TEXT NOT NULL UNIQUE REFERENCES bids(id) ON DELETE CASCADE,
  bidder_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lot_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount       INTEGER NOT NULL,
  phase        TEXT NOT NULL DEFAULT 'chatting',
  created_at   INTEGER NOT NULL,
  expires_at   INTEGER,
  reserved_amount_cents  INTEGER,
  reserved_at            INTEGER
);
CREATE INDEX IF NOT EXISTS idx_matches_bidder ON matches(bidder_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_matches_lot ON matches(lot_id, created_at DESC);

CREATE TABLE IF NOT EXISTS messages (
  id           TEXT PRIMARY KEY,
  match_id     TEXT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  from_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text         TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  seen_at      INTEGER
);
CREATE INDEX IF NOT EXISTS idx_messages_match ON messages(match_id, created_at);
