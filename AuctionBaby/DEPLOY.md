# Deployment guide — zero to production

Everything the founder needs to bring Auction Baby up from an empty Cloudflare account. Ordered runbook — copy the commands, in this sequence.

If you already have some pieces deployed, skip forward — every step is idempotent (safe to re-run) unless flagged otherwise.

---

## 0 — Accounts you need

- **Cloudflare** — free tier is enough to start. `wrangler login` from your terminal binds it.
- **Apple Developer** — you need the app's real bundle id, an APNs Auth Key (.p8), and Sign in with Apple enabled on the App ID.
- **Stripe** — test-mode keys are fine for TestFlight. Add the webhook endpoint later (step 4).
- **Xcode 15+** — for the iOS build.

---

## 1 — Provision the shared D1 database

Every Worker joins one D1. Create it once, reuse the same `database_id`.

```bash
wrangler d1 create auctionbaby-users
# → prints:  database_id = "xxxx-xxxx-xxxx-xxxx"
```

**Copy that id.** You'll paste it into three `wrangler.toml` files in the next steps.

Now apply the schema — fresh install, one shot:

```bash
cd AuctionBaby/auth
wrangler d1 execute auctionbaby-users --file=schema.sql
```

`schema.sql` uses `CREATE TABLE IF NOT EXISTS` everywhere, so re-running is a no-op. If you have an OLDER deployed DB, run only the migrations you don't have yet, in order:

```bash
wrangler d1 execute auctionbaby-users --file=migrations/00N_....sql
```

Migrations 001–009 ship in `AuctionBaby/auth/migrations/`. They're forward-only, one column at a time, and each fails loudly if the column already exists — safe to try them.

---

## 2 — Deploy the auth Worker

Owns Sign in with Apple, sessions, push send, verification, profiles, blocks, reports, admin actions.

**2.1 Paste the D1 id.** Open `AuctionBaby/auth/wrangler.toml` and replace `REPLACE_WITH_D1_DATABASE_ID` with the id from step 1.

**2.2 Confirm the bundle id.** `wrangler.toml` line 29:
```
APPLE_CLIENT_ID = "com.valasek.auctionbaby"
```
Change this if your bundle id differs.

**2.3 Set the secrets:**

```bash
cd AuctionBaby/auth

# Session-signing HMAC key. Rotating this invalidates every session.
openssl rand -hex 32 | wrangler secret put SESSION_SECRET

# Operator-carried admin bearer. Also used by consumables + matching
# Workers for Worker-to-Worker calls (push, reservation mirror).
openssl rand -hex 32 | wrangler secret put APP_SHARED_SECRET

# APNs auth key: Apple Developer → Keys → + → Apple Push Notifications.
# Download the .p8 (you can only download once — save it somewhere safe).
wrangler secret put APNS_AUTH_KEY_P8 < ~/Downloads/AuthKey_XXXXXXXXXX.p8

# The 10-char key id printed next to the .p8 on Apple.
wrangler secret put APNS_KEY_ID
# → paste when prompted

# Your Apple Developer team id (10 chars, top-right of the Apple Developer portal).
wrangler secret put APNS_TEAM_ID
```

**2.4 Deploy:**

```bash
wrangler deploy
# → Deployed auctionbaby-auth
# → https://auctionbaby-auth.<your-subdomain>.workers.dev
```

**Copy that URL.** You'll paste it into the matching Worker's env, the consumables Worker's env, AND the client build config.

**2.5 Smoke test:**

```bash
curl https://auctionbaby-auth.<your-subdomain>.workers.dev/health
# → {"ok":true,"service":"auctionbaby-auth",...}
```

The response's `pushConfigured` and `sessionSecretConfigured` should both be `true`.

---

## 3 — Deploy the matching Worker

Owns bids, matches, messages, blocks, rate limits, cold-match sweep.

**3.1 Paste the SAME D1 id** into `AuctionBaby/matching/wrangler.toml` (`REPLACE_WITH_SAME_D1_DATABASE_ID_AS_AUTH_WORKER`).

**3.2 Set `AUTH_URL`** in `matching/wrangler.toml` to the URL from step 2.4.

**3.3 Set the shared secrets:**

```bash
cd AuctionBaby/matching

# Must MATCH the auth Worker's SESSION_SECRET — this Worker verifies
# session tokens issued by auth without a round-trip.
wrangler secret put SESSION_SECRET
# → paste the SAME hex string from step 2.3

# The auth Worker's APP_SHARED_SECRET. Used to POST /push/send when
# a bid/accept/message needs to notify the other phone.
wrangler secret put AUTH_ADMIN_SECRET
# → paste the SAME hex string as APP_SHARED_SECRET from step 2.3

# Used by /internal/reservations/mark, called by the consumables
# Worker webhook. Same value again by convention.
wrangler secret put APP_SHARED_SECRET
# → paste the SAME hex string
```

**3.4 Deploy:**

```bash
wrangler deploy
# → Deployed auctionbaby-matching
# → https://auctionbaby-matching.<your-subdomain>.workers.dev
# → Cron trigger registered: "17 */6 * * *"  (Batch K cleanup)
```

`wrangler deploy` picks up the `[triggers] crons` block in `wrangler.toml` automatically. You'll see it in the Cloudflare dashboard under Workers → auctionbaby-matching → Triggers.

**Copy the matching URL.** Two consumers need it: consumables Worker env (step 4) + client build config (step 5).

---

## 4 — Deploy the consumables Worker (Stripe web shop)

Owns Gavel packs sold via Stripe Checkout + the Reserve-the-date booking fee. Optional if you don't need web-side purchases.

**4.1 Get Stripe keys:** Stripe dashboard → Developers → API keys. Grab `sk_test_…` (or `sk_live_…` for production).

**4.2 Set the secrets + env:**

```bash
cd AuctionBaby/consumables

wrangler secret put STRIPE_SECRET_KEY
# → paste sk_test_… or sk_live_…

# APP_SHARED_SECRET — same value as auth + matching Workers.
wrangler secret put APP_SHARED_SECRET
# → paste the SAME hex string from step 2.3
```

**4.3 Set MATCHING_URL** in `consumables/wrangler.toml` (or via `[vars]` — check the file's shape). This is what Batch I uses to mirror paid reservations onto matching Worker's `matches.reserved_at`.

**4.4 Create the KV namespace** for booking state and refund dedup:

```bash
wrangler kv:namespace create AUCTIONBABY_CONSUMABLES
# → paste the returned id into consumables/wrangler.toml under kv_namespaces
```

**4.5 First deploy** (needed to get the URL before you can point Stripe at it):

```bash
wrangler deploy
# → Deployed auctionbaby-consumables
# → https://auctionbaby-consumables.<your-subdomain>.workers.dev
```

**4.6 Register the Stripe webhook** at `POST https://auctionbaby-consumables.<your-subdomain>.workers.dev/webhook`, subscribed to `checkout.session.completed` + `charge.refunded`. Stripe gives you a `whsec_…` signing secret — set it and redeploy:

```bash
wrangler secret put STRIPE_WEBHOOK_SECRET
# → paste whsec_…

wrangler deploy
```

---

## 5 — Wire the client

The iOS app reads all URLs + the shared secret from `Info.plist` at launch. The plist references `$(AB_…)` build settings that come from `AuctionBaby/AuctionBaby/Config/Secrets.xcconfig` (untracked).

```bash
cp AuctionBaby/AuctionBaby/Config/Secrets.xcconfig.example \
   AuctionBaby/AuctionBaby/Config/Secrets.xcconfig
```

Open `Secrets.xcconfig` and paste four values:

```
AB_AUTH_URL         = https://auctionbaby-auth.<your-subdomain>.workers.dev
AB_MATCHING_URL     = https://auctionbaby-matching.<your-subdomain>.workers.dev
AB_WORKER_URL       = https://auctionbaby-payout.<your-subdomain>.workers.dev
AB_CONSUMABLES_URL  = https://auctionbaby-consumables.<your-subdomain>.workers.dev
AB_SHARED_SECRET    = <the same hex string you set for APP_SHARED_SECRET>
AB_TERMS_URL        = https://your-marketing-site.com/terms
AB_PRIVACY_URL      = https://your-marketing-site.com/privacy
```

`AB_WORKER_URL` is the legacy payout Worker (float management, ledger). Leave blank if you're not running it — the app degrades gracefully. `AB_SHARED_SECRET` is used ONLY for Worker-to-Worker admin bearer paths (`/push/send`, `/internal/reservations/mark`). User-facing admin endpoints (Batch L) now use the founder's session token, not this secret.

`AB_TERMS_URL` and `AB_PRIVACY_URL` are required for App Store submission (Guideline 5.1.1 — any account-creation flow must link to both). Host them as static HTML anywhere (your marketing site, a Cloudflare Pages project, even a public GitHub Pages repo); the Settings rows are hidden when either is blank.

Rebuild the app in Xcode. `BackendConfig.isBundled` returns true when both `AB_WORKER_URL` and `AB_SHARED_SECRET` are set.

---

## 6 — Grant yourself admin

The moderation console needs `users.is_admin = 1` on your row (Batch L). Sign in with Apple once from the app to create the user, then:

```bash
# Find your user id (recent signups first).
wrangler d1 execute auctionbaby-users --command \
  "SELECT id, email, name FROM users ORDER BY created_at DESC LIMIT 5;"

# Flip is_admin on YOUR row.
wrangler d1 execute auctionbaby-users --command \
  "UPDATE users SET is_admin = 1 WHERE id = '<your-id>';"
```

Verify by opening the app → Settings → Admin console. The user list should load without a 403.

---

## 7 — TestFlight smoke test with two devices

The whole spine only proves out with two real users. Minimum flow:

- [ ] **Phone A** — install, Sign in with Apple, DOB, create a man profile.
- [ ] **Phone B** — install, Sign in with Apple (different Apple ID), DOB, create a woman profile with an Opening Bid Script.
- [ ] **A** — see B on the floor. Place a $200 real bid. Confirm Gavel debit.
- [ ] **B** — receive `bid.received` push. Inbox refreshes (Batch 7 auto-refresh). Bid row shows.
- [ ] **B** — accept. Celebration fires. Match appears with her Opening Bid Script as the opener.
- [ ] **A** — receive `bid.accepted` push. Match list refreshes. Open the chat — her opener is visible (Batch F — the opener now round-trips via Batch A's synchronous send).
- [ ] **A** — send a message. B receives `message.received` push, chat auto-refreshes.
- [ ] Either side — react to a message. Reaction appears on both sides (Batch J).
- [ ] **A** — mark date done. Both sides can leave a review. Earnings ledger updates on B when A reports "paid".
- [ ] **B** — Report & Block A. Chat freezes on B; A can no longer send (Batch F composer freeze, Batch C server 403).
- [ ] **B** — Settings → Blocked users. A is listed. Unblock. Confirm they reappear on the floor.
- [ ] **Founder device** — Settings → Admin console → Moderation queue. B's report on A is visible with counts (Batch H). Tap "Unverify" or "Delete" from the queue — target-user server row is affected.

If every checkbox lands, the spine is live.

---

## 8 — Things this guide deliberately doesn't do

- **Custom domains** for the Workers. `.workers.dev` is fine for TestFlight; add domains via Cloudflare Zero Trust when you point real DNS at prod.
- **Photo hosting.** No R2 setup — the app currently ships without server-side photos (roadmap item; local `photoData` is per-device).
- **Real KYC verification.** Slice 3 landed with `VERIFICATION_VENDOR="manual"` as default. Persona / Onfido integration is separate work.
- **App Store submission.** See `APP_STORE_SUBMISSION.md` for that walkthrough — this guide gets you to TestFlight, not to the store.

---

## Troubleshooting

**Auth Worker's `/health` shows `pushConfigured: false`** — one of `APNS_AUTH_KEY_P8` / `APNS_KEY_ID` / `APNS_TEAM_ID` isn't set. Re-run the `wrangler secret put …` from step 2.3.

**Matching Worker returns 401 on `/bids/incoming`** — the SESSION_SECRET on matching Worker doesn't match auth Worker. Both must be the same hex string.

**Consumables webhook shows 400s in Stripe logs** — `STRIPE_WEBHOOK_SECRET` doesn't match the `whsec_…` Stripe generated when you registered the endpoint. Re-run step 4.6.

**Admin console shows 403 on the moderation queue** — you didn't grant admin (step 6), or you signed in with a different Apple ID than the one you ran the UPDATE for. Check `SELECT id, is_admin FROM users;`.

**Push arrives but the underlying screen doesn't refresh** — you're on an older client build. Batch 7 (auto-refresh) shipped as part of the current spine; make sure the app was built AFTER that commit.
