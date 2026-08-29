/* Auction Baby web — configuration.
   Fill these in to go LIVE. Leave them blank to run in on-device DEMO mode
   (localStorage only, no network) — the app detects `live` from these values.

   All three are the SAME Cloudflare Workers your iOS app already uses. */

// ── Where this build is served from ─────────────────────────────────────────
// Derived at load time from the page's own address, so the app carries no
// hardcoded hostname. Moving to a custom domain (auctionbaby.app) needs no
// change here at all — every URL below follows automatically.
//
// Set SITE_URL_OVERRIDE to pin it to a fixed address instead. The only reason
// to do that is if you ever serve the same build from more than one hostname
// and need Apple's redirect to resolve to one canonical URL.
const SITE_URL_OVERRIDE = "";
const SITE_URL = SITE_URL_OVERRIDE ||
  (location.origin + location.pathname.replace(/[^/]*$/, ""));   // …/app/

window.AB_CONFIG = {
  // The resolved base, exposed so the app and any tooling can read it.
  SITE_URL,

  // ── Backends (your deployed Workers) ─────────────────────────────────────
  AUTH_URL:       "https://auctionbaby-auth.mvalasek77.workers.dev",
  MATCHING_URL:   "https://auctionbaby-matching.mvalasek77.workers.dev",
  CONSUMABLES_URL:"https://auctionbaby-consumables.mvalasek77.workers.dev",

  // ── Sign in with Apple for the Web ───────────────────────────────────────
  // Create a **Services ID** in the Apple Developer portal (NOT the app bundle
  // id), enable "Sign in with Apple", add your web domain + a Return URL of
  // <your-domain>/index.html. Put that Services ID here, and set the same value
  // as WEB_CLIENT_ID in the auth Worker so it accepts the web token audience.
  //
  // ⚠️  Apple matches the Return URL character for character. When the domain
  // changes, register the NEW url in the portal (and verify the domain) BEFORE
  // pointing DNS at it — otherwise every web sign-in fails the moment it moves.
  APPLE_SERVICE_ID: "com.valasek.auctionbaby.web",
  APPLE_REDIRECT_URI: SITE_URL + "index.html",

  // ── Payments (Stripe, via the consumables Worker) ────────────────────────
  // The consumables Worker holds the Stripe secret; the web only needs the
  // return URLs. Gavel packs use /checkout (one-time); Passes use /subscribe
  // (recurring Stripe Billing). Both are implemented in the Worker.
  //
  // The client sends these with every checkout, so they win over the Worker's
  // SUCCESS_URL/CANCEL_URL defaults — no redeploy needed when the domain moves.
  CHECKOUT_SUCCESS_URL: SITE_URL + "index.html#/store?paid=1",
  CHECKOUT_CANCEL_URL:  SITE_URL + "index.html#/store",

  // ── Web Push (VAPID) ─────────────────────────────────────────────────────
  // Generate a VAPID keypair (e.g. `npx web-push generate-vapid-keys`). Put the
  // PUBLIC key here; keep the PRIVATE key as a Worker secret. The Worker stores
  // subscriptions (POST /devices/register) and sends encrypted Web Push.
  // See web/PUSH.md for the server contract.
  VAPID_PUBLIC_KEY: "",           // base64url public key
};

// live == every backend URL present. Auth/pay each check their own deps.
window.AB_LIVE = !!(window.AB_CONFIG.AUTH_URL && window.AB_CONFIG.MATCHING_URL);
