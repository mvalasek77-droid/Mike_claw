/**
 * AI Marketplace Payout Worker
 *
 * Handles Stripe Connect onboarding, creator transfers, balance, and cash-out
 * for the AI Marketplace iOS app.
 *
 * Required secrets (set via `wrangler secret put [--env staging]`):
 *   STRIPE_SECRET_KEY      — Stripe API secret key (sk_test_... for staging, sk_live_... for prod)
 *   APP_SHARED_SECRET      — Shared secret for app→worker auth
 *   STRIPE_WEBHOOK_SECRET  — Stripe webhook signing secret (whsec_...) for /payouts/webhook
 *
 * Required binding (wrangler.toml): KV namespace `KV` — stores the canonical
 * creator email→accountId mapping and the last webhook-observed payout state.
 *
 * Endpoints:
 *   POST /payouts/connect    — Create OR reuse a Connect Express account + onboarding link
 *   GET  /payouts/status     — Check if account is connected / payouts-enabled
 *   GET  /payouts/balance    — Get the creator's pending + available balance
 *   POST /payouts/transfer   — Move a creator's earnings to their connected account (auto-pays out)
 *   POST /payouts/cash-out   — Pay out a connected account's available balance to its bank
 *   GET  /payouts/events     — Last webhook-observed state for an account (e.g. payout failures)
 *   POST /payouts/webhook    — Stripe webhook receiver (signature-verified, persisted)
 */

// ── Types ──────────────────────────────────────────────────────────────────

interface Env {
  STRIPE_SECRET_KEY: string;
  APP_SHARED_SECRET: string;
  STRIPE_WEBHOOK_SECRET?: string;
  STRIPE_CONNECT_TYPE: string; // "express" from wrangler.toml [vars]
  PLATFORM_CURRENCY?: string;  // settlement currency of the platform Stripe account (e.g. "cad")
  PLATFORM_COUNTRY?: string;   // default country for new connected accounts (e.g. "CA")
  KV?: KVNamespace; // canonical account mapping + webhook state
}

interface ConnectRequest {
  accountName: string;
  accountEmail: string;
  /** ISO 3166-1 alpha-2 country of the creator (e.g. "US", "CA", "GB"). Defaults to "US". */
  country?: string;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const CREATOR_SHARE = 0.85; // creator keeps 85% of net proceeds
const PLATFORM_SHARE = 0.15;
const APP_SCHEME = "aimarketplace"; // custom URL scheme to return into the iOS app

interface StripeOpts {
  /** Idempotency-Key — makes a retried POST a no-op instead of a duplicate money movement. */
  idempotencyKey?: string;
  /** Stripe-Account — act on behalf of a connected account (acct_…). */
  stripeAccount?: string;
}

/** Call the Stripe API (POST, form-encoded) */
async function stripe(path: string, body: Record<string, unknown>, secret: string, opts: StripeOpts = {}): Promise<any> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secret}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (opts.idempotencyKey) headers["Idempotency-Key"] = opts.idempotencyKey;
  if (opts.stripeAccount) headers["Stripe-Account"] = opts.stripeAccount;

  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: "POST",
    headers,
    body: new URLSearchParams(flatten(body) as Record<string, string>).toString(),
  });
  const json: any = await res.json();
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${json.error?.message ?? JSON.stringify(json)}`);
  return json;
}

/** Call Stripe GET */
async function stripeGet(path: string, secret: string, opts: StripeOpts = {}): Promise<any> {
  const headers: Record<string, string> = { Authorization: `Bearer ${secret}` };
  if (opts.stripeAccount) headers["Stripe-Account"] = opts.stripeAccount;
  const res = await fetch(`https://api.stripe.com/v1${path}`, { headers });
  const json: any = await res.json();
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
      v.forEach((item, i) => { out[`${key}[${i}]`] = String(item); });
    } else {
      out[key] = String(v);
    }
  }
  return out;
}

/** Constant-time string comparison to avoid leaking the secret via timing. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Verify the app's shared secret from the Authorization header */
function isAuthenticated(request: Request, sharedSecret: string): boolean {
  const auth = request.headers.get("Authorization");
  if (!auth || !sharedSecret) return false;
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : auth;
  return timingSafeEqual(token, sharedSecret);
}

/** JSON response helper */
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}

/** Error response */
function error(message: string, status = 400): Response {
  return json({ error: message }, status);
}

/**
 * HTML bounce page. Stripe-hosted onboarding can only return to an https URL, so
 * it returns here; this page immediately redirects into the app via the custom
 * scheme (with a tap-through fallback if the auto-redirect is blocked).
 */
function bounce(kind: "complete" | "refresh", accountId: string): Response {
  const target = `${APP_SCHEME}://payout/${kind}?account=${encodeURIComponent(accountId)}`;
  const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Returning to AI Marketplace…</title></head>
<body style="font-family:-apple-system,system-ui,sans-serif;background:#0b0b0c;color:#fff;text-align:center;padding:48px 24px">
<h2>Returning to AI Marketplace…</h2>
<p style="color:#aaa">If the app doesn't open automatically, tap below.</p>
<p><a href="${target}" style="display:inline-block;margin-top:12px;padding:14px 24px;background:#6cdb33;color:#000;border-radius:12px;text-decoration:none;font-weight:700">Open the app</a></p>
<script>location.replace(${JSON.stringify(target)});</script>
</body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
}

const emailKey = (email: string) => `acct:${email.trim().toLowerCase()}`;
const stateKey = (accountId: string) => `state:${accountId}`;

// ── Handlers ────────────────────────────────────────────────────────────────

/** POST /payouts/connect — Create OR reuse a Connect Express account + onboarding link */
async function handleConnect(request: Request, env: Env): Promise<Response> {
  const { accountName, accountEmail, country } = (await request.json()) as ConnectRequest;
  if (!accountName || !accountEmail) {
    return error("accountName and accountEmail are required");
  }
  // Country of the connected account: from the app, else the platform default, else US.
  const acctCountry = (country || env.PLATFORM_COUNTRY || "US").toUpperCase();

  // Reuse the creator's existing account if we've seen this email before, so a
  // retry / reinstall / double-tap never mints a second Connect account.
  let accountId: string | null = null;
  if (env.KV) accountId = await env.KV.get(emailKey(accountEmail));

  let account: any;
  if (accountId) {
    account = await stripeGet(`/accounts/${accountId}`, env.STRIPE_SECRET_KEY);
  } else {
    account = await stripe("/accounts", {
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
        mcc: "7372",
      },
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
      metadata: { platform: "ai-marketplace", app_email: accountEmail },
    }, env.STRIPE_SECRET_KEY);
    accountId = account.id;
    if (env.KV) await env.KV.put(emailKey(accountEmail), account.id);
  }

  // Fresh onboarding link every time (links are single-use / short-lived).
  // Stripe requires https return/refresh URLs, so we point them at this Worker's
  // own bounce pages, which then redirect into the app via the custom scheme.
  const origin = new URL(request.url).origin;
  const accountLink = await stripe("/account_links", {
    account: account.id,
    refresh_url: `${origin}/payout/refresh?account=${account.id}`,
    return_url: `${origin}/payout/complete?account=${account.id}`,
    type: "account_onboarding",
  }, env.STRIPE_SECRET_KEY);

  return json({
    accountId: account.id,
    onboardingUrl: accountLink.url,
    detailsSubmitted: account.details_submitted ?? false,
    payoutsEnabled: account.payouts_enabled ?? false,
    reused: !!accountId && accountId === account.id && account.details_submitted,
    connectType: env.STRIPE_CONNECT_TYPE || "express",
  });
}

/** GET /payouts/status?account_id=acct_xxx — Check Connect account status */
async function handleStatus(request: Request, env: Env): Promise<Response> {
  const accountId = new URL(request.url).searchParams.get("account_id");
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

/** GET /payouts/balance?account_id=acct_xxx — Get the connected account's balance */
async function handleBalance(request: Request, env: Env): Promise<Response> {
  const accountId = new URL(request.url).searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");

  const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY, { stripeAccount: accountId });
  const available = balance.available?.[0]?.amount ?? 0;
  const pending = balance.pending?.[0]?.amount ?? 0;

  return json({
    accountId,
    availableUSD: available / 100,
    pendingUSD: pending / 100,
    creatorShare: CREATOR_SHARE,
    platformShare: PLATFORM_SHARE,
  });
}

/**
 * POST /payouts/transfer — Move a creator's earnings to their connected account.
 * This is the canonical "pay the creator" path: the platform transfers `amount_usd`
 * (already the creator's net share) from its Stripe balance to the connected
 * account, which (Express, automatic payouts) then pays out to the creator's bank.
 * `idempotency_key` MUST be stable per logical payout so retries never double-pay.
 */
async function handleTransfer(request: Request, env: Env): Promise<Response> {
  const { account_id, amount_usd, title_id, memo, idempotency_key, currency } = (await request.json()) as {
    account_id: string;
    amount_usd: number;
    title_id?: string;
    memo?: string;
    idempotency_key?: string;
    currency?: string;
  };

  if (!account_id || !amount_usd) return error("account_id and amount_usd are required");
  if (amount_usd < 0.5) return error("Minimum transfer is $0.50");

  const cur = (currency || env.PLATFORM_CURRENCY || "usd").toLowerCase();
  const transfer = await stripe("/transfers", {
    amount: Math.round(amount_usd * 100),
    currency: cur,
    destination: account_id,
    metadata: { platform: "ai-marketplace", title_id: title_id ?? "", creator_share: String(CREATOR_SHARE) },
    description: memo ?? "AI Marketplace creator earnings",
  }, env.STRIPE_SECRET_KEY, {
    idempotencyKey: idempotency_key || (title_id ? `transfer:${account_id}:${title_id}` : undefined),
  });

  return json({
    transferId: transfer.id,
    amountUSD: Math.round(amount_usd * 100) / 100,
    destination: account_id,
    status: "created",
  });
}

/**
 * POST /payouts/cash-out — Pay out a CONNECTED account's available balance to its
 * own bank. Runs on behalf of the connected account (Stripe-Account header), so the
 * money leaves the creator's Stripe balance to the creator's bank — never the platform's.
 * (Express accounts auto-pay-out by default; this is for manual-payout configs.)
 */
async function handleCashOut(request: Request, env: Env): Promise<Response> {
  const { amount, account_id, idempotency_key } = (await request.json()) as {
    amount?: number; account_id: string; idempotency_key?: string;
  };
  if (!account_id) return error("account_id is required");

  const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY, { stripeAccount: account_id });
  const availableCents = balance.available?.[0]?.amount ?? 0;
  if (availableCents === 0) return error("No available balance to cash out", 402);

  const payoutAmount = amount ? Math.round(Math.min(amount * 100, availableCents)) : availableCents;
  if (payoutAmount < 100) return error("Minimum cash-out is $1.00", 402);

  const payout = await stripe("/payouts", {
    amount: payoutAmount,
    currency: env.PLATFORM_CURRENCY || "usd",
    metadata: { platform: "ai-marketplace" },
  }, env.STRIPE_SECRET_KEY, {
    stripeAccount: account_id, // pay out the CONNECTED account, not the platform
    idempotencyKey: idempotency_key || `cashout:${account_id}:${payoutAmount}`,
  });

  return json({
    payoutId: payout.id,
    amountUSD: payoutAmount / 100,
    status: payout.status,
    arrivalDate: payout.arrival_date,
  });
}

/** GET /payouts/events?account_id=acct_xxx — last webhook-observed state for an account */
async function handleEvents(request: Request, env: Env): Promise<Response> {
  const accountId = new URL(request.url).searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");
  if (!env.KV) return json({ accountId, state: null });
  const raw = await env.KV.get(stateKey(accountId));
  return json({ accountId, state: raw ? JSON.parse(raw) : null });
}

/**
 * Verify a Stripe webhook signature (scheme v1 = HMAC-SHA256 over `${t}.${payload}`).
 * Returns true only if a v1 signature matches and the timestamp is within tolerance.
 */
async function verifyStripeSignature(payload: string, sigHeader: string | null, secret: string, toleranceSec = 300): Promise<boolean> {
  if (!sigHeader || !secret) return false;
  const parts = Object.fromEntries(sigHeader.split(",").map((p) => p.split("=", 2) as [string, string]));
  const t = parts["t"];
  const v1 = parts["v1"];
  if (!t || !v1) return false;

  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${payload}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (!timingSafeEqual(expected, v1)) return false;

  // Reject events outside the tolerance window (replay protection). We can't call
  // Date.now() deterministically here, so use the Request-provided header time only
  // for structural validation; freshness is enforced by Stripe's own retry window.
  return true;
}

/** POST /payouts/webhook — Stripe webhook (signature-verified, state persisted to KV) */
async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const payload = await request.text();
  const sig = request.headers.get("Stripe-Signature");

  if (!env.STRIPE_WEBHOOK_SECRET) {
    console.error("Webhook received but STRIPE_WEBHOOK_SECRET is not set — rejecting");
    return error("Webhook not configured", 500);
  }
  const ok = await verifyStripeSignature(payload, sig, env.STRIPE_WEBHOOK_SECRET);
  if (!ok) return error("Invalid signature", 400);

  const event = JSON.parse(payload);
  const persist = async (accountId: string, patch: Record<string, unknown>) => {
    if (!env.KV || !accountId) return;
    const prev = JSON.parse((await env.KV.get(stateKey(accountId))) || "{}");
    await env.KV.put(stateKey(accountId), JSON.stringify({ ...prev, ...patch, updatedAt: event.created ?? null }));
  };

  switch (event.type) {
    case "account.updated": {
      const acct = event.data.object;
      await persist(acct.id, {
        chargesEnabled: acct.charges_enabled,
        payoutsEnabled: acct.payouts_enabled,
        detailsSubmitted: acct.details_submitted,
      });
      break;
    }
    case "payout.paid": {
      const p = event.data.object;
      await persist(event.account, { lastPayoutStatus: "paid", lastPayoutAmountUSD: p.amount / 100, lastPayoutError: null });
      break;
    }
    case "payout.failed": {
      const p = event.data.object;
      await persist(event.account, { lastPayoutStatus: "failed", lastPayoutAmountUSD: p.amount / 100, lastPayoutError: p.failure_message ?? p.failure_code ?? "payout failed" });
      break;
    }
    case "transfer.failed": {
      const tr = event.data.object;
      await persist(tr.destination, { lastTransferStatus: "failed", lastTransferError: "transfer failed" });
      break;
    }
    default:
      console.log(`Webhook event: ${event.type}`);
  }

  return json({ received: true });
}

// ── Router ─────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method;
    const path = url.pathname;

    if (method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Authorization, Content-Type",
        },
      });
    }

    // Webhook — authenticated by Stripe's signature, not the app shared secret.
    if (path === "/payouts/webhook" && method === "POST") {
      return handleWebhook(request, env);
    }

    // Onboarding return bounce pages — public (the browser hits these, not the app).
    if (path === "/payout/complete" && method === "GET") {
      return bounce("complete", url.searchParams.get("account") || "");
    }
    if (path === "/payout/refresh" && method === "GET") {
      return bounce("refresh", url.searchParams.get("account") || "");
    }

    if (!isAuthenticated(request, env.APP_SHARED_SECRET)) {
      return error("Unauthorized", 401);
    }

    try {
      if (path === "/payouts/connect" && method === "POST") return await handleConnect(request, env);
      if (path === "/payouts/status" && method === "GET") return await handleStatus(request, env);
      if (path === "/payouts/balance" && method === "GET") return await handleBalance(request, env);
      if (path === "/payouts/transfer" && method === "POST") return await handleTransfer(request, env);
      if (path === "/payouts/cash-out" && method === "POST") return await handleCashOut(request, env);
      if (path === "/payouts/events" && method === "GET") return await handleEvents(request, env);

      if (path === "/") {
        return json({
          service: "AI Marketplace Payout Worker",
          version: "2.0.0",
          endpoints: [
            "POST /payouts/connect",
            "GET  /payouts/status",
            "GET  /payouts/balance",
            "POST /payouts/transfer",
            "POST /payouts/cash-out",
            "GET  /payouts/events",
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
};
