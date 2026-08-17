# Auction Baby Web — Go-Live Sequence

Do these in order. Nothing here is code — it's deploy + configuration. When
`config.js` is blank the app runs the on-device demo; filling it + deploying the
Workers makes it live.

---

## 1. Deploy the Workers (backend)
All three already exist; you're deploying the web-related changes.

```sh
cd AuctionBaby
# auth: now accepts the web Sign-in-with-Apple audience
(cd auth && npx wrangler secret put WEB_CLIENT_ID   # = com.valasek.auctionbaby.web
            npx wrangler deploy)
# matching: unchanged, just ensure it's on prod
(cd matching && npx wrangler deploy)
# consumables: now has /subscribe + /subscription (Stripe Billing)
(cd consumables && npx wrangler deploy)
```

✅ Checks:
- `curl https://<auth>.workers.dev/health` → healthy.
- The **consumables** Worker must have a **KV namespace bound** (for Pass
  entitlement) and the Stripe secrets set (`STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`).

## 2. Apple — Sign in with Apple for the Web
1. Apple Developer → **Identifiers → Services IDs → +** → e.g.
   `com.valasek.auctionbaby.web`; enable **Sign in with Apple**.
2. Configure it: add your web **domain** and a **Return URL** of
   `https://<your-domain>/index.html`.
3. That Services ID is the value you put in `WEB_CLIENT_ID` (step 1) **and** in
   `config.js` (`APPLE_SERVICE_ID`).

## 3. Stripe — payments
1. In the **consumables** Worker: `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` set.
2. Stripe Dashboard → **Developers → Webhooks** → your endpoint =
   `https://<consumables>.workers.dev/webhook`. Enable events:
   - `checkout.session.completed`
   - `checkout.session.async_payment_succeeded`
   - `charge.refunded`
   - **`customer.subscription.deleted`**  ← new, so canceled Passes are revoked
3. Gavel packs = one-time (`/checkout`), Passes = recurring (`/subscribe`).

## 4. Fill `config.js`
```js
AUTH_URL, MATCHING_URL, CONSUMABLES_URL   // your prod *.workers.dev URLs
APPLE_SERVICE_ID   = "com.valasek.auctionbaby.web"
APPLE_REDIRECT_URI = "https://<your-domain>/index.html"
CHECKOUT_SUCCESS_URL = "https://<your-domain>/index.html#/store?paid=1"
CHECKOUT_CANCEL_URL  = "https://<your-domain>/index.html#/store"
```

## 5. Deploy the web app (Cloudflare Pages)
1. Cloudflare → **Workers & Pages → Create → Pages → Direct Upload** (or connect
   the repo, output dir `AuctionBaby/web`, no build command).
2. Upload `AuctionBaby/web/`. You get `https://<project>.pages.dev`.
3. Add your **custom domain** — it must match the Apple Return URL + Stripe URLs.

## 6. Smoke test (in this order)
1. Open the site → **Sign in with Apple** completes → you're on the Floor.
2. **Floor** loads real profiles (photos if `PHOTOS_PUBLIC_URL` is set).
3. **Bidder:** place a bid → "Bid placed"; the woman account sees it under **Bids**.
4. **Woman:** **Accept** → match appears → **chat** both ways.
5. **Store:** buy a **Gavel pack** → Stripe Checkout → return → balance up.
6. **Store:** subscribe to a **Pass** → Stripe → `GET /subscription?userId=` shows it.
7. Cancel the Pass in Stripe → `customer.subscription.deleted` → entitlement clears.

## Rollback / notes
- Blank `config.js` (or redeploy Pages with it blank) = instant fall back to the
  safe on-device demo. No backend calls.
- Field-shape mismatches (floor/matches/bids JSON keys) are the one thing to
  verify on first real data — adjust the mappers (`mapLot`, `syncMatches`,
  `syncIncoming`) in `app.js` if your Workers use different keys.
- Add PNG `apple-touch-icon` (180×180) for a crisp iOS home-screen icon.
