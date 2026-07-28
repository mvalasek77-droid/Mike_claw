# Auction Baby — Founder Launch Checklist

Everything the code needs from **you** to go live, in order. Each phase is
blocking for the ones after it. Items marked ⚙️ are one command; items
marked 🖱 are dashboard clicks; items marked 📄 are documents/decisions.

---

## Phase 0 — First compile (Mac + Xcode required) — ~1 hour

The entire codebase was written in a Linux environment with **no Swift
toolchain — it has never been compiled**. Expect a handful of trivial
compile fixes on first build.

- [ ] `git pull` branch `claude/auction-baby-dating-app-rezanv`
- [ ] `cd AuctionBaby && xcodegen generate` (or open the committed
      `AuctionBaby.xcodeproj` directly)
- [ ] Build + run on a **real iPhone** (StoreKit + PhotosPicker + Keychain
      behave differently in the simulator)
- [ ] Run both test suites: `AuctionBabyTests` (AuctionLogicTests +
      FlowTests) — ⌘U
- [ ] Walk the 12-minute reviewer path in `DEMO_MODE.md` yourself, both
      roles (name `demo` at onboarding)
- [ ] Optional: drop licensed photos into `Resources/Assets.xcassets` under
      the `photo-*` names from `SampleData.swift` (the gradient-monogram
      fallback works without them)

## Phase 1 — Cloudflare + Stripe backend — ~30 min

- [ ] Create a [Cloudflare account](https://dash.cloudflare.com) (free tier
      is fine) and a [Stripe account](https://dashboard.stripe.com)
      (activate **Connect → Express** for the woman-payout side; business
      category: Dating Services / MCC 7273)
- [ ] ⚙️ `npx wrangler login` (once, in a terminal)
- [ ] ⚙️ Staging first:
      ```bash
      cd AuctionBaby
      STRIPE_SECRET_KEY=sk_test_… ./setup-workers.sh
      ```
      This provisions **both** Workers: KV namespaces, one shared app
      secret, Stripe key, deploy, and it registers the consumables Stripe
      webhook automatically via the API. It ends by smoke-testing both
      deployed URLs and printing three config lines.
- [ ] Copy `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig`
      and paste the three printed lines (`AB_WORKER_URL`,
      `AB_SHARED_SECRET`, `AB_CONSUMABLES_URL`). This file is git-ignored.
      Rebuild the app.
- [ ] 🖱 Payout Worker's own Stripe webhook (Connect events — transfers,
      payouts, account updates): Stripe dashboard → Developers → Webhooks →
      add endpoint at `<payout-url>/webhooks/stripe`, then
      ```bash
      cd backend && npx wrangler secret put STRIPE_WEBHOOK_SECRET --env staging
      ```
- [ ] Optional: operator emails (sale alerts, NSF alerts, payout digest) —
      create a [Resend](https://resend.com) key and
      `cd backend && npx wrangler secret put RESEND_API_KEY --env staging`
- [ ] Test a full web purchase on staging: `curl` the `/checkout` route or
      wire a test page, pay with Stripe test card `4242 4242 4242 4242`,
      then foreground the app — the Gavels should sync into the wallet
      with a "Web shop synced" toast
- [ ] 🖱 Test a refund from the Stripe dashboard on that payment — Gavels
      should claw back on next foreground
- [ ] ⚙️ When staging is proven:
      `STRIPE_SECRET_KEY=sk_live_… ENV=production ./setup-workers.sh`
      and update `Secrets.xcconfig` to the production URLs

## Phase 2 — Domain + email — ~1 hour + DNS wait

The code currently points at **placeholder** URLs that Apple will check.

- [ ] Buy/confirm `auctionbaby.app` (or pick another domain and I'll do a
      find-replace)
- [ ] Host real pages at `/terms` and `/privacy` — the paywall and store
      footers link to them and **App Review opens subscription links**
- [ ] Decide the web Gavel-shop page (calls the consumables Worker's
      `/checkout`; the money rails are live, the storefront page is the
      one unbuilt piece) — or park a "coming soon" page and ship iOS-only
- [ ] Update `SUCCESS_URL` / `CANCEL_URL` in `consumables/wrangler.toml`
      if the domain differs, and redeploy
- [ ] Set the **"Reserve the date"** booking-fee tiers: `RESERVE_TIERS_CENTS`
      in `consumables/wrangler.toml` (default `1000,1500,2500,5000,10000` =
      $10/$15/$25/$50/$100). This is a Stripe (non-IAP) real-world reservation
      fee kept by the platform — it rides the same consumables Worker + Stripe
      account as the web Gavel shop, so no extra setup beyond Phase 1. The
      Worker only charges an allow-listed amount, so a client can't post an
      arbitrary one. The in-app card stays dormant until `AB_CONSUMABLES_URL`
      is configured.
- [ ] **Kill-switch:** `RESERVE_ENABLED` in the same file — set to `"false"`
      and redeploy to turn reservations off fleet-wide with no app update (the
      app hides the card when the Worker reports it disabled). Useful if App
      Review pushes back on the feature post-launch.
- [ ] Confirm the in-app bug-report recipient: `BugReport.swift` currently
      sends to `mv19770601@gmail.com` — change if you want a dedicated
      support inbox
- [ ] Confirm `OPERATOR_EMAIL` in `backend/wrangler.toml`
      (`mvalasek77@gmail.com`) for payout digests/alerts

## Phase 2.5 — Spine Slice 1: Sign in with Apple + user identity — ~45 min

The first slice of the [spine](SPINE_ROADMAP.md). Adds real accounts (Sign in
with Apple → Cloudflare D1 user records). Fully optional to ship — leaving
`AB_AUTH_URL` blank keeps the app local-only, exactly as it works today.

- [ ] In your Apple Developer account: enable the **Sign in with Apple**
      capability for identifier `com.valasek.auctionbaby`.
- [ ] In Xcode → Signing & Capabilities → **+ Capability → Sign in with
      Apple**. Rebuild.
- [ ] ⚙️ Create the D1 database (once per environment):
      ```bash
      cd AuctionBaby/auth
      npx wrangler d1 create auctionbaby-users
      ```
      Paste the printed `database_id` into `AuctionBaby/auth/wrangler.toml`
      under `[[d1_databases]]`. Do the same for staging with `--env staging`.
- [ ] ⚙️ Apply the schema:
      ```bash
      npx wrangler d1 execute auctionbaby-users --file=schema.sql
      ```
- [ ] ⚙️ Set the session-signing secret (any long random string):
      ```bash
      npx wrangler secret put SESSION_SECRET
      ```
- [ ] ⚙️ Deploy: `npx wrangler deploy` (production) or `--env staging`.
- [ ] Paste the deployed URL into `Config/Secrets.xcconfig` as
      `AB_AUTH_URL`. Rebuild the app — the "Save your account" card now
      appears above the Photos step in onboarding.
- [ ] Test on a real device: fresh install → pick a role → Sign in with
      Apple → the card shows "Signed in with Apple" and the name is
      pre-filled if you granted it. Complete onboarding, kill the app,
      relaunch: the session should still be there (Keychain-persisted).
- [ ] Sign out test (once you build a settings surface for it) or wipe the
      Keychain via a fresh install to confirm the sign-in flow re-runs.

**Legal note:** the moment you enable this, you're storing an email (or
Apple's private-relay address) and an internal user id server-side. That
brings light-touch GDPR/CCPA/PIPEDA responsibilities (subject-delete is
already wired via `DELETE /me`; a UI to trigger it will land with a settings
screen). Update your Privacy Policy to disclose Apple-issued email/name +
last-seen timestamp as "data collected for authentication."

## Phase 3 — App Store Connect — ~2 hours

- [ ] Create the app record: bundle id `com.valasek.auctionbaby`, name
      **Auction Baby**
- [ ] Categories: **primary Social Networking, secondary Lifestyle**;
      age rating **17+**
- [ ] **Request high price points first** (this gates three products below
      and Apple reviews it, so start it early): App Store Connect →
      Business / Agreements → request access to price points **above
      $999.99**. Without it you can't create the Influencer, Ferrari, or
      Trillionaire products. $9,999.99 is Apple's absolute ceiling.
- [ ] Create the IAPs to match `Products.storekit` **exactly** (IDs must
      be character-identical):
      | Product ID | Type | Price |
      |---|---|---|
      | `com.valasek.auctionbaby.gavels.handful` | Consumable | $4.99 |
      | `com.valasek.auctionbaby.gavels.stack` | Consumable | $19.99 |
      | `com.valasek.auctionbaby.gavels.chest` | Consumable | $49.99 |
      | `com.valasek.auctionbaby.gavels.vault` | Consumable | $99.99 |
      | `com.valasek.auctionbaby.boost.spotlight` | Consumable | $3.99 |
      | `com.valasek.auctionbaby.status.goodguy` | **Non-consumable** | $4.99 |
      | `com.valasek.auctionbaby.status.inandout` | **Non-consumable** | $9.99 |
      | `com.valasek.auctionbaby.status.whynot` | **Non-consumable** | $19.99 |
      | `com.valasek.auctionbaby.status.goodjob` | **Non-consumable** | $99.99 |
      | `com.valasek.auctionbaby.status.inheritance` | **Non-consumable** | $999.99 |
      | `com.valasek.auctionbaby.status.influencer` | **Non-consumable** | $2,499.99 ⚠️ |
      | `com.valasek.auctionbaby.status.ferrari` | **Non-consumable** | $4,999.99 ⚠️ |
      | `com.valasek.auctionbaby.status.trillionaire` | **Non-consumable** | $9,999.99 ⚠️ |
      | `com.valasek.auctionbaby.sub.paddle` | Auto-renew (1 group) | $19.99/mo |
      | `com.valasek.auctionbaby.sub.reserve` | Auto-renew (same group) | $39.99/mo |
      | `com.valasek.auctionbaby.sub.blackcard` | Auto-renew (same group) | $99.99/mo |

      ⚠️ = needs the high-price-point request above. Write clear review
      notes for the status ratings: the rating a man wears **is** what he
      paid for it — that's the app's entire premise, not an arbitrary
      charge. Expect Apple to look hard at a $9,999.99 product; be ready
      to explain it. Note also that Gavels never buy status, so there's no
      "currency laundering" of a high price point through consumables.
- [ ] App Store Server Notifications **V2**: set both the production and
      sandbox URLs to `<payout-worker-url>/webhooks/app-store-server`
      (this is how Apple refunds reach the refund queue)
- [ ] Listing copy: paste from `APP_STORE.md` (title, subtitle, promo,
      description, keywords)
- [ ] Privacy nutrition labels: per the `APP_STORE.md` privacy section
      (no tracking; purchases + anonymous `appAccountToken` not linked
      to identity)
- [ ] App Review notes: paste the suggested text from `DEMO_MODE.md`
      (credential = name `demo` at onboarding, no password)

## Phase 4 — TestFlight → submission — ~1 week of soak

- [ ] Archive + upload; internal TestFlight to yourself + a few friends
- [ ] Sandbox-account IAP test: buy a Gavel pack, a Boost, and a Pass with
      a sandbox tester; verify wallet credit + entitlements
- [ ] Sandbox refund test: refund the pack in App Store Connect, confirm
      the clawback lands (foreground the app)
- [ ] Kill-mid-purchase test: start a purchase, force-quit before it
      finishes, relaunch — Gavels must still land (transaction replay)
- [ ] Reset-account test: Profile → Reset — confirm you land back at
      onboarding clean
- [ ] Submit for review with the demo notes

## Phase 5 — Legal/business (parallel to everything) 📄

- [ ] Business entity + the Stripe Connect platform profile completed
      (Canadian platform, CAD settlement — already configured in
      `wrangler.toml`)
- [ ] Real Terms of Service + Privacy Policy from a lawyer (the linked
      pages from Phase 2). Flag for counsel: the bid is a
      **letter of intent** — date money settles peer-to-peer in person and
      the app never custodies it (this is the no-escrow/no-money-
      transmitter design; confirm it holds in your jurisdictions)
- [ ] Confirm the AI-Copycat reveal mechanic with counsel against FTC
      fake-profile precedent — the app discloses at onboarding that
      Copycats exist and reveals immediately after a bid, and never takes
      money on a Copycat interaction (all by design, worth a legal read)
- [ ] Woman-payout KYC is handled by Stripe Express onboarding (built in)

## Product decisions parked for you (non-blocking)

- [ ] Streak-freeze stockpiling has no cap (whales can buy unlimited at
      500 Gavels) — cap it or keep as monetization escape valve?
- [ ] The woman side has no Lot-of-the-Day equivalent — fine for launch?
- [ ] Admin password: `Crown-Ivory-23!Gavel77` (username `valasek`) —
      memorize, then delete this line from the file
- [ ] v1.1 backlog priorities: voice/video prompts, liveness verification,
      NSFW photo screening, background checks (see `ROADMAP.md`)
