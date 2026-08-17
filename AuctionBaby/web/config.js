/* Auction Baby web — configuration.
   Fill these in to go LIVE. Leave them blank to run in on-device DEMO mode
   (localStorage only, no network) — the app detects `live` from these values.

   All three are the SAME Cloudflare Workers your iOS app already uses. */
window.AB_CONFIG = {
  // ── Backends (your deployed Workers) ─────────────────────────────────────
  AUTH_URL:       "",  // e.g. "https://auctionbaby-auth.<sub>.workers.dev"
  MATCHING_URL:   "",  // e.g. "https://auctionbaby-matching.<sub>.workers.dev"
  CONSUMABLES_URL:"",  // e.g. "https://auctionbaby-consumables.<sub>.workers.dev"

  // ── Sign in with Apple for the Web ───────────────────────────────────────
  // Create a **Services ID** in the Apple Developer portal (NOT the app bundle
  // id), enable "Sign in with Apple", add your web domain + a Return URL of
  // <your-domain>/index.html. Put that Services ID here, and set the same value
  // as WEB_CLIENT_ID in the auth Worker so it accepts the web token audience.
  APPLE_SERVICE_ID: "",           // e.g. "com.valasek.auctionbaby.web"
  APPLE_REDIRECT_URI: "",         // e.g. "https://auctionbaby.pages.dev/index.html"

  // ── Payments (Stripe, via the consumables Worker) ────────────────────────
  // The consumables Worker holds the Stripe secret; the web only needs the
  // return URLs. Gavel packs use /checkout (one-time). Subscriptions need a
  // Stripe Billing endpoint — see README "Subscriptions".
  CHECKOUT_SUCCESS_URL: "",       // e.g. "https://auctionbaby.pages.dev/index.html#/store?paid=1"
  CHECKOUT_CANCEL_URL:  "",       // e.g. "https://auctionbaby.pages.dev/index.html#/store"
};

// live == every backend URL present. Auth/pay each check their own deps.
window.AB_LIVE = !!(window.AB_CONFIG.AUTH_URL && window.AB_CONFIG.MATCHING_URL);
