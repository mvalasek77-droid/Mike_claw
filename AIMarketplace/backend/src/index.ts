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

interface Env {
  STRIPE_SECRET_KEY: string;
  APP_SHARED_SECRET: string;
  STRIPE_WEBHOOK_SECRET: string; // whsec_… from the Stripe webhook endpoint
  STRIPE_CONNECT_TYPE: string; // "express" from wrangler.toml [vars]
  KV?: KVNamespace; // optional: for storing account IDs
}

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

/** Verify the app's shared secret from the Authorization header */
function isAuthenticated(request: Request, sharedSecret: string): boolean {
  const auth = request.headers.get("Authorization");
  if (!auth) return false;
  // Accept "Bearer <secret>" or just the raw secret
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : auth;
  return token === sharedSecret;
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
  }, env.STRIPE_SECRET_KEY);

  // Step 2: Create an account link for onboarding
  // The return_url brings the user back into the app via deep link
  const accountLink = await stripe("/account_links", {
    account: account.id,
    refresh_url: `https://aimarketplace.app/payout/refresh?account=${account.id}`,
    return_url: `https://aimarketplace.app/payout/complete?account=${account.id}`,
    type: "account_onboarding",
  }, env.STRIPE_SECRET_KEY);

  return json({
    accountId: account.id,
    onboardingUrl: accountLink.url,
    connectType: env.STRIPE_CONNECT_TYPE || "express",
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
  const idem = idempotency_key
    ?? (title_id ? `xfer_${account_id}_${title_id}` : crypto.randomUUID());

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

    // All other endpoints require the shared secret
    if (!isAuthenticated(request, env.APP_SHARED_SECRET)) {
      return error("Unauthorized", 401);
    }

    try {
      // Connect: create account + get onboarding link
      if (path === "/payouts/connect" && method === "POST") {
        return await handleConnect(request, env);
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