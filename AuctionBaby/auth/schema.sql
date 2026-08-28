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
  verification_status    TEXT NOT NULL DEFAULT 'unstarted',
  verification_selfie_score REAL,
  verification_face_match_score REAL,
  verification_liveness_passed INTEGER,

  -- ── Batch L: session-based admin auth ──────────────────────────────────────
  -- 0 = normal user. 1 = admin (can hit /admin/*). Flipped out-of-band via
  --   wrangler d1 execute — no in-app self-grant. Complements the static
  --   APP_SHARED_SECRET which is now only used for Worker-to-Worker calls
  --   (push send, reservation mirror).
  is_admin               INTEGER NOT NULL DEFAULT 0,

  -- ── Batch R: reversible ban ────────────────────────────────────────────────
  -- Epoch-ms cutoff. When set + in the future the user is soft-banned:
  --   handleAppleAuth  rejects new sign-ins with 403
  --   handleUpsertMyProfile  rejects profile writes
  --   matching Worker handlePlaceBid  rejects bids from OR to this user
  -- Existing sessions run to their TTL — this isn't a hard ban. Use
  -- DELETE /admin/users/:id for that. Lift with POST /admin/users/:id/unsuspend.
  suspended_until        INTEGER
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
  seen_at      INTEGER,
  -- Single-slot emoji reaction (either party writes; overwrites are visible
  -- to both). Nil = no reaction. Matches ChatMessage.reaction on the client.
  reaction     TEXT,
  -- Photo messages (migration 015, 2026-08): optional R2/public photo URL.
  -- Client sends { text: "", photo: "<url>" }; at least one of text/photo
  -- must be non-empty. text stays NOT NULL ("" = photo-only).
  photo        TEXT
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
  -- Batch U: R2-hosted photos. JSON array of {id, key}. Ordering is
  -- positional (index 0 = primary). Bytes live in the PHOTOS R2 bucket;
  -- the public URL is PHOTOS_PUBLIC_URL + "/" + key, resolved at read time
  -- so the CDN domain is swappable without a DB rewrite.
  photos_json         TEXT,
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);
-- Floor feed (`GET /users/floor?role=woman`) hits this hard, newest first.
CREATE INDEX IF NOT EXISTS idx_profiles_role_updated ON profiles(role, updated_at DESC);

-- ── Slice 4c1a: server-enforced blocks ───────────────────────────────────────
-- A directional edge from blocker → blocked. A blocked pair (either direction)
-- can't see each other on the floor, can't place bids either way, and can't
-- send new messages on existing matches. Enforcement lives in the auth
-- Worker (floor) and matching Worker (bids/messages).
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      TEXT,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);

-- ── Slice 4c1b: rate-limit counters ──────────────────────────────────────────
-- Fixed-window counters. `key` is a semantic slug (e.g. "bid.place:<userId>"),
-- `window_ms` is the floor of Date.now() rounded down to the window size for
-- that limit. Matching Worker bumps on writes; over cap → 429. Cleanup is a
-- follow-up; old rows are cheap.
CREATE TABLE IF NOT EXISTS rate_counters (
  key         TEXT NOT NULL,
  window_ms   INTEGER NOT NULL,
  count       INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (key, window_ms)
);

-- ── Slice 5: server-side reports ─────────────────────────────────────────────
-- Blocks stop reach; reports flag content for admin review. Same shared D1.
CREATE TABLE IF NOT EXISTS reports (
  id           TEXT PRIMARY KEY,
  reporter_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason       TEXT NOT NULL,
  context      TEXT,
  created_at   INTEGER NOT NULL,
  status       TEXT NOT NULL DEFAULT 'open',
  resolved_at  INTEGER,
  resolved_by  TEXT
);
CREATE INDEX IF NOT EXISTS idx_reports_target ON reports(target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_open_created ON reports(status, created_at DESC);

-- ── Batch Q: admin audit log ─────────────────────────────────────────────────
-- One row per /admin/* mutation. Answers "who did what to whom, and when."
CREATE TABLE IF NOT EXISTS admin_audit (
  id          TEXT PRIMARY KEY,
  actor_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  target_id   TEXT,
  note        TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_target ON admin_audit(target_id, created_at DESC);

-- ── Bug reports ──────────────────────────────────────────────────────────────
-- Users submit bugs from the app; admins triage them in the admin console.
CREATE TABLE IF NOT EXISTS bug_reports (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  description  TEXT NOT NULL,
  steps        TEXT,
  severity     TEXT NOT NULL DEFAULT 'medium',  -- low | medium | high
  device       TEXT,
  status       TEXT NOT NULL DEFAULT 'open',    -- open | closed
  created_at   INTEGER NOT NULL,
  closed_at    INTEGER,
  closed_by    TEXT
);
CREATE INDEX IF NOT EXISTS idx_bug_reports_status ON bug_reports(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bug_reports_user ON bug_reports(user_id, created_at DESC);
