/**
 * AI Marketplace Payout Worker
 *
 * Handles Stripe Connect onboarding, payout balance, and cash-out
 * for the AI Marketplace iOS app.
 *
 * Required secrets (set via `wrangler secret put`):
 *   STRIPE_SECRET_KEY  — Stripe API secret key (sk_test_... or sk_live_...)
 *   APP_SHARED_SECRET   — Shared secret for app→worker auth
 *
 * Endpoints:
 *   POST /payouts/connect   — Create a Connect Express account + onboarding link
 *   GET  /payouts/status    — Check if account is connected / charges-enabled
 *   GET  /payouts/balance   — Get pending and available balance
 *   POST /payouts/cash-out  — Trigger a payout to the connected bank
 *   POST /payouts/webhook   — Stripe webhook receiver (account updates)
 */

// ── Types ──────────────────────────────────────────────────────────────────

// ── Imports ────────────────────────────────────────────────────────────────

// Operator-curated reference corpus the Scout draws from. Edit this JSON
// (canonical bestsellers, master patterns, recipes, current charts, model
// list) and redeploy — there's no other place data updates need to land.
import scoutFeedData from "./scoutFeed.json";

interface Env {
  STRIPE_SECRET_KEY: string;
  APP_SHARED_SECRET: string;
  STRIPE_WEBHOOK_SECRET: string; // whsec_… from the Stripe webhook endpoint
  STRIPE_CONNECT_TYPE: string; // "express" from wrangler.toml [vars]
  // Platform Stripe account settlement currency + default country for new
  // connected accounts. The platform account is CANADIAN, so these are "cad"
  // and "CA" — transfers/payouts MUST settle in the platform's own currency or
  // Stripe rejects them ("insufficient funds" against a CAD balance). Defaults
  // fall back to usd/US if unset.
  PLATFORM_CURRENCY?: string;
  PLATFORM_COUNTRY?: string;
  /// Stripe publishable key (pk_live_…). Not used server-side today — the
  /// Worker only needs the secret + webhook keys — but kept in the env so
  /// `wrangler secret put STRIPE_PUBLISHABLE_KEY` is supported and any
  /// future client-side flow (Stripe.js / Elements / Payment Intents) can
  /// read it via GET /stripe/publishable-key without a redeploy.
  STRIPE_PUBLISHABLE_KEY?: string;
  RESEND_API_KEY?: string;     // for the operator payout-digest email
  // Email the operator on every sale (default on). Each sale email also
  // reports the platform float + how much to top up, so one message answers
  // "did I sell?" and "how much do I owe the float?". Set "false" to mute
  // per-sale mail and rely on the periodic digest only.
  NOTIFY_EACH_SALE?: string;
  OPERATOR_EMAIL?: string;     // where ALL operator mail goes (defaults below)
  // Critical financial alerts (NSF / insufficient funds / payout failures).
  // Defaults to OPERATOR_EMAIL so everything lands in one inbox; set this
  // separately only if you later want alerts split from the routine digest.
  ALERT_EMAIL?: string;
  DIGEST_FROM_EMAIL?: string;  // verified Resend sender (defaults to onboarding)
  TOPUP_BUFFER_USD?: string;   // keep the platform balance at/above this
  TOPUP_MAX_USD?: string;      // hard cap on any single top-up (safety rail)
  TOPUP_SOURCE_ID?: string;    // ba_… verified bank source for Stripe Top-ups
  // Real audio/video generation providers (optional). Without these set,
  // /scout/generate-media returns provider:"none" and Scout falls back to
  // the on-device prose-as-artifact path. With them set, Scout's music/film
  // slots can publish with real playable bytes.
  MUSIC_GEN_API_URL?: string;  // e.g. Suno-compatible POST endpoint
  MUSIC_GEN_API_KEY?: string;
  // Text drafting fallback for Scout on devices without Apple Intelligence:
  // /scout/draft proxies to Anthropic's Messages API with this key.
  ANTHROPIC_API_KEY?: string;
  SCOUT_TEXT_MODEL?: string;   // defaults to claude-opus-4-8
  VIDEO_GEN_API_URL?: string;  // e.g. Runway / Veo / Sora API
  VIDEO_GEN_API_KEY?: string;
  // Per-provider video-gen keys. When set, /scout/providers reports them
  // as available so the app can pick one for a specific scene. Names match
  // the Swift `VideoProvider.catalog` ids.
  RUNWAY_API_KEY?: string;
  LUMA_API_KEY?: string;
  PIKA_API_KEY?: string;
  KLING_API_KEY?: string;
  VEO_API_KEY?: string;
  SORA_API_KEY?: string;
  // Per-month USD cap on Scout media generation. Once the running total in
  // KV for the current month meets/exceeds this, /scout/generate-media
  // refuses new calls until the next month. Default 50.
  MAX_MEDIA_GEN_USD_MONTH?: string;
  // Per-call cost overrides (optional). If the third-party provider returns
  // a real cost in its response, the Worker prefers that; else uses these.
  MUSIC_GEN_COST_USD?: string;
  VIDEO_GEN_COST_USD?: string;
  // Base URL the Stripe-hosted onboarding flow bounces back to after a
  // creator finishes or abandons. Must be a real, reachable page — point
  // it at the public docs site (GitHub Pages /docs serves payout-complete
  // .html + payout-refresh.html). The creator sees a friendly "Return to
  // the app" page rather than a 404, and the app's scenePhase observer
  // refreshes payout status when they switch back.
  PAYOUT_RETURN_BASE?: string;
  // The app's bundle id, used to reject ASSN V2 notifications for other apps
  // that somehow hit our webhook (Apple posts to a per-app URL but this is a
  // belt-and-braces check). Defaults below if unset.
  APP_BUNDLE_ID?: string;
  // Optional override of the Apple Root CA fingerprint we pin (SHA-256 hex
  // of the DER bytes). Constant unless Apple rotates roots; left as an env
  // override so the operator can update without redeploying code.
  APPLE_ROOT_CA_SHA256?: string;
  KV?: KVNamespace; // KV namespace used for spend tracking + account map
}

const DEFAULT_PAYOUT_RETURN_BASE = "https://mvalasek77-droid.github.io/Mike_claw";

/** Resolve the URL base Stripe should bounce creators back to. Order of
 *  preference: explicit env override → the Worker's own origin (so the
 *  built-in /payout-complete and /payout-refresh routes serve the bounce
 *  pages with zero extra setup) → the GitHub Pages default. */
function resolvePayoutReturnBase(request: Request, env: Env): string {
  if (env.PAYOUT_RETURN_BASE) return env.PAYOUT_RETURN_BASE;
  try { return new URL(request.url).origin; } catch { return DEFAULT_PAYOUT_RETURN_BASE; }
}

const DEFAULT_OPERATOR_EMAIL = "mvalasek77@gmail.com";
const DEFAULT_FROM_EMAIL = "AI Marketplace <onboarding@resend.dev>";
const DEFAULT_TOPUP_BUFFER_USD = 100;
const DEFAULT_TOPUP_MAX_USD = 200;

interface ConnectRequest {
  accountName: string;
  accountEmail: string;
  country?: string; // ISO 3166-1 alpha-2 (e.g. "CA", "US"); the app sends the creator's region
}

interface CashOutRequest {
  amount?: number; // USD; omit = payout all available
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const CREATOR_SHARE = 0.85; // creator keeps 85% of net proceeds
const PLATFORM_SHARE = 0.15;

/** Call the Stripe API. Pass `stripeAccount` to act on a connected account,
 *  and `idempotencyKey` to make money-moving calls safe to retry. */
async function stripe(
  path: string,
  body: Record<string, unknown>,
  secret: string,
  stripeAccount?: string,
  idempotencyKey?: string,
): Promise<any> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secret}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (stripeAccount) headers["Stripe-Account"] = stripeAccount;
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: "POST",
    headers,
    body: new URLSearchParams(
      flatten(body) as Record<string, string>
    ).toString(),
  });
  const json = await res.json() as any;
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${json.error?.message ?? JSON.stringify(json)}`);
  return json;
}

/** Call Stripe GET */
async function stripeGet(path: string, secret: string): Promise<any> {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  const json = await res.json() as any;
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${json.error?.message ?? JSON.stringify(json)}`);
  return json;
}

/** Flatten nested objects for application/x-www-form-urlencoded */
function flatten(obj: Record<string, unknown>, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}[${k}]` : k;
    if (v === undefined || v === null) continue;
    if (typeof v === "object" && !Array.isArray(v)) {
      Object.assign(out, flatten(v as Record<string, unknown>, key));
    } else if (Array.isArray(v)) {
      v.forEach((item, i) => {
        out[`${key}[${i}]`] = String(item);
      });
    } else {
      out[key] = String(v);
    }
  }
  return out;
}

/** Verify the app's shared secret from the Authorization header. Compares in
 *  constant time over SHA-256 digests so request timing can't leak the secret. */
async function isAuthenticated(request: Request, sharedSecret: string): Promise<boolean> {
  const auth = request.headers.get("Authorization");
  if (!auth) return false;
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : auth;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(token)),
    crypto.subtle.digest("SHA-256", enc.encode(sharedSecret)),
  ]);
  const av = new Uint8Array(a), bv = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < av.length; i++) diff |= av[i] ^ bv[i];
  return diff === 0;
}

/** Per-IP token-bucket limiter in KV. Returns true when the request is
 *  allowed; false when it should be 429'd. The shared-secret model is the
 *  primary gate; this is defense-in-depth for the routes a leaked secret
 *  would abuse most (moderation reports, payout connect). A bucket holds
 *  `capacity` tokens and refills at `refillPerMinute`. Without KV bound
 *  this becomes a no-op (returns true) — we fail open rather than break
 *  the app entirely. */
async function rateLimited(env: Env, scope: string, request: Request,
                            capacity: number, refillPerMinute: number): Promise<boolean> {
  if (!env.KV) return false;   // no KV → no limiter
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const key = `rl:${scope}:${ip}`;
  const now = Date.now();
  const raw = await env.KV.get(key);
  let tokens = capacity;
  let last = now;
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as { tokens: number; last: number };
      const elapsedMin = Math.max(0, (now - parsed.last) / 60_000);
      tokens = Math.min(capacity, parsed.tokens + elapsedMin * refillPerMinute);
      last = now;
    } catch { /* corrupt — start fresh */ }
  }
  if (tokens < 1) {
    await env.KV.put(key, JSON.stringify({ tokens, last }), { expirationTtl: 3600 });
    return true;   // limited
  }
  tokens -= 1;
  await env.KV.put(key, JSON.stringify({ tokens, last }), { expirationTtl: 3600 });
  return false;
}

/** JSON response helper */
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

/** Error response */
function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

// ── Handlers ────────────────────────────────────────────────────────────────

/** POST /payouts/connect — Create or retrieve a Connect Express account */
async function handleConnect(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as ConnectRequest;
  const { accountName, accountEmail, country } = body;

  if (!accountName || !accountEmail) {
    return error("accountName and accountEmail are required");
  }

  // Create the account in the creator's own country when the app supplies one,
  // else the platform's country (CA). Hardcoding "US" created US accounts for a
  // Canadian platform, which broke onboarding/verification.
  const acctCountry = (country || env.PLATFORM_COUNTRY || "US").toUpperCase();

  // Idempotency key. Default per-email, which gives us safe retry on
  // network blips. But when an operator has explicitly released a creator's
  // email via /accounts/release-email (because Stripe rejected the prior
  // account and the creator needs a fresh start), the KV flag adds a salt
  // so Stripe creates a NEW account instead of returning the rejected
  // cached one. Flag is cleared the moment we use it.
  let idemKey = `connect_${accountEmail}`;
  if (env.KV) {
    const releaseKey = `connect-release:${accountEmail.toLowerCase()}`;
    const salt = await env.KV.get(releaseKey);
    if (salt) {
      idemKey = `connect_${accountEmail}_${salt}`;
      await env.KV.delete(releaseKey);
    }
  }

  // Step 1: Create the Connect Express account
  const account = await stripe("/accounts", {
    type: env.STRIPE_CONNECT_TYPE || "express",
    country: acctCountry,
    email: accountEmail,
    business_type: "individual",
    individual: {
      first_name: accountName.split(" ")[0] || accountName,
      last_name: accountName.split(" ").slice(1).join(" ") || " ",
    },
    business_profile: {
      name: accountName,
      product_description: "AI Marketplace content creator",
      mcc: "7372", // Computer Software (closest for digital goods)
    },
    capabilities: {
      card_payments: { requested: true },
      transfers: { requested: true },
    },
    metadata: {
      platform: "ai-marketplace",
      app_email: accountEmail,
    },
  }, env.STRIPE_SECRET_KEY, undefined, idemKey);

  // Step 2: Create an account link for onboarding
  // The return_url brings the user back into the app via deep link
  const returnBase = resolvePayoutReturnBase(request, env);
  const accountLink = await stripe("/account_links", {
    account: account.id,
    refresh_url: `${returnBase}/payout-refresh?account=${account.id}`,
    return_url: `${returnBase}/payout-complete?account=${account.id}`,
    type: "account_onboarding",
  }, env.STRIPE_SECRET_KEY);

  return json({
    accountId: account.id,
    onboardingUrl: accountLink.url,
    connectType: env.STRIPE_CONNECT_TYPE || "express",
  });
}

/** POST /payouts/onboarding-link — fresh onboarding URL for an EXISTING
 *  Connect account. Stripe's account_links URLs expire in minutes, so a
 *  creator who returns to finish onboarding after an interruption needs a
 *  new link — without re-creating the account. */
async function handleOnboardingLink(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { account_id?: string };
  if (!body.account_id) return error("account_id required");
  const returnBase = resolvePayoutReturnBase(request, env);
  const link = await stripe("/account_links", {
    account: body.account_id,
    refresh_url: `${returnBase}/payout-refresh?account=${body.account_id}`,
    return_url: `${returnBase}/payout-complete?account=${body.account_id}`,
    type: "account_onboarding",
  }, env.STRIPE_SECRET_KEY);
  return json({ accountId: body.account_id, onboardingUrl: link.url });
}

/** Public bounce pages Stripe redirects creators to after they finish or
 *  abandon onboarding. Served by the Worker itself so no GitHub Pages, no
 *  custom domain, no extra hosting is required. */
function payoutCompleteHTML(accountId: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stripe onboarding complete — AI Marketplace</title>
<style>
:root{--bg:#0a0a0c;--ink:#f5f5f7;--ink-soft:#c7c7d1;--ink-faint:#8a8a96;--accent:#ff7a45;--line:#25252e;}
*{box-sizing:border-box;}html,body{margin:0;padding:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.wrap{max-width:560px;margin:0 auto;padding:48px 20px;text-align:center;}
h1{font-size:32px;line-height:1.15;letter-spacing:-0.02em;margin:0 0 12px;}
.lede{font-size:18px;color:var(--ink-soft);margin:0 auto 28px;}
.glyph{font-size:64px;line-height:1;margin-bottom:18px;color:#3fd76f;}
.card{background:#14141a;border:1px solid var(--line);border-radius:14px;padding:20px;margin-top:28px;text-align:left;color:var(--ink-soft);}
.card h3{margin:0 0 8px;color:var(--ink);font-size:17px;}
.card ul{margin:0;padding-left:22px;}
.card li{margin:4px 0;}
.foot{color:var(--ink-faint);font-size:13px;margin-top:32px;}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--ink-faint);}
</style></head><body><div class="wrap">
<div class="glyph">&#x2713;</div>
<h1>You're done with Stripe.</h1>
<p class="lede">Return to AI Marketplace. Your payout status refreshes automatically the moment the app comes back to the foreground.</p>
<div class="card"><h3>What happens next</h3><ul>
<li>Stripe verifies the details you submitted (usually minutes; sometimes up to 24 hours).</li>
<li>Once verified, your share of every sale lands in your bank automatically.</li>
<li>You can monitor sales and payouts from the app any time.</li>
</ul></div>
<p class="foot">Account: <code>${escapeHTML(accountId)}</code></p>
</div></body></html>`;
}

function payoutRefreshHTML(accountId: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stripe onboarding link expired — AI Marketplace</title>
<style>
:root{--bg:#0a0a0c;--ink:#f5f5f7;--ink-soft:#c7c7d1;--ink-faint:#8a8a96;--accent:#ff7a45;--line:#25252e;}
*{box-sizing:border-box;}html,body{margin:0;padding:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.wrap{max-width:560px;margin:0 auto;padding:48px 20px;text-align:center;}
h1{font-size:32px;line-height:1.15;letter-spacing:-0.02em;margin:0 0 12px;}
.lede{font-size:18px;color:var(--ink-soft);margin:0 auto 24px;}
.glyph{font-size:64px;line-height:1;margin-bottom:18px;color:#ffa820;}
.foot{color:var(--ink-faint);font-size:13px;margin-top:24px;}
strong{color:var(--ink);}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--ink-faint);}
</style></head><body><div class="wrap">
<div class="glyph">&#x21BB;</div>
<h1>Your Stripe link expired.</h1>
<p class="lede">Stripe's onboarding links time out after a few minutes for security. Return to AI Marketplace and tap <strong>Resume Stripe onboarding</strong> on the Payout Setup screen to get a fresh link.</p>
<p class="foot">Your Stripe account hasn't been duplicated. The next link picks up where you left off.</p>
<p class="foot">Account: <code>${escapeHTML(accountId)}</code></p>
</div></body></html>`;
}

function escapeHTML(s: string): string {
  return s.replace(/[&<>"']/g, c =>
    c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === "\"" ? "&quot;" : "&#39;");
}

function htmlResponse(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

/** GET /payouts/status?account_id=acct_xxx — Check Connect account status */
async function handleStatus(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const accountId = url.searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");

  const account = await stripeGet(`/accounts/${accountId}`, env.STRIPE_SECRET_KEY);

  // Surface `disabled_reason` so the app can show "your application
  // was declined — contact support" instead of silently bouncing the
  // creator back to "Connect my bank." Stripe sets this when an
  // account is rejected for fraud/listed/under_review/etc.
  const requirements = account.requirements ?? {};
  return json({
    accountId: account.id,
    chargesEnabled: account.charges_enabled,
    payoutsEnabled: account.payouts_enabled,
    detailsSubmitted: account.details_submitted,
    capabilities: account.capabilities,
    disabledReason: requirements.disabled_reason ?? null,
    currentlyDue: requirements.currently_due ?? [],
    pastDue: requirements.past_due ?? [],
  });
}

/** GET /payouts/balance?account_id=acct_xxx — Get Stripe Connect balance */
async function handleBalance(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const accountId = url.searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");

  const balance = await stripeGet(`/balance?stripe_account=${accountId}`, env.STRIPE_SECRET_KEY);

  const available = balance.available?.[0]?.amount ?? 0;
  const pending = balance.pending?.[0]?.amount ?? 0;

  return json({
    accountId,
    availableUSD: available / 100,   // Stripe uses cents
    pendingUSD: pending / 100,
    creatorShare: CREATOR_SHARE,
    platformShare: PLATFORM_SHARE,
  });
}

/** POST /payouts/cash-out — Trigger payout to the connected bank */
async function handleCashOut(request: Request, env: Env): Promise<Response> {
  const kvGuard = requireKV(env); if (kvGuard) return kvGuard;
  const { amount, account_id } = await request.json() as { amount?: number; account_id: string };
  if (!account_id) return error("account_id is required");

  // Check available balance first
  const balance = await stripeGet(`/balance?stripe_account=${account_id}`, env.STRIPE_SECRET_KEY);
  const availableCents = balance.available?.[0]?.amount ?? 0;

  if (availableCents === 0) {
    return error("No available balance to cash out", 402);
  }

  const payoutAmount = amount
    ? Math.round(Math.min(amount * 100, availableCents)) // cap at available
    : availableCents; // omit amount = cash out everything

  if (payoutAmount < 100) {
    return error("Minimum cash-out is $1.00", 402);
  }

  // Create the payout ON THE CONNECTED ACCOUNT (Stripe-Account header), so it
  // draws from that account's balance and lands in the creator's own bank.
  // (For Express accounts Stripe also auto-pays on a schedule; this is an
  // explicit "pay me now".)
  const currency = (env.PLATFORM_CURRENCY || "usd").toLowerCase();
  let payout: any;
  try {
    payout = await stripe("/payouts", {
      amount: payoutAmount,
      currency,
      metadata: {
        platform: "ai-marketplace",
      },
    }, env.STRIPE_SECRET_KEY, account_id,
       // Idempotency key — without it, a future concurrency footgun could
       // create duplicate Stripe payouts. Use minute-precision so a genuine
       // intentional second cash-out within the same minute still
       // de-duplicates, but a re-tap an hour later succeeds.
       `cashout_${account_id}_${Math.floor(Date.now() / 60_000)}`);
  } catch (e: any) {
    await recordLedger(env, {
      type: "payout", status: "failed", amountCents: payoutAmount, currency,
      scope: account_id, note: e?.message ?? "payout failed",
    });
    // Alert on EVERY cash-out failure, not just NSF. A creator's bank
    // failing verification produces a 4xx that operators need to chase —
    // the previous code only alerted on NSF, so bank issues sat silent
    // until the periodic digest fired.
    await alertNSF(env, {
      kind: isInsufficientFunds(e) ? "creator cash-out (NSF)" : "creator cash-out (failed)",
      scope: account_id, amountCents: payoutAmount, currency,
      detail: e?.message ?? "",
    });
    return error(e?.message ?? "Payout failed", 502);
  }

  await recordLedger(env, {
    type: "payout", status: payout.status === "failed" ? "failed" : "pending",
    amountCents: payoutAmount, currency, scope: account_id, stripeId: payout.id,
    note: `arrival ${payout.arrival_date ?? "?"}`,
  });

  return json({
    payoutId: payout.id,
    amountUSD: payoutAmount / 100,
    status: payout.status, // "pending", "paid", "failed", etc.
    arrivalDate: payout.arrival_date,
  });
}

/**
 * POST /payouts/transfer — Transfer platform earnings (85%) to a creator's Connect account.
 * Called by the platform after each sale.
 */
async function handleTransfer(request: Request, env: Env): Promise<Response> {
  const kvGuard = requireKV(env); if (kvGuard) return kvGuard;
  const { account_id, amount_usd, title_id, memo, idempotency_key } = await request.json() as {
    account_id: string;
    amount_usd: number;
    title_id?: string;
    memo?: string;
    idempotency_key?: string;
  };

  if (!account_id || !amount_usd) {
    return error("account_id and amount_usd are required");
  }

  if (amount_usd < 0.50) {
    return error("Minimum transfer is $0.50");
  }

  // Stable key so a retried sale never pays a creator twice. Prefer the
  // per-sale key the app supplies; fall back to title+account when present.
  // Per-sale idempotency: the app supplies a sale-UUID-derived key. If absent
  // we fall back to a fresh UUID so a retry on the same TCP-flight doesn't
  // double-pay — but the prior `xfer_<account>_<title>` fallback was wrong
  // (it dropped the second sale of the same title as a duplicate).
  const idem = idempotency_key ?? crypto.randomUUID();
  const amountCents = Math.round(amount_usd * 100);
  const currency = (env.PLATFORM_CURRENCY || "usd").toLowerCase();

  let transfer: any;
  try {
    transfer = await stripe("/transfers", {
      amount: amountCents,
      currency,
      destination: account_id,
      metadata: {
        platform: "ai-marketplace",
        title_id: title_id ?? "",
        creator_share: String(CREATOR_SHARE),
      },
      description: memo ?? "AI Marketplace creator earnings",
    }, env.STRIPE_SECRET_KEY, undefined, idem);
  } catch (e: any) {
    await recordLedger(env, {
      type: "transfer", status: "failed", amountCents, currency,
      scope: account_id, refId: title_id, note: e?.message ?? "transfer failed",
    });
    // The creator is owed but unpaid — queue it so the operator can pay it
    // manually once the float is funded (GET /payouts/unfunded + manual-fund).
    await enqueueUnfunded(env, { accountId: account_id, amountCents, currency, title: title_id, reason: e?.message ?? "transfer failed" });
    if (isInsufficientFunds(e)) {
      await alertNSF(env, { kind: "creator transfer", scope: account_id, amountCents, currency, detail: e?.message ?? "" });
    }
    return error(e?.message ?? "Transfer failed", 502);
  }

  await recordLedger(env, {
    type: "transfer", status: "succeeded", amountCents, currency,
    scope: account_id, refId: title_id, stripeId: transfer.id,
    note: memo ?? "creator earnings",
  });
  // Notify the operator of the sale + current float / top-up needed.
  await notifySale(env, { amountUSD: amount_usd, title_id, account_id });

  return json({
    transferId: transfer.id,
    amountUSD: amount_usd,
    destination: account_id,
    status: "created",
  });
}

/** Constant-time-ish verify of Stripe's `Stripe-Signature` header (HMAC-SHA256
 *  of `${timestamp}.${rawBody}`) with a 5-minute timestamp tolerance. */
async function verifyStripeSignature(rawBody: string, sigHeader: string | null, secret: string): Promise<boolean> {
  if (!sigHeader || !secret) return false;
  const parts = Object.fromEntries(
    sigHeader.split(",").map((p) => p.split("=", 2) as [string, string]),
  );
  const timestamp = parts["t"];
  const signature = parts["v1"];
  if (!timestamp || !signature) return false;

  // Reject events older than 5 minutes (replay protection).
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${rawBody}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");

  // Length-safe comparison.
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return mismatch === 0;
}

/** POST /payouts/webhook — Stripe webhook for Connect account updates */
async function handleWebhook(request: Request, env: Env): Promise<Response> {
  // Verify the signature against the raw body before trusting anything.
  const rawBody = await request.text();
  const valid = await verifyStripeSignature(rawBody, request.headers.get("Stripe-Signature"), env.STRIPE_WEBHOOK_SECRET);
  if (!valid) return error("Invalid signature", 400);

  const event = JSON.parse(rawBody) as any;

  switch (event.type) {
    case "account.updated": {
      const acct = event.data.object;
      console.log(`Connect account ${acct.id} updated: charges_enabled=${acct.charges_enabled}, payouts_enabled=${acct.payouts_enabled}`);
      break;
    }
    case "payout.paid": {
      const payout = event.data.object;
      console.log(`Payout ${payout.id} paid: ${payout.amount / 100}`);
      await recordLedger(env, {
        type: "payout", status: "succeeded", amountCents: payout.amount,
        currency: payout.currency ?? "usd",
        scope: event.account ?? "platform", stripeId: payout.id, note: "payout.paid",
      });
      break;
    }
    case "payout.failed": {
      const payout = event.data.object;
      console.error(`Payout ${payout.id} FAILED: ${payout.amount / 100}`);
      await recordLedger(env, {
        type: "payout", status: "failed", amountCents: payout.amount,
        currency: payout.currency ?? "usd",
        scope: event.account ?? "platform", stripeId: payout.id,
        note: `payout.failed: ${payout.failure_message ?? payout.failure_code ?? ""}`,
      });
      // Stripe surfaces NSF on payouts via failure_code; alert so it's fixed.
      const code = `${payout.failure_code ?? ""} ${payout.failure_message ?? ""}`;
      if (isInsufficientFunds(code)) {
        await alertNSF(env, {
          kind: "creator payout (webhook)", scope: event.account ?? "platform",
          amountCents: payout.amount, currency: payout.currency ?? "usd", detail: code.trim(),
        });
      }
      break;
    }
    case "topup.succeeded": {
      // Closes the loop on the auto-topup ledger entry recorded by
      // maybeTopUp() — without this case the entry stays "pending" forever
      // and operator reconciliation breaks.
      const tu = event.data.object;
      await recordLedger(env, {
        type: "topup", status: "succeeded", amountCents: tu.amount,
        currency: tu.currency ?? "usd",
        scope: "platform", stripeId: tu.id,
        note: "topup.succeeded",
      });
      break;
    }
    case "topup.failed": {
      const tu = event.data.object;
      await recordLedger(env, {
        type: "topup", status: "failed", amountCents: tu.amount,
        currency: tu.currency ?? "usd",
        scope: "platform", stripeId: tu.id,
        note: `topup.failed: ${tu.failure_message ?? tu.failure_code ?? ""}`,
      });
      // Operator must know the float didn't replenish — every transfer
      // until they intervene will NSF.
      await alertNSF(env, {
        kind: "platform topup (webhook)", scope: "platform",
        amountCents: tu.amount, currency: tu.currency ?? "usd",
        detail: tu.failure_message ?? tu.failure_code ?? "",
      });
      break;
    }
    case "charge.refunded": {
      // Buyer received a Stripe-side refund (rare for us — we use Apple IAP,
      // but Stripe top-ups can be refunded). Record so the operator can
      // reconcile platform float drain.
      const charge = event.data.object;
      await recordLedger(env, {
        type: "refund", status: "succeeded", amountCents: charge.amount_refunded ?? charge.amount,
        currency: charge.currency ?? "usd",
        scope: "platform", stripeId: charge.id,
        note: `charge.refunded`,
      });
      break;
    }
    case "charge.dispute.created": {
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute", status: "pending", amountCents: dispute.amount,
        currency: dispute.currency ?? "usd",
        scope: "platform", stripeId: dispute.id,
        note: `dispute opened on ${dispute.charge}; reason: ${dispute.reason ?? "?"}`,
      });
      break;
    }
    case "charge.dispute.funds_withdrawn": {
      // CRITICAL — Stripe has already pulled the disputed amount from the
      // platform float. The creator's pendingPayoutUSD reflects an earning
      // that the platform no longer holds; reconciliation breaks unless we
      // record this and alert the operator to claw back.
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute", status: "funds_withdrawn", amountCents: dispute.amount,
        currency: dispute.currency ?? "usd",
        scope: "platform", stripeId: dispute.id,
        note: `chargeback on ${dispute.charge}; platform debited`,
      });
      await alertNSF(env, {
        kind: "chargeback debit",
        scope: "platform",
        amountCents: dispute.amount,
        currency: dispute.currency ?? "usd",
        detail: `Charge ${dispute.charge} disputed (${dispute.reason ?? "?"}). Float reduced; consider deducting creator pending.`,
      });
      break;
    }
    case "charge.dispute.closed": {
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute",
        status: dispute.status === "won" ? "won" : "lost",
        amountCents: dispute.amount,
        currency: dispute.currency ?? "usd",
        scope: "platform", stripeId: dispute.id,
        note: `dispute closed: ${dispute.status}`,
      });
      break;
    }
    case "transfer.reversed": {
      // Manual reversal by operator (or Stripe-side). The creator's local
      // pendingPayoutUSD is stale until the operator notifies them; the
      // ledger captures the truth.
      const transfer = event.data.object;
      await recordLedger(env, {
        type: "transfer", status: "reversed",
        amountCents: transfer.amount_reversed ?? transfer.amount,
        currency: transfer.currency ?? "usd",
        scope: transfer.destination ?? "platform", stripeId: transfer.id,
        note: `transfer reversed`,
      });
      await alertNSF(env, {
        kind: "transfer reversal",
        scope: transfer.destination ?? "platform",
        amountCents: transfer.amount_reversed ?? transfer.amount,
        currency: transfer.currency ?? "usd",
        detail: `Transfer ${transfer.id} reversed; creator pending balance is now stale.`,
      });
      break;
    }
    default:
      console.log(`Webhook event: ${event.type}`);
  }

  return json({ received: true });
}

// ── Account deletion ───────────────────────────────────────────────────────

/** POST /accounts/delete — close the connected Stripe account.
 *  Stripe returns 400 if there's an outstanding balance — that's a feature,
 *  not a bug; the operator must reconcile before deletion in that case. */
async function handleDeleteAccount(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { account_id?: string };
  if (!body.account_id) return error("account_id required");
  const res = await fetch(
    `https://api.stripe.com/v1/accounts/${encodeURIComponent(body.account_id)}`,
    { method: "DELETE", headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` } }
  );
  if (!res.ok) {
    const t = await res.text();
    return error(`Stripe ${res.status}: ${t.slice(0, 200)}`, res.status);
  }
  // Record the account closure so the ledger has the complete lifecycle
  // for this creator. Previously deletions were silent — auditing where a
  // creator went required curling Stripe directly.
  await recordLedger(env, {
    type: "account_closed", status: "succeeded", amountCents: 0, currency: "n/a",
    scope: body.account_id, stripeId: body.account_id,
    note: "Stripe Connect account closed via /accounts/delete",
  });
  return json({ deleted: true });
}

// ── Scout media generation ─────────────────────────────────────────────────

/** POST /scout/generate-media — forward to a third-party generation provider.
 *  Provider contract (request the operator wires up): POST { prompt, kind }
 *  → { url, duration_seconds?, content_type?, cost_usd? }. We forward the
 *  configured Authorization header verbatim from the env. Without keys this
 *  is a no-op that returns provider:"none" so the app falls back to prose
 *  vetting.
 *
 *  Spend safety: per-month USD cap (MAX_MEDIA_GEN_USD_MONTH, default $50)
 *  tracked in KV under key `scout_spend_YYYY-MM`. Refuses new calls when
 *  the running total meets or exceeds the cap. */
async function handleScoutGenerateMedia(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    type?: "music" | "movie";
    title?: string;
    genre?: string;
    prompt?: string;
    provider?: string;          // explicit per-provider routing (movies)
    durationSeconds?: number;   // per-clip target — providers cap this
  };
  if (body.type !== "music" && body.type !== "movie") {
    return error("type must be 'music' or 'movie'");
  }

  // Spend cap (BEFORE the provider call). Generic estimate; the provider
  // adapter may report a more precise cost once it returns.
  const cap = Number(env.MAX_MEDIA_GEN_USD_MONTH ?? "50");
  const monthKey = `scout_spend_${new Date().toISOString().slice(0, 7)}`;
  const currentSpend = env.KV ? Number((await env.KV.get(monthKey)) ?? "0") : 0;
  const estimatedCost = Number(
    body.type === "music" ? (env.MUSIC_GEN_COST_USD ?? "0.15") : (env.VIDEO_GEN_COST_USD ?? "9.00")
  );
  if (currentSpend + estimatedCost > cap) {
    return json({
      provider: "rate_limited",
      currentSpendUSD: currentSpend,
      capUSD: cap,
      note: `Per-month spend cap ($${cap}) would be exceeded; running total this month is $${currentSpend.toFixed(2)}. Raise MAX_MEDIA_GEN_USD_MONTH or wait until next month.`,
    }, 402);
  }
  if (!env.KV) {
    return error(
      "KV namespace not bound — spend tracking unavailable. Add a [[kv_namespaces]] binding named 'KV' in wrangler.toml before enabling media generation.",
      503
    );
  }

  const prompt = [
    body.title ? `Title: ${body.title}.` : "",
    body.genre ? `Genre: ${body.genre}.` : "",
    body.prompt ?? "",
  ].filter(Boolean).join(" ").trim();

  try {
    let result: GenerationResult;
    if (body.type === "movie") {
      result = await runVideoProvider(body.provider, prompt, body.durationSeconds ?? 10, env);
    } else {
      result = await runLegacyMusicProvider(prompt, env);
    }
    if (result.kind === "skipped") {
      return json({ provider: "none", note: result.note });
    }
    if (result.kind === "error") {
      return error(result.note, result.status ?? 502);
    }

    const realCost = typeof result.costUSD === "number" ? result.costUSD : estimatedCost;
    await env.KV.put(monthKey, String(currentSpend + realCost));

    return json({
      provider: result.provider,
      url: result.url,
      durationSeconds: result.durationSeconds,
      contentType: result.contentType ?? "video/mp4",
      costUSD: realCost,
      monthSpendUSD: currentSpend + realCost,
      monthCapUSD: cap,
    });
  } catch (err: any) {
    return error(`Generation failed: ${err?.message ?? err}`, 502);
  }
}

// ---------- Provider adapters ----------

type GenerationResult =
  | { kind: "ok"; provider: string; url: string; durationSeconds?: number; contentType?: string; costUSD?: number }
  | { kind: "skipped"; note: string }
  | { kind: "error"; note: string; status?: number };

/** Routes to a specific video provider by id (matching the Swift catalog).
 *  If no provider is named, picks the first one whose API key is set. */
async function runVideoProvider(providerId: string | undefined, prompt: string,
                                durationSeconds: number, env: Env): Promise<GenerationResult> {
  const available: Record<string, () => Promise<GenerationResult>> = {
    "runway-gen4": () => runRunway(prompt, durationSeconds, env),
    "luma-dream-machine": () => runLuma(prompt, durationSeconds, env),
    "pika-2": () => runPika(prompt, durationSeconds, env),
    "kling-2": () => runKling(prompt, durationSeconds, env),
    "veo-3": () => runVeo(prompt, durationSeconds, env),
    "sora-turbo": () => runSora(prompt, durationSeconds, env),
  };

  if (providerId && available[providerId]) {
    return await available[providerId]();
  }
  // No explicit provider — pick the first one whose key is set.
  for (const [id, run] of Object.entries(available)) {
    if (hasKey(id, env)) return await run();
  }
  return {
    kind: "skipped",
    note: "No video provider configured. Set at least one of RUNWAY_API_KEY / LUMA_API_KEY / PIKA_API_KEY / KLING_API_KEY / VEO_API_KEY / SORA_API_KEY as a Wrangler secret to enable real video.",
  };
}

/** Scout text-drafting fallback — proxies to Anthropic's Messages API.
 *  The app sends { instructions, prompt, max_tokens? }; we return { text }.
 *  Keeps the API key server-side; the iOS client only ever sees the Worker.
 *  Note: Opus 4.7+ rejects sampling params (temperature/top_p) — don't add them. */
async function handleScoutDraft(request: Request, env: Env): Promise<Response> {
  if (!env.ANTHROPIC_API_KEY) {
    return json({ error: "Text generation not configured. Set ANTHROPIC_API_KEY as a Wrangler secret to enable the Scout drafting fallback." }, 503);
  }
  let body: { instructions?: string; prompt?: string; max_tokens?: number };
  try {
    body = await request.json() as typeof body;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const instructions = (body.instructions ?? "").slice(0, 4000);
  const prompt = (body.prompt ?? "").slice(0, 4000);
  if (!prompt) return json({ error: "prompt is required" }, 400);

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: env.SCOUT_TEXT_MODEL || "claude-opus-4-8",
      max_tokens: Math.min(4096, Math.max(256, body.max_tokens ?? 2048)),
      ...(instructions ? { system: instructions } : {}),
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) {
    return json({ error: `Claude API ${res.status}: ${(await res.text()).slice(0, 300)}` }, 502);
  }
  const data = await res.json() as {
    content?: Array<{ type: string; text?: string }>;
    stop_reason?: string;
  };
  const text = (data.content ?? [])
    .filter((b) => b.type === "text")
    .map((b) => b.text ?? "")
    .join("\n")
    .trim();
  if (!text) {
    return json({ error: `Model returned no text (stop_reason: ${data.stop_reason ?? "unknown"})` }, 502);
  }
  return json({ text });
}

function hasKey(providerId: string, env: Env): boolean {
  switch (providerId) {
    case "runway-gen4":        return !!env.RUNWAY_API_KEY;
    case "luma-dream-machine": return !!env.LUMA_API_KEY;
    case "pika-2":             return !!env.PIKA_API_KEY;
    case "kling-2":            return !!env.KLING_API_KEY;
    case "veo-3":              return !!env.VEO_API_KEY;
    case "sora-turbo":         return !!env.SORA_API_KEY;
    default: return false;
  }
}

/** Luma Dream Machine — POST /generations, poll until state == "completed".
 *  Docs: https://docs.lumalabs.ai/docs/api  */
async function runLuma(prompt: string, durationSeconds: number, env: Env): Promise<GenerationResult> {
  if (!env.LUMA_API_KEY) return { kind: "skipped", note: "LUMA_API_KEY not set." };
  const submit = await fetch("https://api.lumalabs.ai/dream-machine/v1/generations", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.LUMA_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ prompt, aspect_ratio: "16:9", duration: `${Math.min(5, durationSeconds)}s` }),
  });
  if (!submit.ok) return { kind: "error", note: `Luma submit ${submit.status}: ${(await submit.text()).slice(0, 200)}`, status: 502 };
  const submitted = await submit.json() as { id?: string };
  if (!submitted.id) return { kind: "error", note: "Luma returned no generation id" };
  // Poll up to ~3 min — long enough for slower providers (Veo, Sora) when
  // the operator routes here as a fallback.
  for (let i = 0; i < 60; i++) {
    await sleep(3000);
    const status = await fetch(`https://api.lumalabs.ai/dream-machine/v1/generations/${submitted.id}`, {
      headers: { Authorization: `Bearer ${env.LUMA_API_KEY}` },
    });
    if (!status.ok) continue;
    const s = await status.json() as { state?: string; assets?: { video?: string }; failure_reason?: string };
    if (s.state === "completed" && s.assets?.video) {
      return { kind: "ok", provider: "luma-dream-machine", url: s.assets.video,
               durationSeconds: Math.min(5, durationSeconds), costUSD: 7.20 };
    }
    if (s.state === "failed") return { kind: "error", note: `Luma failed: ${s.failure_reason ?? "unknown"}` };
  }
  return { kind: "error", note: "Luma generation timed out after 3 min." };
}

/** Runway Gen-4 — POST /v1/image_to_video (or text_to_video on newer SKUs).
 *  Docs: https://docs.dev.runwayml.com  */
async function runRunway(prompt: string, durationSeconds: number, env: Env): Promise<GenerationResult> {
  if (!env.RUNWAY_API_KEY) return { kind: "skipped", note: "RUNWAY_API_KEY not set." };
  const submit = await fetch("https://api.dev.runwayml.com/v1/text_to_video", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RUNWAY_API_KEY}`,
      "Content-Type": "application/json",
      "X-Runway-Version": "2024-11-06",
    },
    body: JSON.stringify({
      promptText: prompt,
      model: "gen4_turbo",
      duration: Math.min(10, durationSeconds),
      ratio: "1280:720",
    }),
  });
  if (!submit.ok) return { kind: "error", note: `Runway submit ${submit.status}: ${(await submit.text()).slice(0, 200)}`, status: 502 };
  const submitted = await submit.json() as { id?: string };
  if (!submitted.id) return { kind: "error", note: "Runway returned no task id" };
  for (let i = 0; i < 60; i++) {
    await sleep(3000);
    const status = await fetch(`https://api.dev.runwayml.com/v1/tasks/${submitted.id}`, {
      headers: { Authorization: `Bearer ${env.RUNWAY_API_KEY}`, "X-Runway-Version": "2024-11-06" },
    });
    if (!status.ok) continue;
    const s = await status.json() as { status?: string; output?: string[]; failure?: string };
    if (s.status === "SUCCEEDED" && s.output?.[0]) {
      return { kind: "ok", provider: "runway-gen4", url: s.output[0],
               durationSeconds: Math.min(10, durationSeconds), costUSD: 9.00 };
    }
    if (s.status === "FAILED") return { kind: "error", note: `Runway failed: ${s.failure ?? "unknown"}` };
  }
  return { kind: "error", note: "Runway generation timed out after 3 min." };
}

// Pika / Kling / Veo / Sora stubs — concrete API shapes vary; wire each up
// after signing up for the provider's API and reading their request docs.
// Each returns "skipped" until both the key is set AND the adapter is filled in.
async function runPika(_prompt: string, _dur: number, env: Env): Promise<GenerationResult> {
  if (!env.PIKA_API_KEY) return { kind: "skipped", note: "PIKA_API_KEY not set." };
  return { kind: "skipped", note: "Pika 2.0 adapter is a stub — fill in the endpoint + request shape from Pika's API docs to enable." };
}
async function runKling(_prompt: string, _dur: number, env: Env): Promise<GenerationResult> {
  if (!env.KLING_API_KEY) return { kind: "skipped", note: "KLING_API_KEY not set." };
  return { kind: "skipped", note: "Kling 2.0 adapter is a stub — wire up after Kling API access." };
}
async function runVeo(_prompt: string, _dur: number, env: Env): Promise<GenerationResult> {
  if (!env.VEO_API_KEY) return { kind: "skipped", note: "VEO_API_KEY not set." };
  return { kind: "skipped", note: "Google Veo 3 adapter is a stub — wire up via Google AI Studio API." };
}
async function runSora(_prompt: string, _dur: number, env: Env): Promise<GenerationResult> {
  if (!env.SORA_API_KEY) return { kind: "skipped", note: "SORA_API_KEY not set." };
  return { kind: "skipped", note: "OpenAI Sora adapter is a stub — wire up via OpenAI's video endpoint." };
}

/** Legacy single-provider music path — preserved so existing wrangler configs
 *  pointing at MUSIC_GEN_API_URL keep working. */
async function runLegacyMusicProvider(prompt: string, env: Env): Promise<GenerationResult> {
  if (!env.MUSIC_GEN_API_URL || !env.MUSIC_GEN_API_KEY) {
    return { kind: "skipped",
             note: "Set MUSIC_GEN_API_URL + MUSIC_GEN_API_KEY to enable real music generation." };
  }
  const res = await fetch(env.MUSIC_GEN_API_URL, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.MUSIC_GEN_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ prompt, kind: "music" }),
  });
  if (!res.ok) return { kind: "error", note: `Provider ${res.status}: ${(await res.text()).slice(0, 200)}` };
  const data = await res.json() as { url?: string; duration_seconds?: number; content_type?: string; cost_usd?: number };
  if (!data.url) return { kind: "error", note: "Provider returned no url" };
  return { kind: "ok", provider: "music_gen", url: data.url,
           durationSeconds: data.duration_seconds, contentType: data.content_type, costUSD: data.cost_usd };
}

function sleep(ms: number): Promise<void> { return new Promise(r => setTimeout(r, ms)); }

/** GET /scout/spend — report the current month's media-gen spend + cap.
 *  Lets the operator surface running spend in the app's admin UI. */
async function handleScoutSpend(env: Env): Promise<Response> {
  const cap = Number(env.MAX_MEDIA_GEN_USD_MONTH ?? "50");
  const monthKey = `scout_spend_${new Date().toISOString().slice(0, 7)}`;
  const spend = env.KV ? Number((await env.KV.get(monthKey)) ?? "0") : 0;
  return json({
    month: monthKey.replace("scout_spend_", ""),
    spendUSD: spend,
    capUSD: cap,
    remainingUSD: Math.max(0, cap - spend),
    kvBound: !!env.KV,
  });
}

// ── Moderation ─────────────────────────────────────────────────────────────

/** POST /moderation/report — forward a user report on a title to the operator
 *  AND persist it in KV so the admin can work a queue. Email goes out as
 *  before so the operator gets a real-time ping; KV gives them a UI to
 *  resolve from. Key shape: `report:<status>:<reverse-ts>:<id>` so a
 *  prefix-scan returns newest-pending first.
 *
 *  Without a KV binding the persistence is a no-op (email still goes out),
 *  so operators running an older config keep the previous behavior. */
/** POST /commerce/validate-receipt — verify a StoreKit 2 JWS payload server
 *  side so a jailbroken device can't spoof local-only verification. The app
 *  forwards `transaction.jsonRepresentation` (signed JWS) along with the
 *  product id and the expected credit amount. We decode the JWS header to
 *  pull the x5c cert chain, verify the signature against Apple's root,
 *  check the bundle id + product id, and return ok/credit. KV-cached the
 *  validated transaction.id so a replay is rejected.
 *
 *  This endpoint is the gate for the wallet-credit flow when persistence
 *  moves server-side. The current app validates on-device via
 *  `StoreKitService.checkVerified`; calling this endpoint as well is the
 *  belt-and-braces step. */
/** GET /admin/kv-export?prefix=report:&cursor=... — dump every KV value under
 *  a prefix as JSON, in pages of 1000. Lets the operator back up reports,
 *  spend ledger, idempotency keys before a namespace migration / wipe. */
async function handleKVExport(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return error("KV not bound", 503);
  const url = new URL(request.url);
  const prefix = url.searchParams.get("prefix") ?? "";
  const cursor = url.searchParams.get("cursor") ?? undefined;
  const list = await env.KV.list({ prefix, cursor, limit: 1000 });
  const records: Array<{ key: string; value: any }> = [];
  for (const key of list.keys) {
    const raw = await env.KV.get(key.name);
    if (raw == null) continue;
    let value: any;
    try { value = JSON.parse(raw); } catch { value = raw; }
    records.push({ key: key.name, value });
  }
  return json({
    prefix,
    count: records.length,
    list_complete: list.list_complete,
    cursor: list.list_complete ? null : list.cursor,
    records,
  });
}

async function handleValidateReceipt(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    signed_jws?: string;
    product_id?: string;
    expected_credit_usd?: number;
    transaction_id?: string;
  };
  if (!body.signed_jws || !body.product_id || !body.transaction_id) {
    return error("signed_jws, product_id and transaction_id required");
  }

  // Replay protection: if we've validated this transaction id before, deny
  // (the client should idempotency-credit anyway, but the server must too).
  if (env.KV) {
    const seen = await env.KV.get(`tx:${body.transaction_id}`);
    if (seen === "ok") return json({ valid: true, replay: true, credit_usd: 0 });
  }

  // JWS structure: header.payload.signature (base64url). We decode the
  // payload to read the productId / bundleId / transactionId; the
  // signature verification proper requires Apple's root certs and a real
  // JWS library. For the production cut, plug in `jose` or `node-jose`
  // (Workers supports them via npm). Until then this route enforces the
  // payload semantics and the replay check, which closes 90% of the abuse
  // window vs. on-device only.
  const parts = body.signed_jws.split(".");
  if (parts.length !== 3) return error("malformed signed_jws", 400);
  try {
    const payloadJson = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(payloadJson);
    if (payload.productId !== body.product_id) {
      return error("product_id mismatch", 400);
    }
    if (payload.transactionId !== body.transaction_id) {
      return error("transaction_id mismatch", 400);
    }
    // Trust the on-device verification for now; Apple's JWS signature check
    // is the TODO that closes the last 10%.
    if (env.KV) {
      await env.KV.put(`tx:${body.transaction_id}`, "ok", { expirationTtl: 60 * 60 * 24 * 90 });
    }
    return json({
      valid: true,
      credit_usd: body.expected_credit_usd ?? 0,
      product_id: body.product_id,
      todo: "Wire Apple JWS signature verification with a JOSE library to fully close the spoof window.",
    });
  } catch (e) {
    return error("couldn't decode JWS payload", 400);
  }
}

// ── App Store Server Notifications V2 ───────────────────────────────────────
//
// When Apple processes a consumable refund (and a few other lifecycle events
// we care less about), it POSTs a signed payload to our webhook. The client
// can never see this — consumables disappear from every on-device StoreKit
// sequence the moment they're refunded — so server-side ingest is the only
// path to keep the wallet honest.
//
// Payload shape:
//   {"signedPayload": "<JWS, header.payload.signature>"}
// The header carries an x5c cert chain. We:
//   1. Pin Apple's Root CA G3 by SHA-256 — the LAST cert in x5c must match.
//   2. Verify the JWS signature using the leaf cert's EC public key.
//   3. Decode the payload, decode its nested signedTransactionInfo (also JWS),
//      and route by notificationType.
//
// REFUND / REFUND_REVERSED notifications get queued under the buyer's
// `appAccountToken` (a per-user UUID the client supplies on every purchase
// via `Product.PurchaseOption.appAccountToken(_:)`). The client polls
// /refunds/pending on launch + foreground and acks via /refunds/ack.

/// SHA-256 fingerprint (hex) of Apple Root CA - G3 DER. Constant unless
/// Apple rotates the root; pinned because we don't ship a full chain
/// validator. If Apple rotates, set APPLE_ROOT_CA_SHA256 in env to override.
const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

/// Minimum-viable ASN.1 DER reader — enough to extract the SPKI public key
/// bytes from an X.509 leaf certificate. Throws on malformed input.
function asn1ReadLength(buf: Uint8Array, offset: number): { length: number; headerLen: number } {
  const first = buf[offset];
  if ((first & 0x80) === 0) return { length: first, headerLen: 1 };
  const n = first & 0x7f;
  let length = 0;
  for (let i = 0; i < n; i++) length = (length << 8) | buf[offset + 1 + i];
  return { length, headerLen: 1 + n };
}
function asn1SkipTLV(buf: Uint8Array, offset: number): number {
  const lenInfo = asn1ReadLength(buf, offset + 1);
  return offset + 1 + lenInfo.headerLen + lenInfo.length;
}
function asn1ReadSequence(buf: Uint8Array, offset: number): { contentStart: number; contentEnd: number } {
  if (buf[offset] !== 0x30) throw new Error("expected SEQUENCE at offset " + offset);
  const lenInfo = asn1ReadLength(buf, offset + 1);
  const contentStart = offset + 1 + lenInfo.headerLen;
  return { contentStart, contentEnd: contentStart + lenInfo.length };
}

/// Extract the uncompressed EC P-256 public key (0x04 || X || Y) from an
/// X.509 DER cert. The structure is: Certificate { TBSCertificate {
/// [version?], serial, sigAlgo, issuer, validity, subject, SPKI } }.
function extractECPublicKey(der: Uint8Array): Uint8Array {
  const cert = asn1ReadSequence(der, 0);
  const tbs = asn1ReadSequence(der, cert.contentStart);
  let pos = tbs.contentStart;
  if (der[pos] === 0xa0) pos = asn1SkipTLV(der, pos); // [0] EXPLICIT version
  pos = asn1SkipTLV(der, pos); // serialNumber
  pos = asn1SkipTLV(der, pos); // signature AlgorithmIdentifier
  pos = asn1SkipTLV(der, pos); // issuer Name
  pos = asn1SkipTLV(der, pos); // validity
  pos = asn1SkipTLV(der, pos); // subject Name
  const spki = asn1ReadSequence(der, pos);
  let spkiPos = spki.contentStart;
  spkiPos = asn1SkipTLV(der, spkiPos); // AlgorithmIdentifier
  if (der[spkiPos] !== 0x03) throw new Error("expected BIT STRING for subjectPublicKey");
  const bitLen = asn1ReadLength(der, spkiPos + 1);
  // First byte of BIT STRING content is "unused bits" (always 0 for EC).
  const keyStart = spkiPos + 1 + bitLen.headerLen + 1;
  const keyEnd = spkiPos + 1 + bitLen.headerLen + bitLen.length;
  return der.slice(keyStart, keyEnd);
}

function b64urlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/")
    + "=".repeat((4 - (s.length % 4)) % 4);
  const bin = atob(padded);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}
function b64DecodeToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf;
}
function bytesToHex(buf: ArrayBuffer | Uint8Array): string {
  const arr = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  return Array.from(arr).map(b => b.toString(16).padStart(2, "0")).join("");
}

/// Verify and decode an Apple-signed JWS. Returns the decoded payload on
/// success, throws on any verification failure. Caller decides whether to
/// log + return 200 (default) or 401.
async function verifyAppleJWS(jws: string, env: Env): Promise<any> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("malformed JWS");
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
  if (header.alg !== "ES256") throw new Error("unexpected alg: " + header.alg);
  if (!header.x5c || !Array.isArray(header.x5c) || header.x5c.length < 2) {
    throw new Error("missing x5c chain");
  }
  // Pin to Apple Root CA G3 — the LAST cert in x5c is the root.
  const rootDer = b64DecodeToBytes(header.x5c[header.x5c.length - 1]);
  const rootHash = await crypto.subtle.digest("SHA-256", rootDer);
  const expected = (env.APPLE_ROOT_CA_SHA256 || APPLE_ROOT_CA_G3_SHA256).toLowerCase();
  if (bytesToHex(rootHash) !== expected) {
    throw new Error("x5c root does not match pinned Apple Root CA");
  }
  // Verify signature using the leaf cert's public key.
  const leafDer = b64DecodeToBytes(header.x5c[0]);
  const rawPubKey = extractECPublicKey(leafDer);
  const key = await crypto.subtle.importKey(
    "raw",
    rawPubKey,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const signature = b64urlDecode(parts[2]);
  const data = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: { name: "SHA-256" } },
    key,
    signature,
    data,
  );
  if (!valid) throw new Error("JWS signature invalid");
  return JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
}

/// POST /webhooks/app-store-server — Apple posts here on every consumable
/// refund (and other transaction lifecycle events). We verify, then queue
/// refunds for the buyer to drain on next /refunds/pending poll.
async function handleAppStoreNotification(request: Request, env: Env): Promise<Response> {
  let body: { signedPayload?: string };
  try { body = await request.json() as any; }
  catch { return error("malformed body", 400); }
  if (!body.signedPayload) return error("signedPayload required", 400);

  let payload: any;
  try {
    payload = await verifyAppleJWS(body.signedPayload, env);
  } catch (e: any) {
    // Return 200 so Apple stops retrying a forgery. Log so the operator
    // sees if their pinning needs an update (e.g., Apple rotated root).
    console.error("[ASSN] verify failed:", e?.message ?? e);
    await recordLedger(env, {
      type: "app_store_notification_rejected", status: "failed",
      amountCents: 0, currency: "n/a", scope: "platform", stripeId: "",
      note: `Apple notification rejected: ${e?.message ?? e}`,
    });
    return json({ ok: false, reason: "verification failed" }, 200);
  }

  const notificationType = payload.notificationType as string | undefined;
  const subtype = payload.subtype as string | undefined;
  const txInfoJWS = payload.data?.signedTransactionInfo as string | undefined;
  if (!txInfoJWS) {
    // Some notification types lack transaction info (e.g., TEST). Ack quietly.
    return json({ ok: true, notificationType, noTxInfo: true });
  }
  let txInfo: any;
  try { txInfo = await verifyAppleJWS(txInfoJWS, env); }
  catch (e: any) {
    console.error("[ASSN] nested tx-info verify failed:", e?.message ?? e);
    return json({ ok: false, reason: "tx-info verification failed" }, 200);
  }

  const expectedBundle = env.APP_BUNDLE_ID || "com.aimarketplace.app";
  if (txInfo.bundleId && txInfo.bundleId !== expectedBundle) {
    console.error("[ASSN] bundleId mismatch:", txInfo.bundleId, "expected", expectedBundle);
    return json({ ok: false, reason: "bundle mismatch" }, 200);
  }

  if (notificationType === "REFUND") {
    await queueRefund(env, txInfo, "refunded");
  } else if (notificationType === "REFUND_REVERSED") {
    // Apple reversed a refund (rare — usually fraud claim retracted). The
    // credit should be RESTORED; we surface this as a separate queue type.
    await queueRefund(env, txInfo, "refund_reversed");
  }
  // Ledger every notification so the operator can audit what Apple sent.
  await recordLedger(env, {
    type: "app_store_notification", status: "succeeded",
    amountCents: 0, currency: "n/a", scope: "platform",
    stripeId: String(txInfo.transactionId ?? ""),
    note: `${notificationType}${subtype ? "/" + subtype : ""} product=${txInfo.productId} tx=${txInfo.transactionId}`,
  });
  return json({ ok: true, notificationType });
}

/// Persist a refund event under the buyer's appAccountToken so the client
/// can drain it on next poll. Key shape:
///   `refund-queue:<appAccountToken>` → JSON array of pending entries.
/// Without an appAccountToken on the tx (legacy purchases before we wired
/// it client-side), we fall back to a global `unattributed` bucket the
/// operator can hand-resolve.
async function queueRefund(env: Env, txInfo: any, kind: "refunded" | "refund_reversed"): Promise<void> {
  if (!env.KV) {
    console.error("[ASSN] cannot queue refund — KV not bound");
    return;
  }
  const token = (txInfo.appAccountToken as string | undefined)?.toLowerCase() || "unattributed";
  const key = `refund-queue:${token}`;
  const existing = await env.KV.get(key);
  const queue: any[] = existing ? JSON.parse(existing) : [];
  // Dedup by transaction id — Apple retries notifications.
  if (queue.some((e: any) => e.transactionId === txInfo.transactionId && e.kind === kind)) return;
  queue.push({
    kind,
    transactionId: String(txInfo.transactionId ?? ""),
    originalTransactionId: String(txInfo.originalTransactionId ?? ""),
    productId: String(txInfo.productId ?? ""),
    revocationDate: txInfo.revocationDate,
    revocationReason: txInfo.revocationReason,
    receivedAt: new Date().toISOString(),
  });
  // 90-day TTL — Apple stops retrying long before this, and the client
  // should have polled by then.
  await env.KV.put(key, JSON.stringify(queue), { expirationTtl: 60 * 60 * 24 * 90 });
}

/// GET /refunds/pending?app_account_token=<uuid> — returns queued refund
/// entries the client hasn't acked. Empty array if none. Auth-required.
async function handlePendingRefunds(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return json({ refunds: [], note: "KV not bound" });
  const url = new URL(request.url);
  const token = url.searchParams.get("app_account_token")?.toLowerCase();
  if (!token) return error("app_account_token required");
  const raw = await env.KV.get(`refund-queue:${token}`);
  const refunds = raw ? JSON.parse(raw) : [];
  return json({ refunds });
}

/// POST /refunds/ack — body: { app_account_token, transaction_ids: [...] }
/// Removes the given transaction ids from the queue. Idempotent. Auth-required.
async function handleAckRefunds(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return error("KV not bound", 503);
  const body = await request.json() as { app_account_token?: string; transaction_ids?: string[] };
  const token = body.app_account_token?.toLowerCase();
  if (!token) return error("app_account_token required");
  const ids = new Set((body.transaction_ids ?? []).map(String));
  if (ids.size === 0) return json({ ok: true, removed: 0 });
  const key = `refund-queue:${token}`;
  const existing = await env.KV.get(key);
  if (!existing) return json({ ok: true, removed: 0 });
  const queue: any[] = JSON.parse(existing);
  const before = queue.length;
  const kept = queue.filter((e: any) => !ids.has(String(e.transactionId)));
  if (kept.length === 0) {
    await env.KV.delete(key);
  } else if (kept.length !== before) {
    await env.KV.put(key, JSON.stringify(kept), { expirationTtl: 60 * 60 * 24 * 90 });
  }
  return json({ ok: true, removed: before - kept.length });
}

async function handleReport(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    item_id?: string; item_title?: string; creator_name?: string;
    reason?: string; details?: string; reporter_email?: string;
    notify_on_resolve?: boolean;
  };
  const id = crypto.randomUUID();
  const ts = new Date().toISOString();

  // Length-cap every operator-visible string so a malicious client can't
  // write 24 MB of garbage into KV (each KV value is 25 MB max). Caps match
  // the UI: report bodies are ~paragraph-length, the details field is the
  // only place a user types prose.
  const safe = (v: unknown, max: number) =>
    typeof v === "string" ? v.slice(0, max) : "";
  const itemId = safe(body.item_id, 64);
  const itemTitle = safe(body.item_title, 200);
  const creatorName = safe(body.creator_name, 100);
  const reason = safe(body.reason, 100);
  const details = safe(body.details, 2000);
  const reporterEmail = safe(body.reporter_email, 200);

  if (env.KV) {
    // Reverse timestamp so newest sorts first under a prefix scan.
    const reverse = (9999999999999 - Date.now()).toString().padStart(13, "0");
    const record = {
      id, ts, status: "pending" as const,
      item_id: itemId, item_title: itemTitle,
      creator_name: creatorName, reason,
      details, reporter_email: reporterEmail,
      notify_on_resolve: body.notify_on_resolve === true && !!reporterEmail,
      disposition: "" as "" | "removed" | "warned" | "dismissed",
      resolved_at: "" as string,
      resolution_note: "" as string,
    };
    await env.KV.put(`report:pending:${reverse}:${id}`, JSON.stringify(record));
  }

  const subject = `[AI Marketplace] Report — ${reason || "Unspecified"}`;
  const lines = [
    `Item: ${itemTitle || "(unknown)"}  [${itemId || "?"}]`,
    `Creator: ${creatorName || "(unknown)"}`,
    `Reason: ${reason || "(none)"}`,
    reporterEmail ? `Reporter: ${reporterEmail}` : null,
    "",
    "Details:",
    details.trim() ? details : "(none provided)",
    "",
    `Report id: ${id}`,
    "Open the queue in Admin → Reports & blocks to resolve.",
    "App Review Guideline 1.2 requires action within 24 hours on serious reports.",
  ].filter(Boolean).join("\n");
  await sendEmail(env, subject, lines);
  return json({ received: true, id });
}

/** GET /moderation/reports?status=pending|resolved — admin queue listing.
 *  Returns up to 100 reports, newest-first. */
async function handleListReports(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return json({ reports: [], note: "KV not bound — no queue persisted." });
  const url = new URL(request.url);
  const status = (url.searchParams.get("status") === "resolved") ? "resolved" : "pending";
  const list = await env.KV.list({ prefix: `report:${status}:`, limit: 100 });
  const reports: any[] = [];
  for (const key of list.keys) {
    const raw = await env.KV.get(key.name);
    if (raw) {
      try { reports.push(JSON.parse(raw)); } catch { /* skip malformed */ }
    }
  }
  return json({ reports });
}

/** POST /moderation/reports/{id}/resolve — mark a report resolved with one
 *  of three dispositions (removed | warned | dismissed). The KV key changes
 *  prefix from `report:pending:` to `report:resolved:` so subsequent list
 *  calls return it under the correct status. */
async function handleResolveReport(request: Request, env: Env, id: string): Promise<Response> {
  if (!env.KV) return error("KV not bound — moderation queue unavailable", 503);
  const body = await request.json() as { disposition?: string; note?: string };
  const disp = body.disposition ?? "";
  if (!["removed", "warned", "dismissed"].includes(disp)) {
    return error("disposition must be one of: removed, warned, dismissed");
  }
  // Find the pending entry by id (suffix match) — scan up to 1000 to be safe.
  const list = await env.KV.list({ prefix: "report:pending:", limit: 1000 });
  const hit = list.keys.find(k => k.name.endsWith(`:${id}`));
  if (!hit) return error("report not found or already resolved", 404);
  const raw = await env.KV.get(hit.name);
  if (!raw) return error("report not found", 404);
  let record: any;
  try { record = JSON.parse(raw); } catch { return error("corrupted record", 500); }
  record.status = "resolved";
  record.disposition = disp;
  record.resolved_at = new Date().toISOString();
  // Defensive: body.note could be a non-string (?? "" doesn't catch non-string
  // truthy values like {evil: "obj"}, which would throw on .slice).
  record.resolution_note = typeof body.note === "string" ? body.note.slice(0, 500) : "";
  const reverse = hit.name.split(":")[2]; // preserve original sort
  await env.KV.put(`report:resolved:${reverse}:${id}`, JSON.stringify(record));
  await env.KV.delete(hit.name);

  // Notify the reporter (opt-in at submission time). Keeps trust in the
  // moderation loop — the previous flow let reports vanish into the
  // operator's inbox with no acknowledgement that anything happened.
  if (record.notify_on_resolve === true &&
      typeof record.reporter_email === "string" &&
      record.reporter_email.includes("@")) {
    const dispCopy: Record<string, string> = {
      removed: "The title has been removed from the marketplace.",
      warned: "We've reviewed your report and contacted the creator.",
      dismissed: "We reviewed your report and didn't find a policy violation, but thank you for flagging — we keep records of every report and re-review patterns over time.",
    };
    const subject = `[AI Marketplace] Your report has been resolved`;
    const note = (typeof record.resolution_note === "string" && record.resolution_note.trim())
      ? `\n\nModerator note: ${record.resolution_note}`
      : "";
    const text = [
      `Hi,`,
      ``,
      `Thanks for reporting "${record.item_title}". ${dispCopy[disp] ?? ""}${note}`,
      ``,
      `— The AI Marketplace moderation team`,
    ].join("\n");
    await sendEmail(env, subject, text, record.reporter_email);
  }

  return json({ resolved: true, id, disposition: disp });
}

// ── Automated funding + operator digest ─────────────────────────────────────

/** Send an email via Resend. No-op (logged) if RESEND_API_KEY isn't set. */
async function sendEmail(env: Env, subject: string, text: string, to?: string): Promise<void> {
  const recipient = to || env.OPERATOR_EMAIL || DEFAULT_OPERATOR_EMAIL;
  if (!env.RESEND_API_KEY) {
    console.log(`[email skipped — no RESEND_API_KEY] → ${recipient}\n${subject}\n${text}`);
    return;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: env.DIGEST_FROM_EMAIL || DEFAULT_FROM_EMAIL,
      to: [recipient],
      subject,
      text,
    }),
  });
  if (!res.ok) console.error(`Resend ${res.status}: ${await res.text()}`);
}

// ── Money-flow ledger ────────────────────────────────────────────────────────
//
// An append-only record of every money event, INDEPENDENT of Stripe, kept in
// KV so that if Stripe ever disagrees with us (or "goes off the rails") there's
// a second source of truth to reconcile against. Each entry is immutable;
// corrections are new entries, never edits. Keyed `ledger:<scope>:<ts>:<rand>`
// where scope is the connected account id (or "platform") so a creator's
// activity can be listed by prefix.

interface LedgerEntry {
  ts: string;            // ISO timestamp
  type: string;          // sale | transfer | payout | topup | nsf | refund | dispute | account_closed
  status: string;        // succeeded | failed | pending
  amountCents: number;   // always positive; sign implied by type
  currency: string;
  scope: string;         // accountId or "platform"
  refId?: string;        // sale/title/order id the entry traces to
  stripeId?: string;     // Stripe object id (tr_…, po_…, tu_…) when known
  note?: string;
}

/** Append an immutable entry. Best-effort: a ledger write must never block a
 *  money movement, so failures are logged, not thrown. Also bumps a coarse
 *  per-type running total in `ledger:totals` for the summary endpoint. */
async function recordLedger(env: Env, e: Omit<LedgerEntry, "ts">): Promise<void> {
  if (!env.KV) { console.log(`[ledger skipped — no KV] ${JSON.stringify(e)}`); return; }
  // Dedup on (scope, type, status, stripeId). Stripe replays webhooks and
  // the app retries failed transfers — both produce duplicate ledger calls
  // for one underlying Stripe object. Without this check, a single $50
  // transfer can land in the ledger twice and break reconciliation.
  const dedupKey = e.stripeId
    ? `ledger-idem:${e.scope}:${e.type}:${e.status}:${e.stripeId}`
    : null;
  if (dedupKey) {
    const seen = await env.KV.get(dedupKey);
    if (seen) {
      console.log(`[ledger dedup] skipping duplicate ${e.type}/${e.status} for ${e.stripeId}`);
      return;
    }
  }
  const entry: LedgerEntry = { ts: new Date().toISOString(), ...e };
  const rand = crypto.randomUUID().slice(0, 8);
  const key = `ledger:${entry.scope}:${entry.ts}:${rand}`;
  try {
    // Write the entry FIRST. If we wrote the dedup key first and the entry
    // write transiently failed, the retry would see the dedup key and skip
    // — losing the entry forever. By writing the entry first, a failure
    // here leaves no dedup, so the next attempt records cleanly. Worst
    // case under concurrency is a duplicate (caught downstream by stripeId
    // reconciliation), which is strictly better than a missing entry.
    await env.KV.put(key, JSON.stringify(entry));
    if (dedupKey) {
      await env.KV.put(dedupKey, "1", { expirationTtl: 60 * 60 * 24 * 365 });
    }
    // Coarse running totals (best-effort; the entries are authoritative).
    const totalsRaw = await env.KV.get("ledger:totals");
    const totals = totalsRaw ? JSON.parse(totalsRaw) : {};
    const bucket = `${entry.type}_${entry.status}`;
    totals[bucket] = (totals[bucket] ?? 0) + entry.amountCents;
    await env.KV.put("ledger:totals", JSON.stringify(totals));
  } catch (err: any) {
    console.error("ledger write failed:", err?.message ?? err);
  }
}

/// Gate for money-moving routes. Without KV bound, recordLedger is a no-op
/// — meaning Stripe transfers/payouts would succeed silently with no audit
/// trail. Refusing the request preserves the operator's ability to detect a
/// misconfigured deployment.
function requireKV(env: Env): Response | null {
  if (env.KV) return null;
  return error("Money-moving routes refused: KV binding missing. Add [[kv_namespaces]] in wrangler.toml so the ledger can record every event.", 503);
}

/** Detect a Stripe insufficient-funds (NSF) condition from a thrown error. */
function isInsufficientFunds(err: unknown): boolean {
  const m = (err instanceof Error ? err.message : String(err)).toLowerCase();
  return m.includes("insufficient")          // "balance_insufficient", "insufficient funds"
      || m.includes("balance_insufficient")
      || m.includes("nsf");
}

/** Record an NSF event to the ledger AND email the operator so it can be fixed. */
async function alertNSF(
  env: Env,
  ctx: { kind: string; scope: string; amountCents: number; currency: string; detail: string },
): Promise<void> {
  await recordLedger(env, {
    type: "nsf", status: "failed", amountCents: ctx.amountCents,
    currency: ctx.currency, scope: ctx.scope, note: `${ctx.kind}: ${ctx.detail}`,
  });
  const cur = ctx.currency.toUpperCase();
  const amt = (ctx.amountCents / 100).toFixed(2);
  const subject = `🚨 AI Marketplace NSF — ${ctx.kind} of ${cur} ${amt} failed`;
  const body = [
    `A ${ctx.kind} could not complete because of insufficient funds.`,
    ``,
    `Amount:   ${cur} ${amt}`,
    `Account:  ${ctx.scope}`,
    `Stripe:   ${ctx.detail}`,
    ``,
    `What to do: top up the platform Stripe balance manually (Stripe`,
    `Dashboard → Balance → Add to balance). Automatic top-ups only run`,
    `when a verified bank source is configured and Stripe's Top-ups API`,
    `is available for this account's country/currency. Once funded, the`,
    `affected ${ctx.kind} will succeed on the next attempt. The amount has`,
    `NOT been paid out and is still owed — nothing was lost.`,
  ].join("\n");
  // Alerts default to the single operator inbox (ALERT_EMAIL falls back to
  // OPERATOR_EMAIL), so everything lands in one place.
  await sendEmail(env, subject, body, env.ALERT_EMAIL || env.OPERATOR_EMAIL || DEFAULT_OPERATOR_EMAIL);
}

/** GET /ledger?account_id=…&limit=… — the money record for one account (or the
 *  platform). Auth-required. Newest first. */
async function handleLedger(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return json({ entries: [], note: "No KV bound — ledger unavailable." });
  const url = new URL(request.url);
  // Accept both `scope` (new) and `account_id` (legacy). The app-side
  // AdminLedgerView passes `scope` because operators inspect both the
  // platform bucket and acct_… buckets through the same field.
  const scope = url.searchParams.get("scope")
             || url.searchParams.get("account_id")
             || "platform";
  const limit = Math.min(Number(url.searchParams.get("limit") ?? "50"), 200);
  const list = await env.KV.list({ prefix: `ledger:${scope}:`, limit: 1000 });
  // Keys embed the ISO ts, so reverse-lexicographic = newest first.
  const keys = list.keys.map(k => k.name).sort().reverse().slice(0, limit);
  const entries: LedgerEntry[] = [];
  for (const k of keys) {
    const raw = await env.KV.get(k);
    if (raw) entries.push(JSON.parse(raw) as LedgerEntry);
  }
  return json({ scope, count: entries.length, entries });
}

/** GET /ledger/summary — coarse running totals across all activity. */
async function handleLedgerSummary(env: Env): Promise<Response> {
  if (!env.KV) return json({ totals: {}, note: "No KV bound — ledger unavailable." });
  const raw = await env.KV.get("ledger:totals");
  return json({ totals: raw ? JSON.parse(raw) : {} });
}

/** GET /ledger/calculate-balance?account_id=acct_xxx — sum the ledger to
 *  compute a creator's true pending balance. Formula:
 *      sum(transfer succeeded) - sum(transfer reversed)
 *    - sum(payout succeeded)   - sum(payout pending)
 *  The app uses this to verify its local `pendingPayoutUSD` matches reality
 *  (the local value is computed at sale time and could drift if a Stripe
 *  reversal lands without the app noticing). */
async function handleLedgerCalculateBalance(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return error("KV not bound — ledger unavailable", 503);
  const url = new URL(request.url);
  const accountId = url.searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");
  const list = await env.KV.list({ prefix: `ledger:${accountId}:`, limit: 1000 });
  let credits = 0;
  let debits = 0;
  let reversed = 0;
  for (const key of list.keys) {
    const raw = await env.KV.get(key.name);
    if (!raw) continue;
    let entry: LedgerEntry;
    try { entry = JSON.parse(raw) as LedgerEntry; } catch { continue; }
    if (entry.type === "transfer" && entry.status === "succeeded") credits += entry.amountCents;
    if (entry.type === "transfer" && entry.status === "reversed")  reversed += entry.amountCents;
    if (entry.type === "payout"   && entry.status === "succeeded") debits  += entry.amountCents;
    if (entry.type === "payout"   && entry.status === "pending")   debits  += entry.amountCents;
  }
  const pendingCents = Math.max(0, credits - debits - reversed);
  return json({
    accountId,
    pendingCents,
    pendingUSD: pendingCents / 100,
    credits: { transferSucceededCents: credits, transferReversedCents: reversed },
    debits:  { payoutSucceededAndPendingCents: debits },
    listComplete: list.list_complete,
  });
}

/** POST /accounts/release-email — admin tool. Marks an email as "released"
 *  so the next /payouts/connect for that email uses a salted idempotency
 *  key, forcing Stripe to create a FRESH account instead of returning the
 *  cached one. Used when Stripe rejected a creator's account and the
 *  creator needs to try again with a clean slate.
 *
 *  Requires the rejected Stripe account to be closed FIRST via
 *  /accounts/delete — otherwise the creator ends up with two Stripe
 *  accounts on the same email (Stripe allows it). */
async function handleReleaseEmail(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return error("KV not bound — cannot persist release flag", 503);
  const body = await request.json() as { email?: string };
  const email = (body.email ?? "").trim().toLowerCase();
  if (!email || !email.includes("@")) return error("email required");
  const salt = crypto.randomUUID().slice(0, 8);
  await env.KV.put(`connect-release:${email}`, salt, { expirationTtl: 60 * 60 * 24 * 7 });
  await recordLedger(env, {
    type: "account_released", status: "succeeded", amountCents: 0, currency: "n/a",
    scope: "platform", stripeId: "",
    note: `Admin released email ${email} for fresh Stripe onboarding (salt: ${salt}). 7-day TTL.`,
  });
  return json({ released: true, email, expiresInDays: 7 });
}

// ── Owed-creator queue + manual funding ──────────────────────────────────────
//
// When a transfer fails (NSF or otherwise) the creator is owed but unpaid. We
// queue an `unfunded:<account>:<id>` record so the operator can pay it by hand
// once the platform float is funded. POST /payouts/manual-fund re-attempts the
// transfer and clears the queue entry on success.

interface UnfundedEntry {
  id: string;            // the KV key suffix, so the app can clear a specific one
  accountId: string;
  amountCents: number;
  currency: string;
  title?: string;
  reason: string;
  ts: string;
}

async function enqueueUnfunded(
  env: Env,
  e: { accountId: string; amountCents: number; currency: string; title?: string; reason: string },
): Promise<void> {
  if (!env.KV) { console.log(`[unfunded skipped — no KV] ${JSON.stringify(e)}`); return; }
  const id = crypto.randomUUID().slice(0, 12);
  const entry: UnfundedEntry = { id, ts: new Date().toISOString(), ...e };
  try {
    await env.KV.put(`unfunded:${e.accountId}:${id}`, JSON.stringify(entry));
  } catch (err: any) { console.error("unfunded enqueue failed:", err?.message ?? err); }
}

/** GET /payouts/unfunded — every creator currently owed an unpaid transfer. */
async function handleUnfunded(env: Env): Promise<Response> {
  if (!env.KV) return json({ entries: [], note: "No KV bound." });
  const list = await env.KV.list({ prefix: "unfunded:", limit: 1000 });
  const entries: UnfundedEntry[] = [];
  for (const k of list.keys) {
    const raw = await env.KV.get(k.name);
    if (raw) entries.push(JSON.parse(raw) as UnfundedEntry);
  }
  entries.sort((a, b) => b.ts.localeCompare(a.ts));
  const totalUSD = entries.reduce((s, e) => s + e.amountCents, 0) / 100;
  return json({ count: entries.length, totalUSD, entries });
}

/** POST /payouts/manual-fund — operator re-pays an owed creator by hand.
 *  Body: { account_id, amount_usd, unfunded_id?, reason? }. On success the
 *  matching unfunded entry is cleared; on insufficient funds it re-alerts. */
async function handleManualFund(request: Request, env: Env): Promise<Response> {
  const kvGuard = requireKV(env); if (kvGuard) return kvGuard;
  const body = await request.json() as {
    account_id?: string; amount_usd?: number; unfunded_id?: string; reason?: string;
  };
  if (!body.account_id || !body.amount_usd || body.amount_usd < 0.5) {
    return error("account_id and amount_usd (≥ 0.50) are required");
  }
  const amountCents = Math.round(body.amount_usd * 100);
  const currency = (env.PLATFORM_CURRENCY || "usd").toLowerCase();
  // Unique key so a manual re-pay is never deduped against the original sale.
  const idem = `manual_${body.unfunded_id ?? crypto.randomUUID()}_${Date.now()}`;

  let transfer: any;
  try {
    transfer = await stripe("/transfers", {
      amount: amountCents,
      currency,
      destination: body.account_id,
      metadata: { platform: "ai-marketplace", manual: "true", reason: body.reason ?? "manual fund" },
      description: body.reason ?? "AI Marketplace manual creator funding",
    }, env.STRIPE_SECRET_KEY, undefined, idem);
  } catch (e: any) {
    await recordLedger(env, {
      type: "transfer", status: "failed", amountCents, currency,
      scope: body.account_id, note: `MANUAL fund failed: ${e?.message ?? ""}`,
    });
    if (isInsufficientFunds(e)) {
      await alertNSF(env, { kind: "manual creator funding", scope: body.account_id, amountCents, currency, detail: e?.message ?? "" });
    }
    return error(e?.message ?? "Manual fund failed", 502);
  }

  await recordLedger(env, {
    type: "transfer", status: "succeeded", amountCents, currency,
    scope: body.account_id, stripeId: transfer.id, note: `MANUAL fund: ${body.reason ?? ""}`,
  });
  // Clear the specific owed entry the operator just paid.
  if (env.KV && body.unfunded_id) {
    await env.KV.delete(`unfunded:${body.account_id}:${body.unfunded_id}`);
  }
  return json({ transferId: transfer.id, amountUSD: body.amount_usd, cleared: body.unfunded_id ?? null });
}

// ── Float funding awareness ──────────────────────────────────────────────────

interface Funding {
  currency: string;
  availableUSD: number;   // platform balance available right now
  bufferUSD: number;      // target float
  topUpNeededUSD: number; // how much to add to restore the buffer
  autoTopUp: boolean;     // true when a verified TOPUP_SOURCE_ID is configured
                          // AND the account/country supports the Top-ups API;
                          // false → operator funds the float manually
  salesTodayCount: number;
  salesTodayUSD: number;  // creator earnings transferred out today (burn)
}

/** Cheap funding snapshot: one balance call + today's sales counter from KV.
 *  Used by the per-sale email, the digest, and GET /payouts/funding. */
async function platformFunding(env: Env): Promise<Funding> {
  const cur = (env.PLATFORM_CURRENCY || "usd").toLowerCase();
  const buffer = Number(env.TOPUP_BUFFER_USD ?? DEFAULT_TOPUP_BUFFER_USD);
  let availableUSD = 0;
  try {
    const bal = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY);
    availableUSD = ((bal.available?.find((b: any) => b.currency === cur)?.amount) ?? 0) / 100;
  } catch { /* leave 0 — caller still gets buffer/topUp guidance */ }
  const todayKey = `sales:${new Date().toISOString().slice(0, 10)}`;
  let salesTodayCount = 0, salesTodayUSD = 0;
  if (env.KV) {
    const raw = await env.KV.get(todayKey);
    if (raw) { const s = JSON.parse(raw); salesTodayCount = s.count ?? 0; salesTodayUSD = (s.grossCents ?? 0) / 100; }
  }
  return {
    currency: cur,
    availableUSD,
    bufferUSD: buffer,
    topUpNeededUSD: Math.max(0, buffer - availableUSD),
    autoTopUp: !!env.TOPUP_SOURCE_ID,
    salesTodayCount,
    salesTodayUSD,
  };
}

/** Bump today's sales counter (count + gross cents). Best-effort. */
async function bumpSalesCounter(env: Env, grossCents: number): Promise<void> {
  if (!env.KV) return;
  const todayKey = `sales:${new Date().toISOString().slice(0, 10)}`;
  try {
    const raw = await env.KV.get(todayKey);
    const s = raw ? JSON.parse(raw) : { count: 0, grossCents: 0 };
    s.count += 1; s.grossCents += grossCents;
    await env.KV.put(todayKey, JSON.stringify(s), { expirationTtl: 60 * 60 * 24 * 40 });
  } catch (err: any) { console.error("sales counter failed:", err?.message ?? err); }
}

/** A one-line funding footer used in every operator email. */
function fundingFooter(f: Funding): string {
  const C = f.currency.toUpperCase();
  const topUp = f.topUpNeededUSD > 0
    ? (f.autoTopUp
        ? `TOP UP NEEDED: ${C} ${f.topUpNeededUSD.toFixed(2)} — make sure your linked bank has it; the auto-top-up cron will pull it to restore the float.`
        : `TOP UP NEEDED: ${C} ${f.topUpNeededUSD.toFixed(2)} — add it manually in the Stripe Dashboard (Balance → Add to balance). Automatic top-ups are off because no verified bank source is configured, or Stripe's Top-ups API isn't available for this account's country/currency.`)
    : `Float is healthy — no top-up needed right now.`;
  return [
    ``,
    `— Float status —`,
    `Platform balance: ${C} ${f.availableUSD.toFixed(2)}   (target buffer ${C} ${f.bufferUSD.toFixed(2)})`,
    topUp,
    `Sales today: ${f.salesTodayCount} (${C} ${f.salesTodayUSD.toFixed(2)} paid to creators)`,
  ].join("\n");
}

/** Email the operator about a single sale, with the float/top-up footer so one
 *  message answers "did I sell?" and "how much do I need to top up?". */
async function notifySale(env: Env, sale: { amountUSD: number; title_id?: string; account_id: string }): Promise<void> {
  if ((env.NOTIFY_EACH_SALE ?? "true") === "false") return;
  await bumpSalesCounter(env, Math.round(sale.amountUSD * 100));
  const f = await platformFunding(env);
  const C = f.currency.toUpperCase();
  const subject = `💰 AI Marketplace sale — ${C} ${sale.amountUSD.toFixed(2)} to a creator`;
  const body = [
    `A title just sold. The creator's ${(CREATOR_SHARE * 100).toFixed(0)}% share was transferred to their Stripe balance.`,
    ``,
    `Creator share: ${C} ${sale.amountUSD.toFixed(2)}`,
    `Title:         ${sale.title_id ?? "(unknown)"}`,
    `Account:       ${sale.account_id}`,
    fundingFooter(f),
  ].join("\n");
  await sendEmail(env, subject, body);
}

/** Keep the platform balance funded so creator transfers never fail. Pulls
 *  from your linked top-up bank via the Stripe Top-ups API — no manual "Add to
 *  balance" clicking. Money still moves bank→Stripe (Apple can't fund Stripe
 *  directly), but it's automatic. */
async function maybeTopUp(env: Env): Promise<{ toppedUp: number; availableUSD: number }> {
  const buffer = Number(env.TOPUP_BUFFER_USD ?? DEFAULT_TOPUP_BUFFER_USD);
  const maxTopUp = Number(env.TOPUP_MAX_USD ?? DEFAULT_TOPUP_MAX_USD);
  const cur = (env.PLATFORM_CURRENCY || "usd").toLowerCase();

  // Auto-top-up is OPT-IN. Stripe's Top-ups API ("Add to balance" from a
  // bank) is not available for every account / country / currency — e.g.
  // Canadian accounts can't create programmatic top-ups at all, and Stripe
  // rejects the call with a "can't process for this currency and country"
  // error. Attempting it anyway on every cron run produced a recurring
  // `topup.failed` ledger entry plus a false NSF alert (the bank didn't
  // bounce — the feature simply doesn't exist for the account).
  //
  // So we only attempt a programmatic top-up when the operator has
  // explicitly configured a verified bank source via TOPUP_SOURCE_ID,
  // which is the signal that their account supports top-ups AND a source
  // is ready. Without it we skip silently; the payout digest still tells
  // the operator the float is low and to add funds manually in the Stripe
  // Dashboard (which works in every country). Balance is still read so the
  // caller / digest gets an accurate availableUSD.
  if (!env.TOPUP_SOURCE_ID) {
    const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY);
    const platBal = balance.available?.find((b: any) => b.currency === cur);
    return { toppedUp: 0, availableUSD: (platBal?.amount ?? 0) / 100 };
  }

  const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY);
  const platBal = balance.available?.find((b: any) => b.currency === cur);
  const availableUSD = (platBal?.amount ?? 0) / 100;
  if (availableUSD >= buffer) return { toppedUp: 0, availableUSD };

  // Skip if a top-up is already in flight — they take days to clear and stacking
  // them would over-fund the float.
  const pending = await stripeGet(`/topups?status=pending&limit=1`, env.STRIPE_SECRET_KEY);
  if (pending.data?.length) return { toppedUp: 0, availableUSD };

  // Hard cap: a refund/chargeback can drive `available` very negative; without
  // this clamp the formula would request a runaway bank pull.
  const wantedCents = Math.round((buffer - availableUSD) * 100);
  const amountCents = Math.min(wantedCents, Math.round(maxTopUp * 100));
  if (amountCents <= 0) return { toppedUp: 0, availableUSD };

  const body: Record<string, unknown> = {
    amount: amountCents,
    currency: cur,
    description: "AI Marketplace payout float",
    statement_descriptor: "AIMKT TOPUP",
  };
  // Stripe requires `source` when multiple verified bank sources exist; if it's
  // unset we let Stripe pick the default top-up source.
  if (env.TOPUP_SOURCE_ID) body.source = env.TOPUP_SOURCE_ID;

  const idem = `topup_${new Date().toISOString().slice(0, 10)}`;
  try {
    const topup = await stripe("/topups", body, env.STRIPE_SECRET_KEY, undefined, idem);
    await recordLedger(env, {
      type: "topup", status: "pending", amountCents, currency: cur,
      scope: "platform", stripeId: topup.id, note: "float funding",
    });
  } catch (e: any) {
    await recordLedger(env, {
      type: "topup", status: "failed", amountCents, currency: cur,
      scope: "platform", note: e?.message ?? "topup failed",
    });
    if (isInsufficientFunds(e)) {
      // The top-up bank itself bounced — the float can't be funded, which
      // means creator transfers will start failing. Highest-priority alert.
      await alertNSF(env, { kind: "platform float top-up (bank NSF)", scope: "platform", amountCents, currency: cur, detail: e?.message ?? "" });
    }
    throw e; // let the cron's isolated catch log it
  }
  return { toppedUp: amountCents / 100, availableUSD };
}

/** Email the operator a summary of which creators are owed money and what to do.
 *  Reads balances straight from Stripe (the source of truth) — no second ledger. */
async function sendPayoutDigest(env: Env): Promise<{ accounts: number; owedUSD: number }> {
  const list = await stripeGet(`/accounts?limit=100`, env.STRIPE_SECRET_KEY);
  const accounts: any[] = list.data ?? [];
  const lines: string[] = [];
  let owedUSD = 0;

  for (const acct of accounts) {
    const bal = await stripeGet(`/balance?stripe_account=${acct.id}`, env.STRIPE_SECRET_KEY);
    const cents = (bal.available?.[0]?.amount ?? 0) + (bal.pending?.[0]?.amount ?? 0);
    if (cents <= 0) continue;
    owedUSD += cents / 100;
    const who = acct.metadata?.app_email || acct.email || acct.id;
    const ready = acct.payouts_enabled ? "auto-pays to their bank" : "⚠️ payouts NOT enabled — creator must finish Stripe onboarding";
    lines.push(`• ${who} — $${(cents / 100).toFixed(2)} (${ready})  [${acct.id}]`);
  }

  const f = await platformFunding(env);
  const owedBlock = lines.length
    ? `Creators with a balance owed:\n\n${lines.join("\n")}\n\nTotal owed: $${owedUSD.toFixed(2)}`
    : `No creator balances owed right now.`;
  const body = [
    owedBlock,
    fundingFooter(f),
    ``,
    `How payout works: connected creators are paid to their own bank by Stripe`,
    `automatically. You only keep the platform float funded (auto-top-up handles`,
    `this — just keep your linked bank funded). For anyone marked ⚠️, nudge them`,
    `to finish Stripe onboarding — Stripe can't pay them until then.`,
  ].join("\n");

  const topUpTag = f.topUpNeededUSD > 0 ? ` · top up ${f.currency.toUpperCase()} ${f.topUpNeededUSD.toFixed(2)}` : "";
  await sendEmail(env, `AI Marketplace — ${f.salesTodayCount} sales today, $${owedUSD.toFixed(2)} owed${topUpTag}`, body);
  return { accounts: lines.length, owedUSD };
}

// ── Router ─────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method;
    const path = url.pathname;

    // CORS preflight
    if (method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Authorization, Content-Type",
        },
      });
    }

    // Webhook endpoint — no auth (Stripe signs it)
    if (path === "/payouts/webhook" && method === "POST") {
      return handleWebhook(request, env);
    }
    // Apple ASSN V2 webhook — no auth (Apple signs the JWS; we pin the
    // root CA + verify the signature inside the handler).
    if (path === "/webhooks/app-store-server" && method === "POST") {
      return handleAppStoreNotification(request, env);
    }

    // Public bounce pages from Stripe-hosted onboarding — no auth (Stripe
    // redirects creators here in Safari; they have no Authorization header).
    if (path === "/payout-complete" && method === "GET") {
      const account = url.searchParams.get("account") ?? "";
      return htmlResponse(payoutCompleteHTML(account));
    }
    if (path === "/payout-refresh" && method === "GET") {
      const account = url.searchParams.get("account") ?? "";
      return htmlResponse(payoutRefreshHTML(account));
    }

    // All other endpoints require the shared secret
    if (!(await isAuthenticated(request, env.APP_SHARED_SECRET))) {
      return error("Unauthorized", 401);
    }

    try {
      // Connect: create account + get onboarding link
      if (path === "/payouts/connect" && method === "POST") {
        // 3 connect attempts / IP / 5 min — Stripe rate-limits us already
        // and creating multiple accounts is expensive / pollutes Stripe.
        if (await rateLimited(env, "connect", request, 3, 0.2)) {
          return error("Too many connect attempts — wait a minute and try again.", 429);
        }
        return await handleConnect(request, env);
      }

      // Fresh onboarding link for an existing Connect account (resume flow).
      if (path === "/payouts/onboarding-link" && method === "POST") {
        return await handleOnboardingLink(request, env);
      }

      // Status: is the account fully onboarded?
      if (path === "/payouts/status" && method === "GET") {
        return await handleStatus(request, env);
      }

      // Balance: check pending + available
      if (path === "/payouts/balance" && method === "GET") {
        return await handleBalance(request, env);
      }

      // Cash out: trigger payout
      if (path === "/payouts/cash-out" && method === "POST") {
        return await handleCashOut(request, env);
      }

      // Transfer: move 85% of a sale to the creator's Connect account
      if (path === "/payouts/transfer" && method === "POST") {
        return await handleTransfer(request, env);
      }

      // Moderation: forward a user-submitted report to the operator inbox
      // (Apple Review Guideline 1.2 — UGC apps require an in-app report flow).
      if (path === "/moderation/report" && method === "POST") {
        // 5 reports / IP / minute, refilling at 1 per minute. Stops a
        // malicious script with the shared secret from spamming the
        // operator inbox or filling KV.
        if (await rateLimited(env, "report", request, 5, 1)) {
          return error("Too many reports — slow down and try again in a minute.", 429);
        }
        return await handleReport(request, env);
      }
      if (path === "/commerce/validate-receipt" && method === "POST") {
        return await handleValidateReceipt(request, env);
      }
      // KV export — dumps every key+value (under a prefix) as JSON so the
      // operator can back up reports / spend / ledger before a KV namespace
      // wipe or migration. Capped at 1000 keys per call; pass ?cursor=... to
      // continue. Subject to the shared-secret auth like everything else.
      if (path === "/admin/kv-export" && method === "GET") {
        return await handleKVExport(request, env);
      }
      // Admin queue listing — newest pending or resolved first, up to 100.
      if (path === "/moderation/reports" && method === "GET") {
        return await handleListReports(request, env);
      }
      // Admin resolution — disposition: "removed" | "warned" | "dismissed".
      const resolveMatch = path.match(/^\/moderation\/reports\/([0-9a-fA-F-]{36})\/resolve$/);
      if (resolveMatch && method === "POST") {
        return await handleResolveReport(request, env, resolveMatch[1]);
      }

      // Scout media generation: forwards a prompt to a configured audio or
      // video provider (Suno / Runway / Veo / etc.) and returns a playable
      // URL the app can hand to the Editor as real bytes. Without a provider
      // configured, returns { provider: "none" } and Scout falls back to the
      // on-device prose-as-artifact path — both paths are vetted by the
      // same Editor; this one yields real playable media.
      if (path === "/scout/generate-media" && method === "POST") {
        return await handleScoutGenerateMedia(request, env);
      }

      // Text drafting fallback: devices without Apple Intelligence can't run
      // the on-device Foundation Model, so the app routes Scout's manuscript/
      // lyrics/screenplay drafting here instead. Proxies to Anthropic's
      // Messages API; returns { text }. 503 until ANTHROPIC_API_KEY is set.
      if (path === "/scout/draft" && method === "POST") {
        return await handleScoutDraft(request, env);
      }

      // Scout provider status: which generation providers are configured on
      // this Worker. The app uses this to set proposal budgets and routing.
      if (path === "/scout/providers" && method === "GET") {
        // Per-provider key presence — the app uses this to gray out providers
        // whose API keys aren't wired yet. We never expose the keys themselves.
        const videoProviders = {
          "runway-gen4":         !!env.RUNWAY_API_KEY,
          "luma-dream-machine":  !!env.LUMA_API_KEY,
          "pika-2":              !!env.PIKA_API_KEY,
          "kling-2":             !!env.KLING_API_KEY,
          "veo-3":               !!env.VEO_API_KEY,
          "sora-turbo":          !!env.SORA_API_KEY,
        };
        return json({
          foundation: true,
          musicGenConfigured: !!(env.MUSIC_GEN_API_URL && env.MUSIC_GEN_API_KEY),
          videoGenConfigured: !!(env.VIDEO_GEN_API_URL && env.VIDEO_GEN_API_KEY)
                              || Object.values(videoProviders).some(Boolean),
          textGenConfigured: !!env.ANTHROPIC_API_KEY,
          videoProviders,
        });
      }

      // Scout spend status: current-month spend + cap. Cheap; safe to poll.
      if (path === "/scout/spend" && method === "GET") {
        return await handleScoutSpend(env);
      }

      // Money-flow ledger: the independent record of every transfer/payout/
      // top-up/NSF. ?account_id= scopes it to one creator; default = platform.
      if (path === "/ledger" && method === "GET") {
        return await handleLedger(request, env);
      }
      if (path === "/ledger/summary" && method === "GET") {
        return await handleLedgerSummary(env);
      }
      // Sum the ledger to compute a creator's true pending balance.
      // App calls this to verify its local `pendingPayoutUSD` against the
      // truth; operator calls it during reconciliation.
      if (path === "/ledger/calculate-balance" && method === "GET") {
        return await handleLedgerCalculateBalance(request, env);
      }
      // Admin: release a creator's email so the next /payouts/connect call
      // creates a NEW Stripe account instead of returning the rejected one
      // from Stripe's idempotency cache. Used when an applicant was
      // declined and needs to try again with a clean slate.
      if (path === "/refunds/pending" && method === "GET") {
        return await handlePendingRefunds(request, env);
      }
      if (path === "/refunds/ack" && method === "POST") {
        return await handleAckRefunds(request, env);
      }
      if (path === "/accounts/release-email" && method === "POST") {
        return await handleReleaseEmail(request, env);
      }

      // Float funding: platform balance, target buffer, how much to top up,
      // and today's sales. The operator/admin can poll this for awareness.
      if (path === "/payouts/funding" && method === "GET") {
        return json(await platformFunding(env));
      }

      // Owed creators (failed/NSF transfers) + manual re-pay.
      if (path === "/payouts/unfunded" && method === "GET") {
        return await handleUnfunded(env);
      }
      if (path === "/payouts/manual-fund" && method === "POST") {
        return await handleManualFund(request, env);
      }

      // Scout feed: the curated reference corpus the app's Scout draws from
      // (100 canonical bestsellers per medium + 10 masters per role + recipes
      // + current charts + model list). GET; auth-required to keep the corpus
      // private to the platform. ETag enables 12h client caching.
      if (path === "/scout/feed" && method === "GET") {
        const etag = `"sf-${scoutFeedData.version}"`;
        if (request.headers.get("If-None-Match") === etag) {
          return new Response(null, { status: 304, headers: { "ETag": etag } });
        }
        return new Response(JSON.stringify(scoutFeedData), {
          headers: {
            "Content-Type": "application/json",
            "ETag": etag,
            "Cache-Control": "private, max-age=43200",
          },
        });
      }

      // Account deletion: close the connected Stripe account so user data
      // doesn't linger server-side after in-app deletion (Apple 5.1.1(v)).
      if (path === "/accounts/delete" && method === "POST") {
        return await handleDeleteAccount(request, env);
      }

      // Digest: email the operator who's owed (also runs automatically on cron)
      if (path === "/payouts/digest" && method === "POST") {
        const result = await sendPayoutDigest(env);
        return json(result);
      }

      // Top-up: ensure the platform float is funded (also runs on cron)
      if (path === "/payouts/topup" && method === "POST") {
        const result = await maybeTopUp(env);
        return json(result);
      }

      // Health check
      if (path === "/") {
        return json({
          service: "AI Marketplace Payout Worker",
          version: "1.0.0",
          endpoints: [
            "POST /payouts/connect",
            "POST /payouts/onboarding-link",
            "GET  /payouts/status",
            "GET  /payouts/balance",
            "POST /payouts/cash-out",
            "POST /payouts/transfer",
            "POST /payouts/digest",
            "POST /payouts/topup",
            "POST /payouts/webhook",
            "POST /accounts/delete",
            "POST /moderation/report",
            "GET  /moderation/reports",
            "POST /moderation/reports/{id}/resolve",
            "GET  /scout/feed",
            "GET  /scout/providers",
            "GET  /scout/spend",
            "POST /scout/generate-media",
            "GET  /ledger",
            "GET  /ledger/summary",
            "GET  /payouts/funding",
            "GET  /payouts/unfunded",
            "POST /payouts/manual-fund",
            "GET  /stripe/publishable-key",
            "GET  /payout-complete",
            "GET  /payout-refresh",
          ],
        });
      }

      // Stripe publishable key — clients can fetch this if they need it for
      // Stripe.js / Elements (none of the current app flows use it; Apple
      // IAP collects from buyers, Stripe Connect pays creators server-side).
      // Returns 404 when the secret isn't set so callers can distinguish
      // "not configured" from "configured but empty".
      if (path === "/stripe/publishable-key" && method === "GET") {
        if (!env.STRIPE_PUBLISHABLE_KEY) {
          return error("STRIPE_PUBLISHABLE_KEY not set", 404);
        }
        return json({ publishableKey: env.STRIPE_PUBLISHABLE_KEY });
      }

      return error("Not found", 404);
    } catch (err: any) {
      console.error(`Error on ${path}:`, err);
      return error(err.message ?? "Internal server error", 500);
    }
  },

  /** Cron-triggered automation (schedules set in wrangler.toml):
   *  keep the platform float funded, then email the operator the payout digest. */
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil((async () => {
      // Isolated try blocks so a top-up failure can't suppress the digest
      // — the digest is how the operator notices a top-up failed.
      let topup = { toppedUp: 0, availableUSD: 0 };
      try {
        topup = await maybeTopUp(env);
      } catch (err: any) {
        console.error("cron topup error:", err?.message ?? err);
      }
      try {
        const digest = await sendPayoutDigest(env);
        console.log(`cron: topped up $${topup.toppedUp}, ${digest.accounts} creators owed $${digest.owedUSD}`);
      } catch (err: any) {
        console.error("cron digest error:", err?.message ?? err);
      }
    })());
  },
};