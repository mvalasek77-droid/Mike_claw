# Auction Baby — Matching Worker

Slice 4 of the [spine](../SPINE_ROADMAP.md). The data plane for real bids,
matches, and messages between two actual signed-in users. Shares its D1
database (`auctionbaby-users`) with the auth Worker so `bidder_id` / `lot_id`
are foreign keys into `users`.

## What ships in slice 4a

- **Schema:** `bids`, `matches`, `messages` tables (in the same D1 as `users`).
- **Endpoints:** everything you need to run the full bid → accept → chat →
  mark-done loop between two real users (see the header of `src/index.ts`).
- **Push:** every state change that would matter to the other party (bid
  arrives, bid accepted, whisper nodded, message received, date-done)
  triggers a push via the auth Worker's `/push/send` — the notification pipe
  lives in one place.
- **Session auth:** verifies the same HMAC-signed tokens the auth Worker
  issues, using a shared `SESSION_SECRET`. No cross-Worker HTTP round-trip
  per request.

## What is deliberately NOT in slice 4a

- **UI migration.** The iOS app still uses its on-device simulation by
  default. Wiring the SwiftUI screens to consume these endpoints is slice 4b
  and beyond.
- **Durable Objects / WebSocket real-time.** For MVP, the other side wakes
  via push + refresh-on-foreground. Real-time chat is a future upgrade.
- **Rate limiting.** No `bids/hour` cap yet. Add before public launch.
- **Server-side block enforcement.** That's slice 5.

## Setup (once, per environment)

```bash
cd AuctionBaby/matching
npm install

# 1. Same D1 as auth — paste the auctionbaby-users database_id from
#    ../auth/wrangler.toml into wrangler.toml here.

# 2. If you're on a fresh D1: schema.sql over in auth/ already has the
#    matching tables. If auth is already deployed, apply the delta:
npx wrangler d1 execute auctionbaby-users --file=../auth/migrations/003_add_matching.sql

# 3. Shared secrets. SESSION_SECRET must be the SAME string you set on
#    the auth Worker (that's how this Worker verifies session tokens).
npx wrangler secret put SESSION_SECRET
# AUTH_ADMIN_SECRET is auth's APP_SHARED_SECRET (gates /push/send calls).
npx wrangler secret put AUTH_ADMIN_SECRET

# 4. Point AUTH_URL in wrangler.toml at the deployed auth Worker.

# 5. Deploy.
npx wrangler deploy               # production
npx wrangler deploy --env staging # staging
```

Then paste the deployed URL into `Config/Secrets.xcconfig` as
`AB_MATCHING_URL` and rebuild the app.

## Prove it works (end-to-end, via curl)

You need two signed-in users' `userId`s and session tokens. Sign in from two
devices (or one device + a sandbox tester), then grab the tokens by pulling
the Keychain via a debugger — or, easier, add a temporary log in
`AuthService.signInWithApple` that prints the token during dev.

```bash
AUTH_TOKEN_A="…"      # bidder's session token
AUTH_TOKEN_B="…"      # lot's session token
LOT_ID="…"            # lot's userId
MATCH="https://auctionbaby-matching.you.workers.dev"

# Place a bid (bidder → lot)
curl -X POST "$MATCH/bids" \
  -H "Authorization: Bearer $AUTH_TOKEN_A" \
  -H "Content-Type: application/json" \
  -d '{"lotId":"'"$LOT_ID"'","amount":250,"note":"Dinner at Carbone?"}'
# → 201 { bid: {...} }   AND a push should land on the lot's phone.

# Lot lists inbox
curl "$MATCH/bids/incoming" -H "Authorization: Bearer $AUTH_TOKEN_B"

# Lot accepts (use the bidId from above)
BID_ID="…"
curl -X POST "$MATCH/bids/$BID_ID/accept" -H "Authorization: Bearer $AUTH_TOKEN_B"
# → 201 { match: {...} }   AND a push lands on the bidder's phone.

# Send a message
MATCH_ID="…"
curl -X POST "$MATCH/matches/$MATCH_ID/messages" \
  -H "Authorization: Bearer $AUTH_TOKEN_A" \
  -H "Content-Type: application/json" \
  -d '{"text":"Where should we go?"}'
# → 201 { message: {...} }   AND a push lands on the lot's phone.
```

## Security posture

- **Session tokens** verified locally via HMAC-SHA256 with the shared
  `SESSION_SECRET`. Rotating `SESSION_SECRET` on ONE Worker without the
  other invalidates every sign-in against THAT Worker.
- **Ownership checks** on every match-scoped write: the authed user MUST
  be one of `bidder_id` or `lot_id`. A leaked matchId can't be poked.
- **Bid ceiling** capped at 1B to stop obvious client tampering; the app's
  own `maxStartingBid` is much lower. This is defense-in-depth.
- **Self-bids** rejected — a user can't bid on themselves.
- **Match uniqueness** on `bid_id` (DB UNIQUE constraint) — a double-tap
  accept can't create two matches for the same bid.
- **Push failures never block state changes** — the DB write commits first;
  a push transport error is logged and swallowed.
