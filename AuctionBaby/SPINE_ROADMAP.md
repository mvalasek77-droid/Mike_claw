# Auction Baby — The Spine

The backbone that turns the app from a beautifully-finished single-player
simulation into a real two-sided dating app that strangers can use to meet
each other. Everything above this line (mechanics, monetization, copy, safety
UI, retention loops, the Stripe reservation fee) is already shipped; the
spine is the "real users" layer beneath it.

Every slice below preserves what already works — **Demo Mode and the local
single-player path stay identical**. The spine is purely additive: real users
opt into it (Sign in with Apple); demo/preview users never touch it.

## The slices, in dependency order

| # | Slice | Status | What it unlocks |
|---|---|---|---|
| 1 | **Server-side user identity** (Sign in with Apple + D1 users) | ✅ shipped | Every real user has a durable server identity; foundation for everything below |
| 2 | **Push notifications** (APNs via the auth Worker) | ✅ shipped | A new bid, an accepted bid, or a message wakes the phone even when the app is closed |
| 3 | **Real verification** (server-owned truth, vendor for liveness/ID) | ✅ shipped | The blue check *means* something; fake selfies can't get through |
| 4 | **Matching backend** (bids/matches/messages server-side) | 🔨 4a shipped (data plane); 4b UI migration next | Two real phones actually see each other. Where safety, rate-limiting, and reports live. |
| 5 | **Server-enforced moderation** (reports → admin queue → blocks) | ⏳ planned | User reports actually reach the admin queue; blocks enforced server-side |

Rough scope per slice: **1–4 focused code sessions of mine + a few hours of
Founder setup** (Apple capabilities, Cloudflare bindings, APNs auth key, a
verification vendor account). Nothing here is one commit — it's a multi-week
build.

---

## Slice 1 — Server-side user identity  ✅

**Goal:** any real user can sign in with Apple and receive a durable server
identity (a `serverUserId` + a session token) that persists across launches,
device restores, and app reinstalls. This slice adds **no user-visible
features** other than the sign-in button and a "signed in" state — its value
is that it lays the tracks every later slice runs on.

### What's added
- **New Cloudflare Worker: `AuctionBaby/auth/`**
  - `POST /auth/apple` — verifies the Apple identity JWT against Apple's
    JWKS, upserts a row in D1, returns `{ userId, sessionToken, isNew }`
  - `GET /me` — reads a session token, returns the user record
  - `POST /auth/logout` — invalidates a session
  - `GET /health` — liveness
- **D1 database: `auctionbaby-users`** with one table: `users`
  (id, apple_sub, email, name, created_at, last_seen_at)
- **Sessions** — stateless HMAC-SHA256-signed opaque tokens
  (`userId.expiry.signature`). No DB round-trip on every request.
- **Client: `AuthService.swift`** — owns the session token (Keychain via
  SecureStore) + `serverUserId` (published so views observe it). Sends
  `Authorization: Bearer <sessionToken>` on authed calls.
- **Onboarding:** a "Sign in with Apple" button *above* the manual fields.
  Tapping it → SIWA flow → server exchange → session stored → name pre-filled.
  Skipping it → the existing local-only path stays intact (this is what Demo
  Mode uses).

### What stays the same
- **Demo Mode** — typing `demo` still enters demo mode with no auth.
- **Local storage of the profile** — `AuctionStore.me` is still the source of
  truth for the UI; the server identity is *alongside* it, not a replacement.
- **Every existing feature** — bids, matches, chat, ratings, Reserve-the-date,
  Stripe payouts — all continue to work exactly as they do today.

### What's deliberately NOT in slice 1
- Real bids/matches between users (that's slice 4 — matching backend).
- Push notifications (slice 2).
- Real verification (slice 3).
- Any migration of the on-device sim floor to real users.

Slice 1 shipping value on its own: **real users get real accounts**, and
`serverUserId` is the join key every future slice will use.

### Founder-side setup (once, when slice 1 is ready to deploy)
1. Enable "Sign in with Apple" capability for the app in your Apple
   Developer account (Certificates, IDs & Profiles → your identifier).
2. In Xcode → Signing & Capabilities, add **Sign in with Apple**.
3. `wrangler d1 create auctionbaby-users` → paste the `database_id` into
   `AuctionBaby/auth/wrangler.toml`.
4. `wrangler d1 execute auctionbaby-users --file=AuctionBaby/auth/schema.sql`
5. `cd AuctionBaby/auth && wrangler secret put SESSION_SECRET` (any long
   random string).
6. `wrangler deploy` (staging), then `--env production` when proven.
7. Paste the deployed URL into `Config/Secrets.xcconfig` as `AB_AUTH_URL`.

---

## Slice 2 — Push notifications  ✅

**What shipped:**

- **Auth Worker gains push:** new `device_tokens` D1 table, three new
  endpoints — `POST /devices/register` and `POST /devices/unregister`
  (session-authed), and `POST /push/send` (admin-gated by
  `APP_SHARED_SECRET`) that any other Worker can call when it needs to
  notify a user.
- **APNs HTTP/2 dispatcher** with ES256-signed JWT auth (`.p8` key
  imported via `wrangler secret put`), JWT cached module-scoped for ~50 min
  per Apple's rate limits. Tokens returning `410 Unregistered` or
  `400 BadDeviceToken` are auto-pruned so dead devices don't keep getting
  silently retried.
- **iOS client:** minimal `AppDelegate` (SwiftUI's only route to APNs
  callbacks), a `PushService` singleton that requests authorization, hex-
  encodes the device token, buffers until a session is available, and POSTs
  to `/devices/register`. Foreground presentation shows banners so
  in-app bids aren't silently dropped.
- **Sign-out cleanup:** `AuthService.onSignedOut` fires
  `PushService.onSignedOut()` while the session is still valid, so the
  device is un-registered server-side before the token is cleared.
- **Sandbox vs production:** DEBUG builds register as `apns_sandbox`,
  Release builds as `apns` — the Worker picks the right APNs host per
  token.

**Trigger events wired so far:** none yet (this slice is the pipe).
When slice 4 (matching backend) lands, each event — new bid, accept,
message, refund — calls `POST /push/send` on the auth Worker.

**What isn't in slice 2:**
- Deep-linking into a specific screen from a notification tap (later slice).
- Rich media attachments / notification service extensions (later).
- Per-notification preferences (slice 5-ish, comes with a settings screen).

---

## Slice 3 — Real verification  ✅

**What shipped:** the blue check is now server-owned truth (`users.verified_at`).
Client-side `me.verified` mirrors it, but the server is the source; a
fraudulently-set client flag doesn't stick.

**Vendor pluggability:** the pipeline is vendor-agnostic. Set
`VERIFICATION_VENDOR` on the Worker to pick which one is active. Three
vendors ship today:

- **`manual`** (default) — the founder approves/rejects via
  `POST /admin/verify` (admin-gated by `APP_SHARED_SECRET`). Fine at low
  volume. This is the "we're live but you're bootstrapping" mode.
- **`stub`** — auto-passes instantly. Dev/staging only; **do not enable in
  production** (there's no real check happening).
- **`persona` / `onfido`** — routes are wired but the vendor SDK + payload
  translation is the next drop-in. Adding either is roughly a day: a
  `nextStepFor` branch that returns their SDK init token, and translating
  their webhook shape into the canonical `{ ref, userId, status }`.

**Endpoints:**
- `POST /verify/start` [auth] — idempotent; a user who passed just gets the
  passed state back; a pending user reuses the same session.
- `POST /verify/webhook` — signature-verified (HMAC over rawBody), refuses to
  flip anyone whose stored `verification_ref` doesn't match — so a leaked
  webhook secret still can't verify arbitrary users.
- `POST /admin/verify` — manual approve/reject; fires the "you're verified"
  push (slice 2 pays off) so the app catches up without polling.

**Client:**
- `RemoteUser` gains `verifiedAt` + `verificationStatus` on `/me`.
- `AuthService.onVerified` hook fires on a nil→verified transition — the app
  root wires it to flip the local flag, so a background push landing while
  the app is closed lights up the check the moment the user opens it.
- `VerificationSheet` uses the server flow when signed in; keeps the
  simulated scan for demo/local-only builds so App Review sees the full
  animation with nothing configured.

**Cost note:** the `manual` vendor is free. A real KYC vendor will run
~$1.50–$3 per verification. Consider gating verification behind Pass, or
making the first successful pass free-forever per user.

---

## Slice 4 — Matching backend  🔨

The big one. Broken into three sub-slices:

### 4a — Data plane  ✅

**What shipped:**

- **New Cloudflare Worker** at `AuctionBaby/matching/`, sharing the
  `auctionbaby-users` D1 with the auth Worker so `bidder_id` / `lot_id` are
  foreign keys into `users` — one identity, one database.
- **Schema:** three tables — `bids`, `matches`, `messages`. Indexed for the
  hot paths (her pending inbox, his outgoing history, chat scrollback).
- **Endpoints, all session-authed:**
  - Bids: `POST /bids`, `GET /bids/incoming`, `GET /bids/outgoing`,
    `POST /bids/:id/{accept,decline,withdraw}`.
  - Matches: `GET /matches`, `GET /matches/:id`,
    `POST /matches/:id/messages`, `.../mark-seen`, `.../mark-date-done`.
- **Stateless auth** via the same HMAC session tokens the auth Worker
  issues — shared `SESSION_SECRET`, no cross-Worker round-trip per request.
- **Push triggers** for every event that matters to the other party (bid
  received, bid accepted, whisper nodded, message received, date-done
  advanced) — dispatched to the auth Worker's `/push/send`, so the
  notification pipe from slice 2 is the single owner of APNs.
- **Server-side guards:** ownership check on every match-scoped write,
  UNIQUE(bid_id) on matches (double-tap accept can't dupe), self-bid
  rejected, 1B amount ceiling as defense-in-depth.
- **Client `MatchingService`:** typed calls for every endpoint, injected at
  app root. Doesn't yet replace the on-device sim — this is the plumbing.

**Verifiable today:** the full bid → accept → message flow runs
end-to-end via curl between two signed-in users, and pushes wake both
phones. See `AuctionBaby/matching/README.md` for the curl script.

### 4b — UI migration  🔨

#### 4b0 — Public profile sync  ✅

**What shipped:** the *missing piece* before UI migration can be useful —
two real users can't see each other on the floor unless their profiles
have been mirrored to the server. Purely additive; UI is untouched.

- **New D1 table** `profiles`, split from `users` so a delete-my-account
  cascade wipes the public face too, and so a future "hide my profile"
  flag is a soft-delete here rather than on the identity row.
- **Endpoints on the auth Worker:**
  - `PUT /me/profile` — upsert my public profile (name/bio/hue/prompts/
    interests/starting_bid/archetype/opening_bid_script). Idempotent.
    Refuses role-flip (409).
  - `GET /me/profile` — my current server view.
  - `GET /users/:id/profile` — peer lookup for match/chat displays.
  - `GET /users/floor?role=&limit=&cursor=` — the paginated feed. Cursor
    is the last item's `updated_at` — no OFFSET drift as writes happen.
    Excludes the caller.
- **Age derived** from `users.date_of_birth` on read via JOIN — one query,
  never stored twice. Photos NOT in slice 4b0 (needs R2 + moderation).
- **Client `ProfileService`** with typed calls for all four endpoints.
  `AuctionStore.onProfileChanged` hook fires at every mutation point
  (register, updateOpeningBidScript, equipArchetype, setStartingBid);
  app root wires it to `profileSync.uploadMyProfile(from:)` — Demo Mode
  is skipped, local-only sessions are a silent no-op inside the service.

**Not in 4b0:** the SwiftUI screens still read from the on-device sim.
Wiring `AuctionFeedView` etc. to consume `fetchFloor()` when signed in is
slice 4b1.

#### 4b1 — UI wiring  ✅

Wire the SwiftUI screens (`AuctionFeedView`, `IncomingBidsView`, `BidSheet`,
`ChatView`, `MatchesView`) to consume `MatchingService` + `ProfileService`
for signed-in users. The on-device sim stays as fallback for Demo Mode +
local-only sessions.

- **4b1a** — Floor sourced from `/users/floor`; `AuctionStore.remoteFloor` +
  `isRemoteFloor` flip once at least one real profile exists. Demo/local
  sessions keep seeing the sim.
- **4b1b** — Woman's inbox from `/bids/incoming` with LEFT-JOIN peer
  snapshots; `acceptRemote` / `declineRemote` route through the Worker,
  preserving optimistic UI.
- **4b1c** — Bidder writes real bids via `POST /bids` from BidSheet, with
  Gavel debit rollback on failure. Optimistic outbox entry lands in
  `remoteOutgoingBids`.
- **4b1d** — Matches list + chat via `/matches`, `/matches/:id`,
  `/matches/:id/messages`. `AuctionStore.remoteMatches` /
  `effectiveMatches` — MatchesView and ChatView read through them and
  send goes through the Worker with optimistic bubble + rollback. Accept
  writes the fresh match straight into `remoteMatches` so the woman sees
  the conversation right after tapping accept.

Closes the two-sided loop end-to-end: bid → accept → chat, all through
the matching Worker for signed-in users.

### 4c — Real-time + safety hardening

- **4c1a — Server-enforced blocks.** ✅ Shipped. New `blocks(blocker_id,
  blocked_id, reason, created_at)` table in the shared D1; auth Worker
  exposes `POST /me/blocks`, `DELETE /me/blocks/:userId`,
  `GET /me/blocks`. Auth Worker's `/users/floor` and matching Worker's
  inbox / outgoing / matches queries filter blocked pairs both directions;
  `POST /bids` and `POST /matches/:id/messages` return 403 on either-side
  block. Client wires `AuctionStore.blockAndReport` to the auth Worker via
  `AuthService.blockUser(userId:reason:)` when signed in (Demo Mode +
  local-only sessions stay local-block only).
- **4c1b — Rate limiting.** ✅ Shipped. `rate_counters(key, window_ms,
  count)` in the shared D1; `checkRate(...)` bumps-then-checks with
  `INSERT ... ON CONFLICT DO UPDATE ... RETURNING count` so racers get
  deterministic enforcement. Gated `POST /bids` at 20/hour per bidder and
  `POST /matches/:id/messages` at 30/minute per sender. Over-cap = 429
  with `Retry-After`; MatchingService surfaces the Worker's copy and
  skips ErrorMonitor for 429s.
- **4c2 — Real-time via Durable Objects.** ⏳ Per-user inbox + per-match
  chat room, WebSocket fan-out for real-time chat / bid arrival while
  both apps are open. Push handles the "app is closed" case; DOs handle
  "app is open."

---

## Slice 5 — Server-enforced moderation  ✅

Report + block are the moderation dyad. Blocks (4c1a) cut off reach;
reports (this slice) flag content for admin review.

**Shipped:**
- `reports(id, reporter_id, target_id, reason, context?, created_at,
  status, resolved_at, resolved_by)` table in the shared D1 (migration
  007).
- Auth Worker `POST /me/reports { userId, reason, context? }`,
  rate-limited to 30/day per reporter via the 4c1b `rate_counters` table.
- Admin `GET /admin/reports?status=&limit=&cursor=` triage queue and
  `POST /admin/reports/:id/resolve { status, note? }`, both gated by
  `APP_SHARED_SECRET` (same admin bearer as `/push/send`).
- Client: `AuthService.reportUser(userId:reason:context:)`, new
  `AuctionStore.onReportRequested` hook fires alongside `onBlockRequested`
  inside `blockAndReport`, wired at app root — one tap on ReportSheet
  files both the block AND the moderator-visible report.
- Blocks (from 4c1a) are already enforced at the matching Worker layer.

---

## Legal + operational reality checks that come with the spine

The moment strangers can message each other, several things start mattering
that don't matter today:

- **Privacy laws** — GDPR (EU), CCPA (California), PIPEDA (Canada). Data
  subject rights (export + delete) become real endpoints, not just policy
  language. Slice 1 already stores `email` and `apple_sub` — a minimal
  amount of PII — and needs a delete-my-account flow to satisfy 6.5.1 in
  App Review.
- **Age verification** — 17+ is the App Store rating, but you should be
  ready to explain how you keep 17-and-unders out (SIWA doesn't tell you
  age; a `date_of_birth` collected at onboarding + Apple's parental
  controls are the standard defense).
- **Safety plan** — Apple + regulators expect a documented plan for:
  blocking, reporting, in-app safety resources, rapid takedown of harmful
  content, and moderator response time SLAs.
- **DMCA / content takedown** — you'll get takedown requests. Have a
  DMCA agent registered.

None of these block slice 1, but you should have counsel spinning up on
them in parallel — by the time slice 4 ships, you need answers.

---

## Status log

- **2026-07-28** — Roadmap written.
- **2026-07-28** — Slice 1 shipped (SIWA + D1 users).
- **2026-07-28** — Slice 2 shipped (push notifications).
- **2026-07-28** — Slice 3 shipped (verification: manual mode default, vendor adapters pluggable).
- **2026-07-28** — Slice 4a shipped (matching data plane: Worker, schema, endpoints, push wiring, client service). 4b (UI migration) is next.
- **2026-07-28** — Slice 4b0 shipped (public profile sync: new profiles table, /me/profile PUT/GET, /users/:id/profile, /users/floor paginated feed, client ProfileService). Unblocks 4b1 (UI wiring).
- **2026-07-28** — Slice 4b1 shipped in four sub-slices (a: real floor; b: real inbox + accept/decline; c: real bid write; d: matches list + chat). Two-sided loop complete for signed-in users. Next: 4c real-time + safety hardening.
- **2026-07-28** — Slice 4c1a shipped (server-enforced blocks: blocks table, /me/blocks endpoints on auth Worker, both-direction filtering on floor + matching Worker's list/write endpoints, client wire-up). Report & Block is now honored across devices.
- **2026-07-28** — Slice 4c1b shipped (rate limits: rate_counters table, 20 bids/hour per bidder, 30 messages/minute per sender, 429 + Retry-After on over-cap, client friendly-copy passthrough). Spam waves stop before they hit real users.
- **2026-07-28** — Slice 5 shipped (server-side reports: reports table, POST /me/reports rate-limited to 30/day, admin triage + resolve endpoints APP_SHARED_SECRET-gated, ReportSheet fires both block and report in one tap). Moderation dyad complete.
- **2026-07-28** — Slice 6 shipped (BlockedUsersView: signed-in users see their server-synced blocks with unblock; hydrates names/hues via /users/:id/profile; Demo/local sessions get a read-only mirror; wired into SafetyCenter). Block loop closed on the user side.
