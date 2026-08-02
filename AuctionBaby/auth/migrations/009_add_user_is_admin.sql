-- Migration 009 — session-based admin auth (Batch L).
-- Replaces the static-bearer admin gate on user-facing endpoints
-- (/admin/reports*, /admin/users*, /admin/verify) with a session-token
-- check that also requires `users.is_admin = 1`. Anyone with the app
-- can no longer become admin by discovering the static bearer.
--
-- Internal Worker-to-Worker calls (/push/send from matching Worker,
-- /internal/reservations/mark from consumables Worker) keep the static
-- bearer — they don't have session tokens to present.
--
-- Grant admin: `wrangler d1 execute auctionbaby-users --command \
--   "UPDATE users SET is_admin = 1 WHERE id = '<founder-user-id>';"`

ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0;
