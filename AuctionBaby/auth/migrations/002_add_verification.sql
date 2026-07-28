-- Migration 002 — slice 3 (real verification).
-- Adds verification columns to users. NOT idempotent on the ALTER lines
-- (SQLite has no `IF NOT EXISTS` for ADD COLUMN) — safe to run once, fails
-- loudly if any column already exists. Skip this if you're running the
-- current schema.sql for the first time.

ALTER TABLE users ADD COLUMN verified_at         INTEGER;
ALTER TABLE users ADD COLUMN verification_vendor TEXT;
ALTER TABLE users ADD COLUMN verification_ref    TEXT;
ALTER TABLE users ADD COLUMN verification_status TEXT NOT NULL DEFAULT 'unstarted';

CREATE INDEX IF NOT EXISTS idx_users_verif_pending ON users(verification_status)
  WHERE verification_status = 'pending';
