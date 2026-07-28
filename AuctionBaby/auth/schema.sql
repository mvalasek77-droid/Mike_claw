-- Auction Baby — auth Worker D1 schema.
-- Apply with:  wrangler d1 execute auctionbaby-users --file=schema.sql
--
-- FRESH INSTALL: CREATE TABLE IF NOT EXISTS handles everything below.
-- ALREADY DEPLOYED: adding new columns to an existing table requires
-- ALTER TABLE ADD COLUMN — see AuctionBaby/auth/migrations/*.sql. SQLite
-- doesn't support IF NOT EXISTS on ADD COLUMN, so those files fail loudly
-- if a column already exists (which is what you want).

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
  last_seen_at  INTEGER NOT NULL,

  -- ── Slice 3: real verification ────────────────────────────────────────────
  -- Nullable timestamp of when the user's verification PASSED. This is the
  -- single source of truth for the app's blue check; the client mirrors it
  -- into UI state via /me. A previously-verified user can lose their check
  -- (fraud/reversal) by nulling this column.
  verified_at            INTEGER,
  -- Which vendor performed the check. 'manual' = founder-approved (bootstrap
  -- mode, low volume); 'persona' / 'onfido' = KYC SDK (future); 'stub' =
  -- dev/staging shortcut. Persisted for audit / rev-back.
  verification_vendor    TEXT,
  -- Vendor's own reference id for the check (Persona inquiry id, Onfido
  -- check id, or a UUID we mint for manual mode). Lets support look it up.
  verification_ref       TEXT,
  -- 'unstarted' | 'pending' | 'passed' | 'failed' | 'expired'
  verification_status    TEXT NOT NULL DEFAULT 'unstarted'
);

CREATE INDEX IF NOT EXISTS idx_users_apple_sub ON users(apple_sub);
CREATE INDEX IF NOT EXISTS idx_users_verif_pending ON users(verification_status)
  WHERE verification_status = 'pending';

-- ── Slice 2: push notifications ──────────────────────────────────────────────
-- One row per (user, device). A user can have multiple devices (iPhone + iPad),
-- and a device can only belong to one user at a time (re-registering the same
-- token on a different user account overwrites — the previous user simply
-- stops receiving on that device, which is what they'd expect).
--
-- `platform` distinguishes sandbox (dev/TestFlight-internal) from production
-- so we hit the right APNs host. `apns` = production. `apns_sandbox` = dev.
CREATE TABLE IF NOT EXISTS device_tokens (
  token         TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform      TEXT NOT NULL,   -- 'apns' | 'apns_sandbox'
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
