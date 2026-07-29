-- Migration 006 — slice 4c1b (rate limiting).
-- Fixed-window counters keyed by (key, window_ms). `key` is a semantic slug
-- like "bid.place:<userId>" or "message.send:<userId>"; `window_ms` is the
-- floor of Date.now() rounded to the window size for that limit. UPSERT to
-- bump; read to check. Skip if you're running the current schema.sql for
-- the first time.

CREATE TABLE IF NOT EXISTS rate_counters (
  key         TEXT NOT NULL,
  window_ms   INTEGER NOT NULL,
  count       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (key, window_ms)
);
