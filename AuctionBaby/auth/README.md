# Auction Baby — Auth Worker

Slice 1 of the [spine](../SPINE_ROADMAP.md). Sign in with Apple → server user
identity in Cloudflare D1. Stateless HMAC-signed session tokens.

## What it does

- `POST /auth/apple` — verifies an Apple identity JWT against Apple's JWKS,
  upserts a row in D1, returns a session token.
- `GET /me` — returns the authed user (Bearer token).
- `POST /auth/logout` — client-side hint (see note below).
- `DELETE /me` — hard-deletes the account (GDPR/CCPA subject-delete).
- `GET /health` — liveness.

## Setup (once, per environment)

```bash
cd AuctionBaby/auth
npm install

# 1. Create the D1 database and paste its id into wrangler.toml.
npx wrangler d1 create auctionbaby-users
# → copy the printed `database_id` into wrangler.toml under [[d1_databases]]

# 2. Apply the schema.
npx wrangler d1 execute auctionbaby-users --file=schema.sql

# 3. Set the session-signing secret (any long random string).
npx wrangler secret put SESSION_SECRET

# 4. Deploy.
npx wrangler deploy                     # production
# OR
npx wrangler deploy --env staging       # staging (repeat step 1-3 with --env staging)

# 5. Paste the deployed URL into Config/Secrets.xcconfig as AB_AUTH_URL, rebuild the app.
```

## Sessions: a note on statelessness

Session tokens are HMAC-SHA256-signed opaque strings:
`userId.expiryMs.signature`. They validate with **no DB round-trip** (fast +
cheap) but the tradeoff is that individual sessions can't be server-revoked
— rotating `SESSION_SECRET` invalidates ALL sessions at once.

For slice 1 this is fine (there's nothing yet worth stealing). If later
slices need per-user forced logout (e.g. after a password/2FA reset), add a
`revoked_sessions` D1 table and a check in `verifySessionToken`.

## Security posture

- **JWT signature** is verified against Apple's live JWKS (cached 24h,
  auto-refreshed on unknown `kid`) using WebCrypto RSASSA-PKCS1-v1_5.
- **All standard claims** are checked: `iss=https://appleid.apple.com`,
  `aud=<your bundle id>`, `exp > now`, `iat < now+60s`, non-empty `sub`.
  A valid signature on the wrong `aud` is the classic attack — the check
  is not optional.
- **Never expose `apple_sub`** in API responses (Apple asks us not to).
  See `publicUser()`.
- **DB fields are minimal**: id, apple_sub, email, name, dob, timestamps.
  Anything richer belongs to later slices' own tables.

## Local testing

You cannot fully test SIWA locally (needs Apple's servers and a real
bundle id), but `/health` and session-token round-trips are easy:

```bash
npx wrangler dev --local
curl http://127.0.0.1:8787/health
```

A full E2E test needs TestFlight on a physical device signed in to an
Apple ID.
