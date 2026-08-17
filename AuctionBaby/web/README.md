# Auction Baby — Web App (PWA)

A no-build, installable Progressive Web App version of Auction Baby, created
after the App Store 4.3(b)/1.2 rejection (Apple itself suggested the web-app
route). It runs standalone on demo data today and is wired to later point at the
existing Cloudflare Workers backend.

## What's here
```
web/
  index.html            SPA shell (installable, offline)
  app.js                state, routing, screens, demo data (localStorage)
  styles.css            auction-house theme (dark / gold / serif)
  manifest.webmanifest  PWA manifest
  sw.js                 service worker (offline shell)
  icons/icon.svg        app mark
```

## Run it locally
Any static server (a PWA needs http/https, not file://):
```sh
cd AuctionBaby/web
python3 -m http.server 8080
# open http://localhost:8080
```
On iPhone Safari: open the URL → **Share → Add to Home Screen** → it launches
full-screen like an app, no App Store, no review.

## Deploy (recommended: Cloudflare Pages — you already use Cloudflare)
1. Cloudflare dashboard → **Workers & Pages → Create → Pages → Direct Upload**
   (or connect the repo and set the build output directory to `AuctionBaby/web`).
2. Upload the `web/` folder. No build command — it's static.
3. You get `https://<project>.pages.dev`; add a custom domain if you want.
   *(GitHub Pages / Netlify / Vercel work too — it's just static files.)*

## It's already wired to the backend — just add config
`api.js` is a full client for your Workers (auth, floor, bids, matches,
messages, Stripe checkout). `app.js` uses it when configured and **falls back
to demo** when not — so blank config = the on-device demo you see now; filled
config = live. **Go live by editing `config.js` + deploying two things.**

### Go-live checklist
1. **Point at your Workers** — in `web/config.js` set:
   ```js
   AUTH_URL, MATCHING_URL, CONSUMABLES_URL   // your deployed *.workers.dev URLs
   ```
2. **Sign in with Apple for the Web** (so real accounts work):
   - Apple Developer → **Identifiers → Services IDs → +** → create e.g.
     `com.valasek.auctionbaby.web`; enable **Sign in with Apple**; add your web
     **domain** + a **Return URL** of `https://<your-domain>/index.html`.
   - Put that Services ID + return URL in `config.js`
     (`APPLE_SERVICE_ID`, `APPLE_REDIRECT_URI`).
   - On the **auth Worker**, set the same value so it accepts the web token:
     ```sh
     cd AuctionBaby/auth && npx wrangler secret put WEB_CLIENT_ID   # = com.valasek.auctionbaby.web
     npx wrangler deploy
     ```
     *(The Worker now accepts both the app bundle id and this web Services ID —
     that change is in `auth/src/index.ts`.)*
3. **Payments = Stripe** (the `consumables` Worker speaks Stripe for both):
   - Set `CHECKOUT_SUCCESS_URL` / `CHECKOUT_CANCEL_URL` in `config.js`.
   - **Gavel packs** → `POST /checkout` (one-time). PackIds are
     `gavels_handful/stack/chest/vault` (already matched in `app.js`).
   - **Passes** → `POST /subscribe` (**recurring, Stripe Billing** — added to the
     Worker). PassIds `pass_paddle/pass_reserve/pass_blackcard`. The webhook
     records the active Pass in **KV** (`pass:{userId}`); `GET /subscription?userId=`
     reads it; `customer.subscription.deleted` clears it.
   - Redeploy the Worker: `cd AuctionBaby/consumables && npx wrangler deploy`
     (a **KV namespace** must be bound for Pass entitlement to persist), and add
     `customer.subscription.deleted` to your Stripe webhook event list.
4. **Deploy the web app** to Cloudflare Pages (above). Done — it's live.

**Photos:** the floor now renders real profile photos when the auth Worker
returns them (needs `PHOTOS_PUBLIC_URL` set + R2 bound); otherwise it falls back
to gradient monograms. No client change needed.

### Field-shape note (verify against your live Workers)
`api.js`/`mapLot`/`syncMatches` use tolerant field names (`floor`/`users`,
`location`/`city`, `prompts[].answer`, `messages[].fromMe/text`). If your
Workers return different keys, adjust those two mappers in `app.js` — everything
else flows from them.

### Nice-to-haves
- **Photos:** wire real R2 photo URLs (the app already uploads them) instead of gradient avatars.
- **iOS icon:** add a PNG `apple-touch-icon` (180×180) for a crisp home-screen icon (SVG covers Android/desktop).
- **Push:** Web Push (VAPID) instead of APNs.

## Why this path
- No App Review gate — you ship and iterate freely.
- Reuses the Cloudflare backend you've already built and deployed.
- Better economics on payments (Stripe vs. Apple's cut).
- Add-to-Home-Screen gives a near-native feel on iOS and Android.
