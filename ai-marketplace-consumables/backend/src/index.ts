/**
 * AI Marketplace — Consumable Purchases Worker
 *
 * Sells consumable "credit" packs through Stripe Checkout (mode=payment, i.e.
 * one-time charges, not subscriptions) and keeps a per-user credit balance in
 * KV. Credits are the consumable good: the app spends them on generations,
 * unlocks, etc. and they do not renew.
 *
 * The card never touches the app or this Worker: /checkout creates a hosted
 * Stripe Checkout Session server-side and returns its URL; Stripe collects
 * payment and calls /webhook, which is the ONLY place a balance is credited —
 * and only after verifying Stripe's signature. Crediting is idempotent by
 * event id, so Stripe's at-least-once webhook delivery can't double-credit.
 *
 * Required secrets (set via `wrangler secret put`):
 *   STRIPE_SECRET_KEY      — sk_test_… / sk_live_…
 *   STRIPE_WEBHOOK_SECRET  — whsec_… for the Checkout webhook endpoint
 *   APP_SHARED_SECRET      — shared secret for app→worker auth (also in the app)
 *
 * Endpoints:
 *   GET  /health           — liveness + config sanity (no secrets leaked)
 *   GET  /catalog          — the consumable credit packs for sale
 *   POST /checkout         — create a Checkout Session for a pack  [auth]
 *   POST /webhook          — Stripe webhook; credits the balance on success
 *   GET  /balance?userId=  — a user's current consumable credit balance [auth]
 *   POST /consume          — spend credits (idempotent)                [auth]
 *   GET  /ledger?userId=   — recent purchases/spends for a user        [auth]
 */

interface Env {
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  APP_SHARED_SECRET: string;
  CURRENCY?: string;
  SUCCESS_URL?: string;
  CANCEL_URL?: string;
  KV?: KVNamespace;
}

// ── Consumable catalog ───────────────────────────────────────────────────────
// The single source of truth for what a dollar buys. Prices are in the smallest
// currency unit (cents) so they map straight onto Stripe amounts. Edit here and
// redeploy — there's no dashboard product to keep in sync.
interface Pack {
  id: string;
  name: string;
  description: string;
  credits: number;
  priceCents: number;
}

const CATALOG: Pack[] = [
  { id: "credits_100",  name: "Starter",   description: "100 credits",   credits: 100,   priceCents: 499 },
  { id: "credits_550",  name: "Plus",      description: "500 + 50 bonus credits", credits: 550,   priceCents: 1999 },
  { id: "credits_1200", name: "Pro",       description: "1,000 + 200 bonus credits", credits: 1200,  priceCents: 3999 },
  { id: "credits_3500", name: "Studio",    description: "3,000 + 500 bonus credits", credits: 3500,  priceCents: 9999 },
];

function findPack(id: string): Pack | undefined {
  return CATALOG.find((p) => p.id === id);
}

// ── Stripe helpers ───────────────────────────────────────────────────────────

/** POST to the Stripe API with form-encoded params (Stripe wants
 *  x-www-form-urlencoded, not JSON). `idempotencyKey` makes retried creates
 *  safe. */
async function stripe(
  path: string,
  body: Record<string, unknown>,
  secret: string,
  idempotencyKey?: string,
): Promise<any> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${secret}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: "POST",
    headers,
    body: new URLSearchParams(flatten(body)).toString(),
  });
  const j = (await res.json()) as any;
  if (!res.ok) throw new Error(`Stripe ${res.status}: ${j.error?.message ?? JSON.stringify(j)}`);
  return j;
}

/** Flatten nested objects/arrays into Stripe's `a[b][0]=c` form encoding. */
function flatten(obj: Record<string, unknown>, prefix = ""): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}[${k}]` : k;
    if (v === undefined || v === null) continue;
    if (Array.isArray(v)) {
      v.forEach((item, i) => {
        if (typeof item === "object" && item !== null) {
          Object.assign(out, flatten(item as Record<string, unknown>, `${key}[${i}]`));
        } else {
          out[`${key}[${i}]`] = String(item);
        }
      });
    } else if (typeof v === "object") {
      Object.assign(out, flatten(v as Record<string, unknown>, key));
    } else {
      out[key] = String(v);
    }
  }
  return out;
}

/** Constant-time-ish verify of Stripe's `Stripe-Signature` header (HMAC-SHA256
 *  of `${timestamp}.${rawBody}`) with a 5-minute replay window. */
async function verifyStripeSignature(rawBody: string, sigHeader: string | null, secret: string): Promise<boolean> {
  if (!sigHeader || !secret) return false;
  const parts = Object.fromEntries(
    sigHeader.split(",").map((p) => p.split("=", 2) as [string, string]),
  );
  const timestamp = parts["t"];
  const signature = parts["v1"];
  if (!timestamp || !signature) return false;
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
  if (expected.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return mismatch === 0;
}

// ── Auth ─────────────────────────────────────────────────────────────────────

/** Verify the app's shared secret from the Authorization header, comparing in
 *  constant time over SHA-256 digests so timing can't leak the secret. */
async function isAuthenticated(request: Request, sharedSecret: string): Promise<boolean> {
  const auth = request.headers.get("Authorization");
  if (!auth || !sharedSecret) return false;
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

// ── KV: balances + ledger ────────────────────────────────────────────────────

const balanceKey = (userId: string) => `bal:${userId}`;
const eventKey = (eventId: string) => `evt:${eventId}`;       // webhook idempotency
const consumeKey = (key: string) => `use:${key}`;             // consume idempotency
const ledgerKey = (userId: string) => `led:${userId}`;

async function getBalance(env: Env, userId: string): Promise<number> {
  if (!env.KV) return 0;
  const raw = await env.KV.get(balanceKey(userId));
  return raw ? Number(raw) || 0 : 0;
}

async function setBalance(env: Env, userId: string, credits: number): Promise<void> {
  if (!env.KV) return;
  await env.KV.put(balanceKey(userId), String(Math.max(0, Math.round(credits))));
}

interface LedgerEntry {
  ts: number;
  type: "purchase" | "consume";
  credits: number;     // signed: + on purchase, − on consume
  balanceAfter: number;
  ref: string;         // stripe session id / consume idempotency key
  note?: string;
}

async function appendLedger(env: Env, userId: string, entry: LedgerEntry): Promise<void> {
  if (!env.KV) return;
  const raw = await env.KV.get(ledgerKey(userId));
  const list: LedgerEntry[] = raw ? JSON.parse(raw) : [];
  list.unshift(entry);
  await env.KV.put(ledgerKey(userId), JSON.stringify(list.slice(0, 50)));
}

// ── Responses ────────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
const error = (message: string, status = 400) => json({ error: message }, status);

// ── Route handlers ───────────────────────────────────────────────────────────

/** GET /catalog — public list of purchasable packs. */
function handleCatalog(env: Env): Response {
  const currency = (env.CURRENCY ?? "usd").toLowerCase();
  return json({
    currency,
    packs: CATALOG.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      credits: p.credits,
      priceCents: p.priceCents,
      priceDisplay: formatPrice(p.priceCents, currency),
    })),
  });
}

function formatPrice(cents: number, currency: string): string {
  const symbol = currency === "usd" || currency === "cad" ? "$" : "";
  return `${symbol}${(cents / 100).toFixed(2)}`;
}

/** POST /checkout — create a Stripe Checkout Session for a pack.
 *  Body: { packId, userId, successUrl?, cancelUrl? }
 *  Returns: { sessionId, url } — redirect the user to `url`. */
async function handleCheckout(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  const packId = String(body?.packId ?? "");
  const userId = String(body?.userId ?? "").trim();
  if (!userId) return error("userId is required");
  const pack = findPack(packId);
  if (!pack) return error(`Unknown packId '${packId}'`, 404);

  const currency = (env.CURRENCY ?? "usd").toLowerCase();
  const successUrl = String(body?.successUrl ?? env.SUCCESS_URL ?? "https://example.com/success");
  const cancelUrl = String(body?.cancelUrl ?? env.CANCEL_URL ?? "https://example.com/cancel");

  try {
    const session = await stripe(
      "/checkout/sessions",
      {
        mode: "payment",
        success_url: successUrl,
        cancel_url: cancelUrl,
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency,
              unit_amount: pack.priceCents,
              product_data: {
                name: `${pack.name} — ${pack.credits} credits`,
                description: pack.description,
              },
            },
          },
        ],
        // Everything the webhook needs to credit the right user lives here.
        metadata: { userId, packId: pack.id, credits: String(pack.credits) },
        client_reference_id: userId,
      },
      env.STRIPE_SECRET_KEY,
      // Idempotent per user+pass so a double-tap doesn't open two sessions
      // within the same minute.
      `checkout:${userId}:${pack.id}:${Math.floor(Date.now() / 60000)}`,
    );
    return json({ sessionId: session.id, url: session.url });
  } catch (e: any) {
    return error(`Checkout failed: ${e.message}`, 502);
  }
}

/** POST /webhook — Stripe Checkout events. The ONLY place credits are minted.
 *  Verifies the signature, then on `checkout.session.completed` (and paid)
 *  credits the user's balance exactly once per event. */
async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const rawBody = await request.text();
  const valid = await verifyStripeSignature(
    rawBody, request.headers.get("Stripe-Signature"), env.STRIPE_WEBHOOK_SECRET);
  if (!valid) return error("Invalid signature", 400);

  let event: any;
  try { event = JSON.parse(rawBody); } catch { return error("Invalid event body"); }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    // Only credit a genuinely paid session (async payment methods complete later).
    if (session.payment_status !== "paid") {
      return json({ received: true, skipped: "unpaid" });
    }

    // Idempotency: if we've already processed this event id, do nothing.
    if (env.KV) {
      const seen = await env.KV.get(eventKey(event.id));
      if (seen) return json({ received: true, duplicate: true });
    }

    const userId = String(session.metadata?.userId ?? session.client_reference_id ?? "");
    const credits = Number(session.metadata?.credits ?? 0);
    if (!userId || !credits) {
      return json({ received: true, skipped: "missing metadata" });
    }

    const current = await getBalance(env, userId);
    const next = current + credits;
    await setBalance(env, userId, next);
    await appendLedger(env, userId, {
      ts: Date.now(), type: "purchase", credits, balanceAfter: next,
      ref: String(session.id), note: String(session.metadata?.packId ?? ""),
    });
    if (env.KV) {
      // Mark the event processed for 30 days — long past Stripe's retry window.
      await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
    }
    console.log(`Credited ${credits} to ${userId} (session ${session.id}); balance ${next}`);
  }

  return json({ received: true });
}

/** GET /balance?userId= — a user's current consumable credit balance. */
async function handleBalance(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId")?.trim();
  if (!userId) return error("userId is required");
  return json({ userId, credits: await getBalance(env, userId) });
}

/** POST /consume — spend credits. Idempotent per `idempotencyKey`, so a retried
 *  spend never double-charges the balance.
 *  Body: { userId, credits, reason?, idempotencyKey } */
async function handleConsume(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  const userId = String(body?.userId ?? "").trim();
  const credits = Math.round(Number(body?.credits ?? 0));
  const idem = String(body?.idempotencyKey ?? "").trim();
  const reason = body?.reason ? String(body.reason) : undefined;
  if (!userId) return error("userId is required");
  if (!Number.isFinite(credits) || credits <= 0) return error("credits must be a positive number");
  if (!idem) return error("idempotencyKey is required");

  // Replay guard: return the prior result rather than spending again.
  if (env.KV) {
    const prior = await env.KV.get(consumeKey(idem));
    if (prior) return json({ ...JSON.parse(prior), replay: true });
  }

  const current = await getBalance(env, userId);
  if (current < credits) {
    return json({ ok: false, reason: "insufficient_credits", credits: current }, 402);
  }
  const next = current - credits;
  await setBalance(env, userId, next);
  await appendLedger(env, userId, {
    ts: Date.now(), type: "consume", credits: -credits, balanceAfter: next,
    ref: idem, note: reason,
  });
  const result = { ok: true, spent: credits, credits: next };
  if (env.KV) {
    await env.KV.put(consumeKey(idem), JSON.stringify(result), { expirationTtl: 60 * 60 * 24 * 7 });
  }
  return json(result);
}

/** GET /ledger?userId= — recent purchases/spends. */
async function handleLedger(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId")?.trim();
  if (!userId) return error("userId is required");
  if (!env.KV) return json({ userId, entries: [] });
  const raw = await env.KV.get(ledgerKey(userId));
  return json({ userId, entries: raw ? JSON.parse(raw) : [] });
}

// ── Router ───────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;
    const method = request.method;

    if (method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
          "Access-Control-Allow-Headers": "Authorization,Content-Type,Stripe-Signature",
        },
      });
    }

    // Public routes.
    if (pathname === "/health" && method === "GET") {
      return json({
        ok: true,
        service: "ai-marketplace-consumables",
        currency: (env.CURRENCY ?? "usd").toLowerCase(),
        packs: CATALOG.length,
        stripeConfigured: Boolean(env.STRIPE_SECRET_KEY),
        webhookConfigured: Boolean(env.STRIPE_WEBHOOK_SECRET),
        kvBound: Boolean(env.KV),
      });
    }
    if (pathname === "/catalog" && method === "GET") return handleCatalog(env);
    // Stripe calls this server-to-server; it authenticates via signature, not
    // the shared secret.
    if (pathname === "/webhook" && method === "POST") return handleWebhook(request, env);

    // Authenticated app routes.
    const authed = await isAuthenticated(request, env.APP_SHARED_SECRET);
    if (!authed) return error("Unauthorized", 401);

    if (pathname === "/checkout" && method === "POST") return handleCheckout(request, env);
    if (pathname === "/balance" && method === "GET") return handleBalance(request, env);
    if (pathname === "/consume" && method === "POST") return handleConsume(request, env);
    if (pathname === "/ledger" && method === "GET") return handleLedger(request, env);

    return error("Not found", 404);
  },
};
