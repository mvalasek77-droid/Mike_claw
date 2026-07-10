# Auction Baby — Payout Worker (Cloudflare Workers + Stripe)

The server side of Auction Baby's money model, ported from the proven AI
Marketplace payout Worker. One Cloudflare Worker handles:

- **Stripe Connect Express payouts** — women onboard once, then their 85%
  share of every confirmed date auto-pays to their own bank.
- **Apple App Store Server Notifications V2** — when Apple refunds a Gavel
  pack, the refund is queued under the buyer's `appAccountToken` (the UUID
  the app attaches to every purchase) so the wallet claws back even when the
  device never sees the refund.
- **Money-flow ledger** — an append-only KV record of every transfer, payout,
  top-up, refund and dispute, independent of Stripe, for reconciliation.
- **Float automation** — cron keeps the platform Stripe balance topped up
  from your bank and emails you a payout digest every 6 hours.
- **Moderation queue** — in-app reports land here (Apple Guideline 1.2).

Money model (mirrors `Models/Commerce.swift` in the app): Apple takes its IAP
commission first; of the net, the woman keeps **85%** and the platform keeps
**15%**.

## Deploy — all the steps

Everything below happens in this directory (`AuctionBaby/backend`).

### 0. Prerequisites

- A [Cloudflare account](https://dash.cloudflare.com/sign-up) (free tier works)
- A [Stripe account](https://dashboard.stripe.com/register) with **Connect**
  enabled (Settings → Connect → Get started, choose Express)
- Node 18+

### 1. Install and log in

```bash
npm install
npx wrangler login          # opens a browser to authorize wrangler
```

### 2. Create the KV namespace

```bash
npx wrangler kv namespace create KV
# → paste the printed id into wrangler.toml under [[kv_namespaces]]
```

For staging (Stripe test mode) too:

```bash
npx wrangler kv namespace create KV --env staging
# → paste into [[env.staging.kv_namespaces]]
```

### 3. Set the secrets

```bash
# Stripe → Developers → API keys
npx wrangler secret put STRIPE_SECRET_KEY        # sk_live_… (sk_test_… for staging)

# Any long random string; ALSO paste it into the app's backend config
openssl rand -hex 32
npx wrangler secret put APP_SHARED_SECRET

# Set AFTER step 5 creates the webhook endpoint (needs the whsec_…)
npx wrangler secret put STRIPE_WEBHOOK_SECRET

# Optional — enables operator emails (sale/NSF/digest): resend.com API key
npx wrangler secret put RESEND_API_KEY
```

For staging, repeat each with `--env staging` and test-mode keys.

### 4. Deploy

```bash
npx wrangler deploy                  # production
npx wrangler deploy --env staging    # staging (Stripe test mode)
```

Note the Worker URL it prints, e.g.
`https://auctionbaby-payout.<your-subdomain>.workers.dev`.

### 5. Wire the Stripe webhook

Stripe Dashboard → Developers → Webhooks → **Add endpoint**:

- URL: `https://<worker-url>/payouts/webhook`
- Events: `account.updated`, `payout.paid`, `payout.failed`,
  `topup.succeeded`, `topup.failed`, `charge.refunded`,
  `charge.dispute.created`, `charge.dispute.funds_withdrawn`,
  `charge.dispute.closed`, `transfer.reversed`
- Copy the signing secret (`whsec_…`) →
  `npx wrangler secret put STRIPE_WEBHOOK_SECRET`

### 6. Wire Apple App Store Server Notifications

App Store Connect → your app → **App Information** → App Store Server
Notifications:

- Production URL: `https://<worker-url>/webhooks/app-store-server`
- Version: **V2**

Apple signs every notification; the Worker pins Apple's Root CA and verifies
the JWS before trusting anything. Refunds are queued by `appAccountToken` —
the same UUID `AuctionStore.appAccountToken` attaches to every purchase.

### 7. Smoke test (staging, fake money)

```bash
export STAGING_URL="https://auctionbaby-payout-staging.<you>.workers.dev"
export APP_SHARED_SECRET="<staging secret>"
bash smoke-test.sh                    # creates a test Connect account first run
# finish onboarding with Stripe's test data, then:
export TEST_ACCOUNT_ID="acct_…"
bash smoke-test.sh                    # runs the full transfer → ledger path
```

### 8. Point the app at the Worker

Add the Worker URL + `APP_SHARED_SECRET` to the app's backend configuration
(a `BackendConfig` service, mirroring the AI Marketplace pattern) and the app
can call `/payouts/*`, `/refunds/*` and `/moderation/report` with
`Authorization: Bearer <APP_SHARED_SECRET>`.

## Endpoints

| Route | Auth | Purpose |
|---|---|---|
| `POST /payouts/connect` | secret | Create Connect Express account + onboarding link |
| `POST /payouts/onboarding-link` | secret | Fresh link for an existing account (they expire in minutes) |
| `GET /payouts/status` | secret | Onboarding / payouts-enabled state |
| `GET /payouts/balance` | secret | Available + pending balance |
| `POST /payouts/cash-out` | secret | Explicit "pay me now" to her bank |
| `POST /payouts/transfer` | secret | Pay her 85% share after a confirmed date |
| `POST /payouts/webhook` | Stripe sig | Stripe events → ledger + alerts |
| `POST /webhooks/app-store-server` | Apple JWS | Refunds → per-user queue |
| `GET /refunds/pending` | secret | Client drains queued refunds |
| `POST /refunds/ack` | secret | Client acks drained refunds |
| `POST /commerce/validate-receipt` | secret | Server-side replay check for IAP |
| `POST /moderation/report` | secret | In-app report → KV queue + email |
| `GET /moderation/reports` | secret | Admin queue listing |
| `POST /moderation/reports/{id}/resolve` | secret | removed / warned / dismissed |
| `GET /ledger`, `/ledger/summary`, `/ledger/calculate-balance` | secret | Money record + reconciliation |
| `GET /payouts/funding`, `/payouts/unfunded`, `POST /payouts/manual-fund` | secret | Float awareness + owed-but-unpaid recovery |
| `POST /payouts/digest`, `POST /payouts/topup` | secret | Manual triggers for the cron jobs |
| `POST /accounts/delete`, `/accounts/release-email` | secret | Account lifecycle (Apple 5.1.1(v)) |
| `GET /payout-complete`, `/payout-refresh` | none | Branded bounce pages after Stripe onboarding |

## Safety rails carried over from the AI Marketplace Worker

- Idempotency keys on every money-moving Stripe call (safe retries, no
  double-pays).
- Ledger writes are entry-first (a transient failure can duplicate, never
  lose, a record) and deduped by Stripe object id.
- Money routes refuse to run without KV bound (no silent, unaudited moves).
- NSF / chargeback / reversal events email the operator immediately.
- Auto-top-up is capped per pull (`TOPUP_MAX_USD`) so a refund storm can't
  trigger a runaway bank draw.
- Constant-time shared-secret comparison; per-IP rate limits on the abuse-prone
  routes; Apple Root CA pinning on the ASSN webhook.
