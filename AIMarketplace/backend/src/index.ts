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
  RESEND_API_KEY?: string;     // for the operator payout-digest email
  OPERATOR_EMAIL?: string;     // where digests go (defaults below)
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
  VIDEO_GEN_API_URL?: string;  // e.g. Runway / Veo / Sora API
  VIDEO_GEN_API_KEY?: string;
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
  const json = await res.json();
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${json.error?.message ?? JSON.stringify(json)}`);
  return json;
}

/** Call Stripe GET */
async function stripeGet(path: string, secret: string): Promise<any> {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    headers: { Authorization: `Bearer ${secret}` },
  });
  const json = await res.json();
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
  const { accountName, accountEmail } = body;

  if (!accountName || !accountEmail) {
    return error("accountName and accountEmail are required");
  }

  // Step 1: Create the Connect Express account
  const account = await stripe("/accounts", {
    type: env.STRIPE_CONNECT_TYPE || "express",
    country: "US",
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
  }, env.STRIPE_SECRET_KEY, undefined, `connect_${accountEmail}`);

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

  return json({
    accountId: account.id,
    chargesEnabled: account.charges_enabled,
    payoutsEnabled: account.payouts_enabled,
    detailsSubmitted: account.details_submitted,
    capabilities: account.capabilities,
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
  const payout = await stripe("/payouts", {
    amount: payoutAmount,
    currency: "usd",
    metadata: {
      platform: "ai-marketplace",
    },
  }, env.STRIPE_SECRET_KEY, account_id);

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

  const transfer = await stripe("/transfers", {
    amount: Math.round(amount_usd * 100),
    currency: "usd",
    destination: account_id,
    metadata: {
      platform: "ai-marketplace",
      title_id: title_id ?? "",
      creator_share: String(CREATOR_SHARE),
    },
    description: memo ?? "AI Marketplace creator earnings",
  }, env.STRIPE_SECRET_KEY, undefined, idem);

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
      console.log(`Payout ${payout.id} paid: $${payout.amount / 100}`);
      break;
    }
    case "payout.failed": {
      const payout = event.data.object;
      console.error(`Payout ${payout.id} FAILED: $${payout.amount / 100}`);
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
  };
  if (body.type !== "music" && body.type !== "movie") {
    return error("type must be 'music' or 'movie'");
  }
  const providerURL = body.type === "music" ? env.MUSIC_GEN_API_URL : env.VIDEO_GEN_API_URL;
  const providerKey = body.type === "music" ? env.MUSIC_GEN_API_KEY : env.VIDEO_GEN_API_KEY;
  if (!providerURL || !providerKey) {
    return json({
      provider: "none",
      note: `Set ${body.type === "music" ? "MUSIC_GEN_API_URL + MUSIC_GEN_API_KEY" : "VIDEO_GEN_API_URL + VIDEO_GEN_API_KEY"} to enable real ${body.type} generation. Scout will use the on-device prose-as-artifact path until then.`,
    });
  }

  // Spend cap check BEFORE the provider call.
  const cap = Number(env.MAX_MEDIA_GEN_USD_MONTH ?? "50");
  const monthKey = `scout_spend_${new Date().toISOString().slice(0, 7)}`;
  const currentSpend = env.KV ? Number((await env.KV.get(monthKey)) ?? "0") : 0;
  const estimatedCost = Number(
    body.type === "music" ? (env.MUSIC_GEN_COST_USD ?? "0.15") : (env.VIDEO_GEN_COST_USD ?? "0.60")
  );
  if (currentSpend + estimatedCost > cap) {
    return json({
      provider: "rate_limited",
      currentSpendUSD: currentSpend,
      capUSD: cap,
      note: `Per-month spend cap (\$${cap}) would be exceeded; running total this month is \$${currentSpend.toFixed(2)}. Raise MAX_MEDIA_GEN_USD_MONTH or wait until next month.`,
    }, 402);
  }
  if (!env.KV) {
    // Strict: without KV we can't track spend, so we refuse. Operator must
    // bind a KV namespace before enabling paid generation.
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
    const res = await fetch(providerURL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${providerKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prompt, kind: body.type }),
    });
    if (!res.ok) {
      return error(`Provider ${res.status}: ${(await res.text()).slice(0, 200)}`, 502);
    }
    const data = await res.json() as { url?: string; duration_seconds?: number; content_type?: string; cost_usd?: number };
    if (!data.url) return error("Provider returned no url", 502);

    // Record the spend. Prefer the provider's reported cost; fall back to
    // the env estimate. Tracked per-month in KV so the cap is enforceable.
    const realCost = typeof data.cost_usd === "number" ? data.cost_usd : estimatedCost;
    await env.KV.put(monthKey, String(currentSpend + realCost));

    return json({
      provider: body.type === "music" ? "music_gen" : "video_gen",
      url: data.url,
      durationSeconds: data.duration_seconds,
      contentType: data.content_type,
      costUSD: realCost,
      monthSpendUSD: currentSpend + realCost,
      monthCapUSD: cap,
    });
  } catch (err: any) {
    return error(`Generation failed: ${err?.message ?? err}`, 502);
  }
}

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

/** POST /moderation/report — forward a user report on a title to the operator.
 *  No PII beyond what the reporter typed; the body is plain text. */
async function handleReport(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    item_id?: string; item_title?: string; creator_name?: string;
    reason?: string; details?: string; reporter_email?: string;
  };
  const subject = `[AI Marketplace] Report — ${body.reason ?? "Unspecified"}`;
  const lines = [
    `Item: ${body.item_title ?? "(unknown)"}  [${body.item_id ?? "?"}]`,
    `Creator: ${body.creator_name ?? "(unknown)"}`,
    `Reason: ${body.reason ?? "(none)"}`,
    body.reporter_email ? `Reporter: ${body.reporter_email}` : null,
    "",
    "Details:",
    (body.details && body.details.trim().length) ? body.details : "(none provided)",
    "",
    "App Review Guideline 1.2 requires action within 24 hours on serious reports.",
  ].filter(Boolean).join("\n");
  await sendEmail(env, subject, lines);
  return json({ received: true });
}

// ── Automated funding + operator digest ─────────────────────────────────────

/** Send an email via Resend. No-op (logged) if RESEND_API_KEY isn't set. */
async function sendEmail(env: Env, subject: string, text: string): Promise<void> {
  if (!env.RESEND_API_KEY) {
    console.log(`[email skipped — no RESEND_API_KEY]\n${subject}\n${text}`);
    return;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: env.DIGEST_FROM_EMAIL || DEFAULT_FROM_EMAIL,
      to: [env.OPERATOR_EMAIL || DEFAULT_OPERATOR_EMAIL],
      subject,
      text,
    }),
  });
  if (!res.ok) console.error(`Resend ${res.status}: ${await res.text()}`);
}

/** Keep the platform balance funded so creator transfers never fail. Pulls
 *  from your linked top-up bank via the Stripe Top-ups API — no manual "Add to
 *  balance" clicking. Money still moves bank→Stripe (Apple can't fund Stripe
 *  directly), but it's automatic. */
async function maybeTopUp(env: Env): Promise<{ toppedUp: number; availableUSD: number }> {
  const buffer = Number(env.TOPUP_BUFFER_USD ?? DEFAULT_TOPUP_BUFFER_USD);
  const maxTopUp = Number(env.TOPUP_MAX_USD ?? DEFAULT_TOPUP_MAX_USD);
  const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY);
  const usd = balance.available?.find((b: any) => b.currency === "usd");
  const availableUSD = (usd?.amount ?? 0) / 100;
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
    currency: "usd",
    description: "AI Marketplace payout float",
    statement_descriptor: "AIMKT TOPUP",
  };
  // Stripe requires `source` when multiple verified bank sources exist; if it's
  // unset we let Stripe pick the default top-up source.
  if (env.TOPUP_SOURCE_ID) body.source = env.TOPUP_SOURCE_ID;

  const idem = `topup_${new Date().toISOString().slice(0, 10)}`;
  await stripe("/topups", body, env.STRIPE_SECRET_KEY, undefined, idem);
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

  const body = lines.length
    ? `Creators with a balance owed:\n\n${lines.join("\n")}\n\n` +
      `Total owed: $${owedUSD.toFixed(2)}\n\n` +
      `How payout works: connected creators are paid to their own bank by Stripe automatically. ` +
      `You only keep the platform float funded (auto-top-up handles this). ` +
      `For anyone marked ⚠️, nudge them to finish Stripe onboarding — Stripe can't pay them until then.`
    : `No creator balances owed right now.`;

  await sendEmail(env, `AI Marketplace payouts — $${owedUSD.toFixed(2)} owed across ${lines.length} creator(s)`, body);
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
        return await handleReport(request, env);
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

      // Scout provider status: which generation providers are configured on
      // this Worker. The app uses this to set proposal budgets and routing.
      if (path === "/scout/providers" && method === "GET") {
        return json({
          foundation: true,
          musicGenConfigured: !!(env.MUSIC_GEN_API_URL && env.MUSIC_GEN_API_KEY),
          videoGenConfigured: !!(env.VIDEO_GEN_API_URL && env.VIDEO_GEN_API_KEY),
        });
      }

      // Scout spend status: current-month spend + cap. Cheap; safe to poll.
      if (path === "/scout/spend" && method === "GET") {
        return await handleScoutSpend(env);
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
            "GET  /payouts/status",
            "GET  /payouts/balance",
            "POST /payouts/cash-out",
            "POST /payouts/transfer",
            "POST /payouts/digest",
            "POST /payouts/topup",
            "POST /payouts/webhook",
          ],
        });
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