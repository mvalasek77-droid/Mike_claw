-- Migration 004 — slice 4b0 (public profiles).
-- Adds the profiles table. Idempotent (IF NOT EXISTS).
-- Skip if you're running the current schema.sql for the first time.

CREATE TABLE IF NOT EXISTS profiles (
  user_id             TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  role                TEXT NOT NULL,
  name                TEXT NOT NULL,
  location            TEXT,
  bio                 TEXT,
  hue                 REAL NOT NULL DEFAULT 0.6,
  starting_bid        INTEGER,
  archetype           TEXT,
  opening_bid_script  TEXT,
  prompts_json        TEXT,
  interests_json      TEXT,
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_profiles_role_updated ON profiles(role, updated_at DESC);
