# Auction Baby — Consumables Worker (Stripe Checkout)

Sells **Gavel packs** through hosted Stripe Checkout for Auction Baby's
**web shop**. Ported from the AI Marketplace consumables model:
catalog → hosted Checkout → signed webhook → idempotent crediting →
consume/ledger — plus one hardening addition: `charge.refunded` debits the
balance, so a Stripe refund claws Gavels back the same way an Apple refund
does on the IAP side.

**Why this exists next to StoreKit:** digital Gavels *inside the iOS app*
must be sold through Apple IAP. This Worker is the web/real-world surface —
a browser-based shop where Stripe's fee (~3%) replaces Apple's 15–30%. The
pack ladder mirrors `Products.storekit` exactly so web and iOS parity holds:

| Pack | Gavels | Price |
|---|---|---|
| Handful | 1,000 | $4.99 |
| Stack | 5,000 | $19.99 |
| Chest | 14,000 | $49.99 |
| Vault | 30,000 | $99.99 |

Users are keyed by the app's **`appAccountToken`** (per-install UUID, no
PII) — the same identifier the payout Worker uses for Apple refund routing,
so one identity spans both money surfaces. The iOS app drains the web
balance into the local wallet via `/consume` on foreground (idempotent, so
a retried drain can't double-credit).

## Money-safety invariants

1. **The webhook is the only place Gavels are minted** — and only after the
   Stripe signature verifies (HMAC-SHA256, 5-minute replay window).
2. **Crediting is idempotent by event id** — Stripe's at-least-once webhook
   delivery can't double-credit (30-day processed-event memory).
3. **Only `payment_status == "paid"` sessions credit** — async payment
   methods that complete later credit on the later event.
4. **`charge.refunded` debits, floored at zero** — routed via a
   `payment_intent → {user, gavels}` KV table written at credit time
   (180-day TTL, comfortably past Stripe's refund window).
5. **`/consume` is idempotent per key** — a retried drain returns the prior
   result instead of spending twice.
6. **No card data anywhere** — Checkout is Stripe-hosted; this Worker only
   ever sees session ids and webhook events.

## Endpoints

| Route | Auth | What |
|---|---|---|
| `GET /health` | — | liveness + config sanity |
| `GET /catalog` | — | the Gavel packs for sale |
| `POST /checkout` | Bearer | create a Checkout Session; returns `{sessionId, url}` |
| `POST /webhook` | Stripe sig | credits on `checkout.session.completed`, debits on `charge.refunded` |
| `GET /balance?userId=` | Bearer | current web-Gavel balance |
| `POST /consume` | Bearer | spend/drain Gavels (idempotent) |
| `GET /ledger?userId=` | Bearer | recent purchases/spends/refunds |

## Deploy — one command

The whole provisioning flow (KV namespaces, shared secret, Stripe key,
deploy, **automatic Stripe webhook registration via the API**, smoke tests)
is scripted for both Workers:

```bash
cd AuctionBaby
npx wrangler login                                  # once
STRIPE_SECRET_KEY=sk_test_… ./setup-workers.sh      # staging first
STRIPE_SECRET_KEY=sk_live_… ENV=production ./setup-workers.sh
```

The script prints the exact `Secrets.xcconfig` lines when it finishes.
Webhook events registered: `checkout.session.completed`,
`checkout.session.async_payment_succeeded`, `charge.refunded`.

<details>
<summary>Manual steps, if you'd rather run them yourself</summary>

```bash
cd AuctionBaby/consumables
npm install
npx wrangler kv namespace create KV            # paste id into wrangler.toml
npx wrangler kv namespace create KV --env staging
npx wrangler secret put STRIPE_SECRET_KEY      # sk_test_… first, sk_live_… later
npx wrangler secret put APP_SHARED_SECRET      # reuse the payout Worker's value
npx wrangler deploy
# Stripe dashboard → webhook endpoint at <url>/webhook with the three events
npx wrangler secret put STRIPE_WEBHOOK_SECRET  # whsec_… from that endpoint
BASE_URL=<url> APP_SHARED_SECRET=<secret> ./smoke-test.sh
```
</details>

## Testing

Two layers, both runnable against local `wrangler dev` or a deployed URL:

```bash
npx wrangler dev --local        # boots with simulated KV; .dev.vars carries
                                # test secrets (git-ignored)

# Route/auth sanity:
BASE_URL=http://127.0.0.1:8787 APP_SHARED_SECRET=devsecret ./smoke-test.sh

# Full money path with genuinely HMAC-signed webhook events — credit,
# replay-idempotency, signature rejection, unpaid skip, async-payment
# credit, consume + replay, proportional partial refunds, floor at zero:
BASE_URL=http://127.0.0.1:8787 APP_SHARED_SECRET=devsecret \
  STRIPE_WEBHOOK_SECRET=whsec_localtest ./e2e-test.sh
```

`e2e-test.sh` passes 17/17 against the shipped Worker. For dashboard-driven
testing use the Stripe CLI instead: `stripe listen --forward-to
http://127.0.0.1:8787/webhook` + `stripe trigger checkout.session.completed`.

## Relationship to the payout Worker

`backend/` (auctionbaby-payout) handles **money out** — Stripe Connect
Express payouts to women, Apple ASSN V2 refund routing, the founder admin
console. This Worker handles **money in** on the web surface. They share
the `APP_SHARED_SECRET` by convention (one secret in the app) but have
independent KV namespaces and deployments, so a bug in one can't corrupt
the other's ledger.
