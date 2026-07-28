-- Auction Baby — auth Worker D1 schema.
-- Apply with:  wrangler d1 execute auctionbaby-users --file=schema.sql
-- Safe to re-run (all statements are IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS users (
  -- Our stable internal id, a UUID string. This is the `serverUserId` the app
  -- carries around and every future slice (matching, moderation) joins on.
  id            TEXT PRIMARY KEY,
  -- Apple's stable per-user, per-team subject. NEVER changes for a given
  -- Apple ID + team combination; the join key we look up on repeat sign-in.
  apple_sub     TEXT UNIQUE NOT NULL,
  -- Apple gives us the email only on the FIRST sign-in (or if the user
  -- revokes and re-grants). May be a private-relay address (@privaterelay.
  -- appleid.com) — don't try to email through relay without Apple's SMTP
  -- config. Optional; a user can revoke email scope.
  email         TEXT,
  -- Full name is also only given on FIRST sign-in. Optional (user can hide).
  name          TEXT,
  -- Client-authored date of birth, collected at onboarding. Age gating on
  -- the app is 17+; App Review expects a documented mechanism. Stored as
  -- yyyy-mm-dd text so timezone math never lies to us.
  date_of_birth TEXT,
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_users_apple_sub ON users(apple_sub);
