/**
 * Auction Baby — Consumable Purchases Worker (Stripe Checkout)
 *
 * Sells Gavel packs through Stripe Checkout (mode=payment, one-time charges,
 * not subscriptions) and keeps a per-user Gavel balance in KV. This is the
 * WEB-SHOP path only: digital Gavels inside the iOS app stay on StoreKit per
 * Apple's rules. The pack ladder mirrors the StoreKit catalog exactly so web
 * and iOS parity holds ($4.99 → 1,000 Gavels … $99.99 → 30,000 Gavels).
 *
 * The card never touches the app or this Worker: /checkout creates a hosted
 * Stripe Checkout Session server-side and returns its URL; Stripe collects
 * payment and calls /webhook, which is the ONLY place a balance is credited —
 * and only after verifying Stripe's signature. Crediting is idempotent by
 * event id, so Stripe's at-least-once webhook delivery can't double-credit.
 *
 * Users are keyed by the app's `appAccountToken` (a per-install UUID, no PII)
 * — the same identifier the payout Worker uses to route Apple IAP refunds, so
 * one identity spans both money surfaces.
 *
 * Ported from the AI Marketplace consumables Worker, with one addition:
 * `charge.refunded` debits the balance (floored at zero), so a Stripe refund
 * claws Gavels back the same way an Apple refund does on the IAP side.
 *
 * Required secrets (set via `wrangler secret put`):
 *   STRIPE_SECRET_KEY      — sk_test_… / sk_live_…
 *   STRIPE_WEBHOOK_SECRET  — whsec_… for the Checkout webhook endpoint
 *   APP_SHARED_SECRET      — shared secret for app→worker auth (also in the app)
 *
 * ── Reserve the date ─────────────────────────────────────────────────────────
 * This Worker also collects a one-time "Reserve the date" fee: once a woman
 * accepts a bid, the bidder can pay a small real-world BOOKING fee to lock in
 * the in-person meeting. Two things make this deliberately different from the
 * Gavel packs above, and both are load-bearing for App Store + legal safety:
 *
 *   1. It is a REAL-WORLD service fee (reserving an in-person date), so per
 *      Apple's rules it must NOT use IAP — Stripe is the correct rail here,
 *      the mirror image of why Gavels must stay on StoreKit.
 *   2. The fee is kept by the PLATFORM. It never credits Gavels and never
 *      flows to the other person — so it isn't escrow, isn't money
 *      transmission, and unlocks no in-app content (reserving only marks the
 *      real-world date as booked). That's what keeps it clear of the
 *      escort-service / marketplace-payout line.
 *
 * Required secrets (set via `wrangler secret put`):
 *   STRIPE_SECRET_KEY      — sk_test_… / sk_live_…
 *   STRIPE_WEBHOOK_SECRET  — whsec_… for the Checkout webhook endpoint
 *   APP_SHARED_SECRET      — shared secret for app→worker auth (also in the app)
 *
 * Endpoints:
 *   GET  /health            — liveness + config sanity (no secrets leaked)
 *   GET  /catalog           — the Gavel packs for sale
 *   POST /checkout          — create a Checkout Session for a pack  [auth]
 *   POST /webhook           — Stripe webhook; credits/debits balances & bookings
 *   GET  /balance?userId=   — a user's current web-Gavel balance    [auth]
 *   POST /consume           — spend/drain Gavels (idempotent)       [auth]
 *   GET  /ledger?userId=    — recent purchases/spends for a user    [auth]
 *   GET  /reserve/info      — the current reservation fee (public)
 *   POST /reserve/checkout  — Checkout Session for a date's booking fee [auth]
 *   GET  /reserve/status?matchId= — is a date reserved?             [auth]
 */

interface Env {
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  APP_SHARED_SECRET: string;
  CURRENCY?: string;
  SUCCESS_URL?: string;
  CANCEL_URL?: string;
  RESERVE_ENABLED?: string;     // "false" turns the whole feature off remotely (kill-switch)
  RESERVE_TIERS_CENTS?: string; // allowed booking-fee amounts, CSV of cents
  KV?: KVNamespace;
  /** Matching Worker base URL, e.g. https://auctionbaby-matching.you.workers.dev
   *  Optional — when set, a paid reservation POSTs the matching Worker's
   *  internal endpoint so `matches.reserved_at` is stamped and every other
   *  device sees the reservation on next GET /matches. Without it the flag
   *  stays device-local (Batch I fallback). */
  MATCHING_URL?: string;
}

// ── Gavel catalog ────────────────────────────────────────────────────────────
// The single source of truth for what a dollar buys on the web shop. Mirrors
// StoreKitService.gavelCatalog / Products.storekit exactly — if one ladder
// changes, change both. Prices are in cents so they map straight onto Stripe.
interface Pack {
  id: string;
  name: string;
  description: string;
  gavels: number;
  priceCents: number;
}

const CATALOG: Pack[] = [
  { id: "gavels_handful", name: "Handful", description: "1,000 Gavels",  gavels: 1_000,  priceCents: 499 },
  { id: "gavels_stack",   name: "Stack",   description: "5,000 Gavels",  gavels: 5_000,  priceCents: 1999 },
  { id: "gavels_chest",   name: "Chest",   description: "14,000 Gavels", gavels: 14_000, priceCents: 4999 },
  { id: "gavels_vault",   name: "Vault",   description: "30,000 Gavels", gavels: 30_000, priceCents: 9999 },
];

function findPack(id: string): Pack | undefined {
  return CATALOG.find((p) => p.id === id);
}

// ── Auction Baby Pass (recurring subscriptions, web/Stripe Billing) ──────────
// Mirrors the iOS PassTier prices (monthly). Web only — Apple IAP handles subs
// on the app. priceCents map to Stripe recurring prices.
interface Pass { id: string; name: string; priceCents: number; }
const PASS_CATALOG: Pass[] = [
  { id: "pass_paddle",    name: "Paddle",     priceCents: 1999 },
  { id: "pass_reserve",   name: "Reserve",    priceCents: 3999 },
  { id: "pass_blackcard", name: "Black Card", priceCents: 9999 },
];
function findPass(id: string): Pass | undefined {
  return PASS_CATALOG.find((p) => p.id === id);
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
// payment_intent → route record so charge.refunded can undo the right thing
// without relying on metadata propagation from the Checkout Session. For a
// Gavel pack the record is {kind:"gavels", userId, gavels, refundedCents};
// for a booking it is {kind:"reservation", userId, matchId}.
const piKey = (paymentIntent: string) => `pi:${paymentIntent}`;
// matchId → {userId, paidAt, sessionId, refunded} — the booking record for a
// single date. Presence + !refunded means the date is reserved.
const reserveKey = (matchId: string) => `res:${matchId}`;

/** Fire-and-forget the reservation state into the matching Worker so
 *  `matches.reserved_at` is stamped and every other device sees the flag
 *  via GET /matches. Gated by `MATCHING_URL` + `APP_SHARED_SECRET` (same
 *  bearer convention across all Workers). Logs, never throws. */
async function notifyMatchingReservation(
  env: Env, matchId: string, amountCents: number, at: number | null,
): Promise<void> {
  if (!env.MATCHING_URL) return;
  const url = env.MATCHING_URL.replace(/\/$/, "") + "/internal/reservations/mark";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.APP_SHARED_SECRET}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ matchId, amountCents, at }),
    });
    if (!res.ok) {
      console.log(`reservation mirror ${res.status} for match ${matchId}`);
    }
  } catch (e) {
    console.log(`reservation mirror transport: ${String(e)}`);
  }
}

/** Remote kill-switch. Set RESERVE_ENABLED="false" to disable reservations
 *  fleet-wide without an app update — the app hides the card when this is off. */
function reserveEnabled(env: Env): boolean {
  return String(env.RESERVE_ENABLED ?? "true").trim().toLowerCase() !== "false";
}

/** The allow-list of "Reserve the date" fee amounts, in cents. A checkout may
 *  only charge one of these, so a client can never POST an arbitrary amount.
 *  Default ladder: $10 / $15 / $25 / $50 / $100. */
function reserveTiersCents(env: Env): number[] {
  const raw = env.RESERVE_TIERS_CENTS ?? "1000,1500,2500,5000,10000";
  const list = raw
    .split(",")
    .map((s) => Math.round(Number(s.trim())))
    .filter((n) => Number.isFinite(n) && n > 0);
  return list.length ? Array.from(new Set(list)).sort((a, b) => a - b) : [1000, 1500, 2500, 5000, 10000];
}

async function getBalance(env: Env, userId: string): Promise<number> {
  if (!env.KV) return 0;
  const raw = await env.KV.get(balanceKey(userId));
  return raw ? Number(raw) || 0 : 0;
}

async function setBalance(env: Env, userId: string, gavels: number): Promise<void> {
  if (!env.KV) return;
  await env.KV.put(balanceKey(userId), String(Math.max(0, Math.round(gavels))));
}

interface LedgerEntry {
  ts: number;
  type: "purchase" | "consume" | "refund";
  gavels: number;      // signed: + on purchase, − on consume/refund
  balanceAfter: number;
  ref: string;         // stripe session id / consume idempotency key / charge id
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

/** GET /catalog — public list of purchasable Gavel packs. */
function handleCatalog(env: Env): Response {
  const currency = (env.CURRENCY ?? "usd").toLowerCase();
  return json({
    currency,
    packs: CATALOG.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      gavels: p.gavels,
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
 *  `userId` is the app's appAccountToken (lowercased UUID).
 *  Returns: { sessionId, url } — redirect the user to `url`. */
async function handleCheckout(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  const packId = String(body?.packId ?? "");
  const userId = String(body?.userId ?? "").trim().toLowerCase();
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
                name: `${pack.name} — ${pack.gavels.toLocaleString("en-US")} Gavels`,
                description: pack.description,
              },
            },
          },
        ],
        // Everything the webhook needs to credit the right user lives here.
        metadata: { userId, packId: pack.id, gavels: String(pack.gavels) },
        client_reference_id: userId,
      },
      env.STRIPE_SECRET_KEY,
      // Idempotent per user+pack so a double-tap doesn't open two sessions
      // within the same minute.
      `checkout:${userId}:${pack.id}:${Math.floor(Date.now() / 60000)}`,
    );
    return json({ sessionId: session.id, url: session.url });
  } catch (e: any) {
    return error(`Checkout failed: ${e.message}`, 502);
  }
}

/** POST /subscribe — create a recurring (monthly) Stripe Checkout Session for
 *  an Auction Baby Pass. Web only. Body: { passId, userId, successUrl?, cancelUrl? }
 *  Returns: { sessionId, url } — redirect the user to `url`. */
async function handleSubscribe(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  const passId = String(body?.passId ?? "");
  const userId = String(body?.userId ?? "").trim().toLowerCase();
  if (!userId) return error("userId is required");
  const pass = findPass(passId);
  if (!pass) return error(`Unknown passId '${passId}'`, 404);

  const currency = (env.CURRENCY ?? "usd").toLowerCase();
  const successUrl = String(body?.successUrl ?? env.SUCCESS_URL ?? "https://example.com/success");
  const cancelUrl = String(body?.cancelUrl ?? env.CANCEL_URL ?? "https://example.com/cancel");

  try {
    const session = await stripe(
      "/checkout/sessions",
      {
        mode: "subscription",
        success_url: successUrl,
        cancel_url: cancelUrl,
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency,
              unit_amount: pass.priceCents,
              recurring: { interval: "month" },
              product_data: { name: `Auction Baby Pass — ${pass.name}` },
            },
          },
        ],
        // kind=subscription so the webhook records entitlement, not Gavels.
        metadata: { kind: "subscription", userId, passId: pass.id },
        // Copy identity onto the subscription too, so a later
        // customer.subscription.deleted can clear the entitlement.
        subscription_data: { metadata: { userId, passId: pass.id } },
        client_reference_id: userId,
      },
      env.STRIPE_SECRET_KEY,
      `subscribe:${userId}:${pass.id}:${Math.floor(Date.now() / 60000)}`,
    );
    return json({ sessionId: session.id, url: session.url });
  } catch (e: any) {
    return error(`Subscribe failed: ${e.message}`, 502);
  }
}

/** GET /subscription?userId= — the user's active Pass id (from KV), or null. */
async function handleSubscriptionStatus(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId")?.trim().toLowerCase();
  if (!userId) return error("userId is required");
  if (!env.KV) return json({ passId: null });
  const passId = await env.KV.get(`pass:${userId}`);
  return json({ passId: passId || null });
}

/** POST /webhook — Stripe events. The ONLY place balances move on purchase or
 *  refund. Verifies the signature; `checkout.session.completed` credits once
 *  per event, `charge.refunded` debits once per event (floored at zero). */
async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const rawBody = await request.text();
  const valid = await verifyStripeSignature(
    rawBody, request.headers.get("Stripe-Signature"), env.STRIPE_WEBHOOK_SECRET);
  if (!valid) return error("Invalid signature", 400);

  let event: any;
  try { event = JSON.parse(rawBody); } catch { return error("Invalid event body"); }

  // Idempotency shared by both event types: one KV mark per event id.
  if (env.KV) {
    const seen = await env.KV.get(eventKey(event.id));
    if (seen) return json({ received: true, duplicate: true });
  }

  // checkout.session.completed covers instant payment methods (cards).
  // Delayed methods (ACH/SEPA) complete with payment_status "unpaid" and
  // Stripe later fires the SEPARATE async_payment_succeeded event when the
  // funds actually clear — miss it and money is taken but never credited.
  if (event.type === "checkout.session.completed" ||
      event.type === "checkout.session.async_payment_succeeded") {
    const session = event.data.object;
    if (session.payment_status !== "paid") {
      // Unpaid completed-event for an async method; the credit rides the
      // later async_payment_succeeded event. Don't mark the event id —
      // no state changed.
      return json({ received: true, skipped: "unpaid" });
    }

    // ── "Reserve the date" booking fee ──────────────────────────────────────
    // A paid reservation marks ONE date as booked. It never credits Gavels and
    // never moves money to another person — the platform keeps the fee for the
    // real-world service of reserving the meeting.
    if (String(session.metadata?.kind ?? "gavels") === "reservation") {
      const matchId = String(session.metadata?.matchId ?? "");
      const bookedBy = String(session.metadata?.userId ?? session.client_reference_id ?? "");
      const amountCents = Number(session.metadata?.amountCents ?? session.amount_total ?? 0);
      if (!matchId) return json({ received: true, skipped: "missing matchId" });
      if (env.KV) {
        await env.KV.put(
          reserveKey(matchId),
          JSON.stringify({ userId: bookedBy, paidAt: Date.now(), amountCents,
                           sessionId: String(session.id), refunded: false }),
          { expirationTtl: 60 * 60 * 24 * 180 },
        );
        if (session.payment_intent) {
          await env.KV.put(
            piKey(String(session.payment_intent)),
            JSON.stringify({ kind: "reservation", userId: bookedBy, matchId }),
            { expirationTtl: 60 * 60 * 24 * 180 },
          );
        }
        await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
      }
      // Batch I — mirror the reservation state onto the matching Worker so
      // it's visible across devices (GET /matches ships reservedAt from D1).
      // Best-effort: failure is logged but never fails the webhook.
      await notifyMatchingReservation(env, matchId, amountCents, Date.now());
      console.log(`Reservation paid for match ${matchId} by ${bookedBy}`);
      return json({ received: true, reserved: true });
    }

    // A subscription (Auction Baby Pass): record the entitlement, credit no Gavels.
    if (String(session.metadata?.kind) === "subscription") {
      const subUser = String(session.metadata?.userId ?? session.client_reference_id ?? "");
      const passId = String(session.metadata?.passId ?? "");
      if (subUser && passId && env.KV) await env.KV.put(`pass:${subUser}`, passId);
      return json({ received: true, subscription: passId });
    }

    const userId = String(session.metadata?.userId ?? session.client_reference_id ?? "");
    const gavels = Number(session.metadata?.gavels ?? 0);
    if (!userId || !gavels) {
      return json({ received: true, skipped: "missing metadata" });
    }

    const current = await getBalance(env, userId);
    const next = current + gavels;
    await setBalance(env, userId, next);
    await appendLedger(env, userId, {
      ts: Date.now(), type: "purchase", gavels, balanceAfter: next,
      ref: String(session.id), note: String(session.metadata?.packId ?? ""),
    });
    if (env.KV) {
      // Route table for refunds: payment_intent → who got how many Gavels
      // for how many cents. 180-day TTL comfortably outlives Stripe's
      // refund window. refundedCents tracks cumulative partial refunds.
      if (session.payment_intent) {
        await env.KV.put(piKey(String(session.payment_intent)),
                         JSON.stringify({ kind: "gavels", userId, gavels, refundedCents: 0 }),
                         { expirationTtl: 60 * 60 * 24 * 180 });
      }
      // Mark the event processed for 30 days — long past Stripe's retry window.
      await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
    }
    console.log(`Credited ${gavels} Gavels to ${userId} (session ${session.id}); balance ${next}`);
  }

  // Subscription ended (canceled / lapsed) → drop the Pass entitlement.
  if (event.type === "customer.subscription.deleted") {
    const sub = event.data.object as any;
    const userId = String(sub.metadata?.userId ?? "");
    if (userId && env.KV) await env.KV.delete(`pass:${userId}`);
    return json({ received: true, subscriptionEnded: true });
  }

  if (event.type === "charge.refunded") {
    const charge = event.data.object;
    const pi = String(charge.payment_intent ?? "");
    if (!pi || !env.KV) return json({ received: true, skipped: "no payment_intent or KV" });

    const routed = await env.KV.get(piKey(pi));
    if (!routed) return json({ received: true, skipped: "unknown payment_intent" });
    const record = JSON.parse(routed) as {
      kind?: string; userId: string; gavels?: number; refundedCents?: number; matchId?: string;
    };

    // A refunded booking fee un-reserves the date; nothing to debit (Gavels
    // were never credited). Idempotent: refunding again just re-sets the flag.
    if (record.kind === "reservation") {
      if (record.matchId) {
        // Clear the matching-Worker mirror on refund so the "Reserved" pill
        // disappears on every device (not just the one that KV-marked it).
        await notifyMatchingReservation(env, record.matchId, 0, null);
        const rraw = await env.KV.get(reserveKey(record.matchId));
        if (rraw) {
          await env.KV.put(reserveKey(record.matchId),
                           JSON.stringify({ ...JSON.parse(rraw), refunded: true }),
                           { expirationTtl: 60 * 60 * 24 * 180 });
        }
      }
      await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
      console.log(`Reservation refunded for match ${record.matchId} (charge ${charge.id})`);
      return json({ received: true, reservationRefunded: true });
    }

    const userId = record.userId;
    const gavels = Number(record.gavels ?? 0);

    // Stripe fires charge.refunded on PARTIAL refunds too, with the
    // CUMULATIVE amount_refunded. Debit proportionally to the newly-refunded
    // slice only, tracked via refundedCents, so a $0.01 partial refund on a
    // $99.99 pack doesn't claw back all 30,000 Gavels — and repeated partial
    // events stay idempotent in aggregate.
    const totalCents = Number(charge.amount ?? 0);
    const cumulativeRefunded = Number(charge.amount_refunded ?? 0);
    const priorRefunded = Number(record.refundedCents ?? 0);
    const newlyRefunded = Math.max(0, Math.min(cumulativeRefunded, totalCents) - priorRefunded);
    if (totalCents <= 0 || newlyRefunded <= 0) {
      await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
      return json({ received: true, skipped: "nothing newly refunded" });
    }
    const debit = Math.round(gavels * (newlyRefunded / totalCents));

    const current = await getBalance(env, userId);
    const next = Math.max(0, current - debit);
    await setBalance(env, userId, next);
    await appendLedger(env, userId, {
      ts: Date.now(), type: "refund", gavels: -(current - next), balanceAfter: next,
      ref: String(charge.id), note: pi,
    });
    await env.KV.put(piKey(pi),
                     JSON.stringify({ ...record, refundedCents: priorRefunded + newlyRefunded }),
                     { expirationTtl: 60 * 60 * 24 * 180 });
    await env.KV.put(eventKey(event.id), "1", { expirationTtl: 60 * 60 * 24 * 30 });
    console.log(`Refund: debited ${current - next} Gavels from ${userId} (charge ${charge.id}); balance ${next}`);
  }

  return json({ received: true });
}

/** GET /balance?userId= — a user's current web-Gavel balance. */
async function handleBalance(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId")?.trim().toLowerCase();
  if (!userId) return error("userId is required");
  return json({ userId, gavels: await getBalance(env, userId) });
}

/** POST /consume — spend/drain Gavels. Idempotent per `idempotencyKey`, so a
 *  retried spend never double-charges the balance. The iOS app uses this to
 *  drain the web balance into the local wallet on foreground.
 *  Body: { userId, gavels, reason?, idempotencyKey } */
async function handleConsume(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  const userId = String(body?.userId ?? "").trim().toLowerCase();
  const gavels = Math.round(Number(body?.gavels ?? 0));
  const idem = String(body?.idempotencyKey ?? "").trim();
  const reason = body?.reason ? String(body.reason) : undefined;
  if (!userId) return error("userId is required");
  if (!Number.isFinite(gavels) || gavels <= 0) return error("gavels must be a positive number");
  if (!idem) return error("idempotencyKey is required");

  // Replay guard: return the prior result rather than spending again.
  if (env.KV) {
    const prior = await env.KV.get(consumeKey(idem));
    if (prior) return json({ ...JSON.parse(prior), replay: true });
  }

  const current = await getBalance(env, userId);
  if (current < gavels) {
    return json({ ok: false, reason: "insufficient_gavels", gavels: current }, 402);
  }
  const next = current - gavels;
  await setBalance(env, userId, next);
  await appendLedger(env, userId, {
    ts: Date.now(), type: "consume", gavels: -gavels, balanceAfter: next,
    ref: idem, note: reason,
  });
  const result = { ok: true, spent: gavels, gavels: next };
  if (env.KV) {
    await env.KV.put(consumeKey(idem), JSON.stringify(result), { expirationTtl: 60 * 60 * 24 * 7 });
  }
  return json(result);
}

/** GET /ledger?userId= — recent purchases/spends. */
async function handleLedger(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId")?.trim().toLowerCase();
  if (!userId) return error("userId is required");
  if (!env.KV) return json({ userId, entries: [] });
  const raw = await env.KV.get(ledgerKey(userId));
  return json({ userId, entries: raw ? JSON.parse(raw) : [] });
}

// ── Reserve the date ─────────────────────────────────────────────────────────

/** GET /reserve/info — public: whether reservations are on, and the allowed
 *  booking-fee tiers so the app can render the picker. */
function handleReserveInfo(env: Env): Response {
  const currency = (env.CURRENCY ?? "usd").toLowerCase();
  const tiers = reserveTiersCents(env).map((c) => ({ cents: c, display: formatPrice(c, currency) }));
  return json({ enabled: reserveEnabled(env), currency, tiers });
}

/** POST /reserve/checkout — Checkout Session for a single date's booking fee.
 *  Body: { matchId, userId, successUrl?, cancelUrl? }
 *  `userId` is the app's appAccountToken (lowercased UUID). Returns { url } to
 *  open in the browser — or { alreadyReserved:true } if it's already booked. */
async function handleReserveCheckout(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return error("Invalid JSON body"); }

  if (!reserveEnabled(env)) return error("Reservations are currently unavailable", 403);

  const matchId = String(body?.matchId ?? "").trim();
  const userId = String(body?.userId ?? "").trim().toLowerCase();
  if (!matchId) return error("matchId is required");
  if (!userId) return error("userId is required");

  // Charge only an allow-listed amount — never an arbitrary client-supplied one.
  const tiers = reserveTiersCents(env);
  const requested = Math.round(Number(body?.amountCents ?? tiers[0]));
  if (!tiers.includes(requested)) {
    return error(`amountCents must be one of: ${tiers.join(", ")}`, 400);
  }
  const cents = requested;

  // Don't open a second Checkout for an already-booked date.
  if (env.KV) {
    const existing = await env.KV.get(reserveKey(matchId));
    if (existing) {
      const rec = JSON.parse(existing);
      if (rec.paidAt && !rec.refunded) return json({ alreadyReserved: true });
    }
  }

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
              unit_amount: cents,
              product_data: {
                name: "Reserve your date",
                description:
                  "Booking fee to lock in your in-person date. Paid to Auction Baby " +
                  "for the reservation — not to your match, and it unlocks nothing in the app.",
              },
            },
          },
        ],
        metadata: { kind: "reservation", matchId, userId, amountCents: String(cents) },
        client_reference_id: userId,
      },
      env.STRIPE_SECRET_KEY,
      // Idempotent per match+amount within the minute so a double-tap opens one session.
      `reserve:${matchId}:${cents}:${Math.floor(Date.now() / 60000)}`,
    );
    return json({ sessionId: session.id, url: session.url });
  } catch (e: any) {
    return error(`Reservation checkout failed: ${e.message}`, 502);
  }
}

/** GET /reserve/status?matchId= — is this date reserved (and not refunded)? */
async function handleReserveStatus(request: Request, env: Env): Promise<Response> {
  const matchId = new URL(request.url).searchParams.get("matchId")?.trim();
  if (!matchId) return error("matchId is required");
  if (!env.KV) return json({ matchId, reserved: false });
  const raw = await env.KV.get(reserveKey(matchId));
  if (!raw) return json({ matchId, reserved: false });
  const rec = JSON.parse(raw);
  return json({ matchId, reserved: Boolean(rec.paidAt) && !rec.refunded,
                paidAt: rec.paidAt ?? null, amountCents: rec.amountCents ?? null });
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
        service: "auctionbaby-consumables",
        currency: (env.CURRENCY ?? "usd").toLowerCase(),
        packs: CATALOG.length,
        stripeConfigured: Boolean(env.STRIPE_SECRET_KEY),
        webhookConfigured: Boolean(env.STRIPE_WEBHOOK_SECRET),
        kvBound: Boolean(env.KV),
      });
    }
    if (pathname === "/catalog" && method === "GET") return handleCatalog(env);
    if (pathname === "/reserve/info" && method === "GET") return handleReserveInfo(env);
    // Stripe calls this server-to-server; it authenticates via signature, not
    // the shared secret.
    if (pathname === "/webhook" && method === "POST") return handleWebhook(request, env);

    // Authenticated app routes.
    const authed = await isAuthenticated(request, env.APP_SHARED_SECRET);
    if (!authed) return error("Unauthorized", 401);

    if (pathname === "/checkout" && method === "POST") return handleCheckout(request, env);
    if (pathname === "/subscribe" && method === "POST") return handleSubscribe(request, env);
    if (pathname === "/subscription" && method === "GET") return handleSubscriptionStatus(request, env);
    if (pathname === "/balance" && method === "GET") return handleBalance(request, env);
    if (pathname === "/consume" && method === "POST") return handleConsume(request, env);
    if (pathname === "/ledger" && method === "GET") return handleLedger(request, env);
    if (pathname === "/reserve/checkout" && method === "POST") return handleReserveCheckout(request, env);
    if (pathname === "/reserve/status" && method === "GET") return handleReserveStatus(request, env);

    return error("Not found", 404);
  },
};
