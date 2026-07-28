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

-- ── Slice 4: matching backend ────────────────────────────────────────────────
-- Bids, matches, and messages — the "two phones actually see each other" layer.
-- Written to by the matching Worker (AuctionBaby/matching/), which shares this
-- D1 database with the auth Worker (single source of truth for user identity).
CREATE TABLE IF NOT EXISTS bids (
  id           TEXT PRIMARY KEY,
  bidder_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lot_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount       INTEGER NOT NULL,
  note         TEXT,
  status       TEXT NOT NULL DEFAULT 'pending',   -- pending | accepted | declined | withdrawn
  gilded       INTEGER NOT NULL DEFAULT 0,        -- 0/1 bool
  insured      INTEGER NOT NULL DEFAULT 0,        -- 0/1 bool
  is_whisper   INTEGER NOT NULL DEFAULT 0,        -- 0/1 bool
  prompt_ref   TEXT,                              -- optional quote of her prompt answer
  created_at   INTEGER NOT NULL,
  resolved_at  INTEGER
);
-- The inbox query — "her pending bids, newest first" — hits this hard.
CREATE INDEX IF NOT EXISTS idx_bids_lot_status ON bids(lot_id, status, created_at DESC);
-- Bidder's outgoing history.
CREATE INDEX IF NOT EXISTS idx_bids_bidder ON bids(bidder_id, created_at DESC);

CREATE TABLE IF NOT EXISTS matches (
  id           TEXT PRIMARY KEY,
  -- One accepted bid = one match. UNIQUE enforces that on the DB, not just app.
  bid_id       TEXT NOT NULL UNIQUE REFERENCES bids(id) ON DELETE CASCADE,
  bidder_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lot_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount       INTEGER NOT NULL,
  phase        TEXT NOT NULL DEFAULT 'chatting', -- chatting | dateDone | closed
  created_at   INTEGER NOT NULL,
  -- Bumble-style 24h freshness clock; cleared on the receiver's first reply.
  expires_at   INTEGER,
  -- Slice 3-adjacent — the "Reserve the date" fee state, if paid.
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
  -- When the OTHER side loaded messages past this one (drives read receipts).
  seen_at      INTEGER
);
-- The chat-view query — "messages in this match, oldest first" — is the hot path.
CREATE INDEX IF NOT EXISTS idx_messages_match ON messages(match_id, created_at);

-- ── Slice 4b0: public profiles ───────────────────────────────────────────────
-- A user's profile as seen by OTHER users — bio, prompts, starting bid, etc.
-- Split from `users` (which is auth identity) so a delete-my-account cascade
-- also clears the public face; and so a future "hide my profile" flag is a
-- simple soft-delete on this table rather than surgery on the identity row.
--
-- Age is NOT stored here — it's derived from `users.date_of_birth` at query
-- time to keep the single source of truth. Photos are NOT stored here
-- either — that needs R2 + moderation and is a slice on its own.
CREATE TABLE IF NOT EXISTS profiles (
  user_id             TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  role                TEXT NOT NULL,             -- 'man' | 'woman'
  name                TEXT NOT NULL,
  location            TEXT,
  bio                 TEXT,
  hue                 REAL NOT NULL DEFAULT 0.6, -- 0..1 portrait tone
  starting_bid        INTEGER,                   -- women only, dollars
  archetype           TEXT,                      -- men only: 'none' | 'goodGuy' | ... | 'trillionaire'
  opening_bid_script  TEXT,                      -- women only, canned first message
  prompts_json        TEXT,                      -- JSON: [{"question":"…","answer":"…"}]
  interests_json      TEXT,                      -- JSON: ["Art","Travel",…]
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);
-- Floor feed (`GET /users/floor?role=woman`) hits this hard, newest first.
CREATE INDEX IF NOT EXISTS idx_profiles_role_updated ON profiles(role, updated_at DESC);
