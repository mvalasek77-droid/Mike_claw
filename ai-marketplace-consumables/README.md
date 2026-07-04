# AI Marketplace — Consumable Purchases (Stripe)

A small, self-contained service that sells **consumable credit packs** through
Stripe Checkout and tracks a per-user credit balance. Credits are the
consumable good — the app spends them on generations/unlocks and they do not
renew. This is the purchase side of the marketplace clone; it is deliberately
separate from the existing `AIMarketplace/backend` Connect **payout** worker so
the two concerns (money in vs. money out) can be reasoned about and deployed
independently.

## Why Stripe here (and the App Store rule)

Stripe may be used for **real-world goods and services**. If these credits are
consumed for *digital* content inside an iOS app, Apple's guidelines require
**StoreKit in-app purchase**, not Stripe. So use this service for:

- a **web / Android** storefront, or
- **real-world** fulfilment (physical goods, real services), or
- server-side crediting where the iOS app uses StoreKit and this Worker mirrors
  the balance for non-Apple surfaces.

Don't wire `/checkout` straight into an iOS build selling digital credits — that
risks App Store rejection. The AuctionBaby app keeps digital status/currency on
StoreKit for exactly this reason.

## Architecture

```
app / web ──POST /checkout──▶ Worker ──create Checkout Session──▶ Stripe
       ◀───── { url } ───────                                     (hosted page)
                                                                       │
                                              user pays on Stripe ◀────┘
                                                                       │
Stripe ──POST /webhook (signed)──▶ Worker ──credit balance in KV──────┘
```

The card never touches the app or the Worker — Stripe's hosted Checkout collects
it. Balances are **only** minted in `/webhook`, after signature verification,
and **once per event** (idempotent by Stripe event id).

## Endpoints

| Method | Path                 | Auth            | Purpose                                   |
|--------|----------------------|-----------------|-------------------------------------------|
| GET    | `/health`            | none            | Liveness + config sanity                  |
| GET    | `/catalog`           | none            | The consumable packs for sale             |
| POST   | `/checkout`          | shared secret   | Create a Checkout Session → `{ url }`     |
| POST   | `/webhook`           | Stripe signature| Credit the balance on paid checkout       |
| GET    | `/balance?userId=`   | shared secret   | Current credit balance                    |
| POST   | `/consume`           | shared secret   | Spend credits (idempotent)                |
| GET    | `/ledger?userId=`    | shared secret   | Recent purchases/spends                   |

### `POST /checkout`
```json
{ "packId": "credits_550", "userId": "abc123",
  "successUrl": "https://…/success", "cancelUrl": "https://…/cancel" }
→ { "sessionId": "cs_…", "url": "https://checkout.stripe.com/…" }
```

### `POST /consume`
```json
{ "userId": "abc123", "credits": 10, "reason": "image_gen",
  "idempotencyKey": "gen-7f3a" }
→ { "ok": true, "spent": 10, "credits": 540 }   // 402 if insufficient
```

## Catalog

Edit `CATALOG` in `src/index.ts` and redeploy — prices are in cents, credits are
whatever number you choose. There is no Stripe dashboard product to keep in sync;
`price_data` is built inline per Checkout Session.

## Setup

```bash
cd backend
npm install

# create a KV namespace and paste its id into wrangler.toml (both blocks)
npx wrangler kv namespace create KV

# secrets (test mode first)
npx wrangler secret put STRIPE_SECRET_KEY       # sk_test_…
npx wrangler secret put STRIPE_WEBHOOK_SECRET   # whsec_… (from the step below)
npx wrangler secret put APP_SHARED_SECRET       # long random string; also in the app

npm run typecheck
npm run dev            # local at http://127.0.0.1:8787
```

Point a Stripe webhook (Dashboard → Developers → Webhooks, or the CLI) at
`/webhook` for the `checkout.session.completed` event, and copy its signing
secret into `STRIPE_WEBHOOK_SECRET`:

```bash
stripe listen --forward-to http://127.0.0.1:8787/webhook
stripe trigger checkout.session.completed
```

## Test

```bash
BASE_URL=http://127.0.0.1:8787 APP_SHARED_SECRET=devsecret ./backend/smoke-test.sh
```

## Deploy

```bash
npx wrangler deploy                 # production
npx wrangler deploy --env staging   # Stripe test mode
```

## Status

**Scaffold — the purchase flow is complete and testable end-to-end** (catalog →
Checkout → signed webhook → balance → consume, all idempotent). Not yet built:
receipts/refund handling (`charge.refunded` → claw back credits), a real
storefront UI, and per-user auth beyond the shared secret (JWT/App Store
server-notifications bridge). See the checklist below.

- [x] Catalog + Checkout Session creation
- [x] Signed webhook → idempotent crediting
- [x] Balance + idempotent consume + ledger
- [ ] `charge.refunded` → debit credits
- [ ] Storefront UI (web) / StoreKit bridge (iOS)
- [ ] Per-user identity (replace shared-secret-only auth)
