-- Migration 001 — slice 2 (push notifications).
-- Adds the device_tokens table. Idempotent (IF NOT EXISTS).
-- Skip this if you're running schema.sql for the first time.

CREATE TABLE IF NOT EXISTS device_tokens (
  token         TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform      TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
