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
| 1 | **Server-side user identity** (Sign in with Apple + D1 users) | 🚧 in progress | Every real user has a durable server identity; foundation for everything below |
| 2 | **Push notifications** (APNs via the auth Worker) | ⏳ planned | A new bid, an accepted bid, or a message wakes the phone even when the app is closed |
| 3 | **Real verification** (server-owned truth, vendor for liveness/ID) | ⏳ planned | The blue check *means* something; fake selfies can't get through |
| 4 | **Matching backend** (bids/matches/messages server-side) | ⏳ planned | Two real phones actually see each other. Where safety, rate-limiting, and reports live. |
| 5 | **Server-enforced moderation** (reports → admin queue → blocks) | ⏳ planned | User reports actually reach the admin queue; blocks enforced server-side |

Rough scope per slice: **1–4 focused code sessions of mine + a few hours of
Founder setup** (Apple capabilities, Cloudflare bindings, APNs auth key, a
verification vendor account). Nothing here is one commit — it's a multi-week
build.

---

## Slice 1 — Server-side user identity  🚧

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

## Slice 2 — Push notifications  ⏳

**Trigger events:** new bid received, bid accepted, new message, date
reserved, refund landed.

**Approach:** the auth Worker persists per-user APNs device tokens (a new
`device_tokens` table in D1), and each other Worker calls a shared
`sendPush(userId, payload)` helper. Uses APNs HTTP/2 with an Auth Key (.p8)
you generate in your Apple Developer account.

**Founder setup:** create an APNs Auth Key, upload it as a Worker secret.

**Client:** `UNUserNotificationCenter.requestAuthorization`, register for
remote notifications, POST the device token to the auth Worker on launch and
on token change.

---

## Slice 3 — Real verification  ⏳

Today `verifyMe()` just flips a bool. The blue check needs to mean something.

**Approach:** integrate a KYC vendor (Persona or Onfido — both have SwiftUI
SDKs and a Workers-friendly webhook flow) for **liveness + ID match**. The
verification state lives on the server (`users.verified_at`), *not* the
client — so the flag is trustworthy in Auction Credit and everywhere else it
appears.

**Cost:** ~$1.50–$3 per verification depending on vendor + volume. That's
real money at scale; consider gating verification behind Pass or making it
free-forever after the first successful pass.

---

## Slice 4 — Matching backend  ⏳ (the big one)

Everything the app does with `matches`, `outgoingBids`, `incomingBids`,
`messages` becomes a server round-trip. This is where the app finally
becomes multiplayer.

**Approach:**
- Durable Objects for per-user inbox + per-match chat room (real-time
  fan-out to two devices via WebSocket).
- D1 for the durable record of bids/matches/reviews (source of truth).
- Rate-limiting: bids per hour, messages per minute (spam control).
- The existing on-device `AuctionStore` becomes a **cache + optimistic UI
  layer** over the server — its logic doesn't change, just its source.

**Scope estimate:** 3–4 focused sessions plus a real test with two phones.

---

## Slice 5 — Server-enforced moderation  ⏳

Today `ReportSheet` exists as UI but has no submit path. Blocks are
client-filtered `blockedIDs`, so a blocked user can still see and message
you if their client is honest.

**Approach:**
- `POST /moderation/report` — writes to a `reports` D1 table with
  reason, reporter, target, evidence pointer.
- The existing `AdminModerationView` gets fed by a `GET /admin/moderation`
  the founder can hit through the admin console.
- Blocks are enforced at the matching-backend Worker layer (slice 4) —
  a blocked bidder's bids are never delivered to the blocker's inbox.

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

- **2026-07-28** — Roadmap written. Slice 1 in progress.
