-- Migration 016 — email + password login.
--
-- WHY: Sign in with Apple was the only way into the web app, and it only
-- works through a popup (Apple POSTs to the redirect URI in redirect mode,
-- and GitHub Pages is static, so it cannot receive that POST). Firefox blocks
-- or breaks that popup, so a Firefox user who lost their localStorage session
-- had no way back into an account that still existed. This adds a second,
-- self-contained login path that depends on no third party.
--
-- The hash is PBKDF2-SHA256, 210k iterations, per-user random 16-byte salt.
-- Both are stored hex-encoded. `password_hash` NULL means the account has no
-- password and can only be reached through Apple.
ALTER TABLE users ADD COLUMN password_hash TEXT;
ALTER TABLE users ADD COLUMN password_salt TEXT;
ALTER TABLE users ADD COLUMN password_set_at INTEGER;

-- One password login per email address, case-insensitive.
--
-- Deliberately PARTIAL (only rows that actually have a password). Apple
-- accounts are exempt because Apple hands out private-relay addresses and may
-- give us no email at all, so several Apple rows can legitimately share a NULL
-- or repeated email — a plain UNIQUE(email) would reject those.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_password_email
  ON users(lower(email)) WHERE password_hash IS NOT NULL;

-- NOTE on apple_sub: it is UNIQUE NOT NULL and cannot be relaxed without
-- rebuilding the table, which is not worth the risk on a live users table.
-- Password accounts therefore carry a synthetic sentinel, "pw:<uuid>", which
-- satisfies the constraint and can never collide with a real Apple subject.
-- Code that means "is this an Apple account?" must test for that prefix
-- rather than assuming apple_sub implies Apple.
