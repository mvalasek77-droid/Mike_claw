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

## Current state vs. next steps
**Working now (demo, on-device):** onboarding, the Floor + Lot of the Day, lot
detail, the bid sheet with the spend disclosure, simulated accept → SOLD!
celebration → match → chat with replies, the Store (Gavels + Passes), and a
profile/reset. Persists to `localStorage`; installable + offline.

**To make it live (real users + payments):**
1. **Backend:** point `app.js`'s (currently stubbed) actions at the existing
   Cloudflare Workers — auth, `/users/floor`, matching/messages. The APIs already
   exist; the web client just needs `fetch` calls + a session token in
   `localStorage` (Sign in with Apple **JS**, Google, or email OTP for the web).
2. **Payments = Stripe, not Apple IAP.** The web can't use StoreKit. The
   `consumables` Worker already speaks Stripe — wire the Store's Checkout buttons
   to Stripe Checkout for Gavel packs and the Pass subscriptions (Stripe Billing).
   Web payments keep 100% minus Stripe fees (no 15–30% Apple cut).
3. **Photos:** real uploads → R2 (as the app already does), or keep the
   generated gradient avatars.
4. **iOS icon polish:** add PNG `apple-touch-icon` sizes (180×180) for a crisp
   home-screen icon; the SVG covers Android/desktop install.
5. **Push:** Web Push (VAPID) instead of APNs, if you want notifications.

## Why this path
- No App Review gate — you ship and iterate freely.
- Reuses the Cloudflare backend you've already built and deployed.
- Better economics on payments (Stripe vs. Apple's cut).
- Add-to-Home-Screen gives a near-native feel on iOS and Android.
