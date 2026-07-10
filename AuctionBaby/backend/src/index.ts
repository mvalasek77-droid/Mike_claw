/**
 * Auction Baby Payout Worker
 *
 * Handles Stripe Connect onboarding, payout balance, and cash-out for the
 * Auction Baby iOS app, plus Apple App Store Server Notifications (refund
 * routing keyed by appAccountToken) and the money-flow ledger.
 *
 * Money model (mirrors Models/Commerce.swift in the app):
 *   • Bidders (men) buy Gavels + subscriptions via Apple IAP — Apple takes
 *     its commission before any money reaches the platform.
 *   • Women earn from confirmed dates. Of the net proceeds the woman keeps
 *     85% and the platform keeps 15%. Her share is transferred to her own
 *     Stripe Connect Express account and auto-pays to her bank.
 *
 * Required secrets (set via `wrangler secret put`):
 *   STRIPE_SECRET_KEY      — Stripe API secret key (sk_test_… or sk_live_…)
 *   STRIPE_WEBHOOK_SECRET  — whsec_… from the Stripe webhook endpoint
 *   APP_SHARED_SECRET      — shared secret for app→worker auth
 *   RESEND_API_KEY         — (optional) operator emails
 */

interface Env {
  STRIPE_SECRET_KEY: string;
  APP_SHARED_SECRET: string;
  STRIPE_WEBHOOK_SECRET: string; // whsec_… from the Stripe webhook endpoint
  STRIPE_CONNECT_TYPE: string;   // "express" from wrangler.toml [vars]
  // Platform Stripe account settlement currency + default country for new
  // connected accounts. The platform account is CANADIAN, so these are "cad"
  // and "CA" — transfers/payouts MUST settle in the platform's own currency or
  // Stripe rejects them ("insufficient funds" against a CAD balance).
  PLATFORM_CURRENCY?: string;
  PLATFORM_COUNTRY?: string;
  // Stripe publishable key (pk_live_…). Not used server-side — kept so any
  // future client-side flow can read it via GET /stripe/publishable-key.
  STRIPE_PUBLISHABLE_KEY?: string;
  RESEND_API_KEY?: string;   // for operator emails
  // Email the operator on every paid date (default on). Set "false" to mute
  // per-date mail and rely on the periodic digest only.
  NOTIFY_EACH_SALE?: string;
  OPERATOR_EMAIL?: string;   // where ALL operator mail goes (defaults below)
  // Critical financial alerts (NSF / payout failures). Defaults to
  // OPERATOR_EMAIL so everything lands in one inbox.
  ALERT_EMAIL?: string;
  DIGEST_FROM_EMAIL?: string; // verified Resend sender (defaults to onboarding)
  TOPUP_BUFFER_USD?: string;  // keep the platform balance at/above this
  TOPUP_MAX_USD?: string;     // hard cap on any single top-up (safety rail)
  TOPUP_SOURCE_ID?: string;   // ba_… verified bank source for Stripe Top-ups
  // Base URL the Stripe-hosted onboarding flow bounces back to. Defaults to
  // the Worker's own origin (which serves /payout-complete + /payout-refresh).
  PAYOUT_RETURN_BASE?: string;
  // The app's bundle id — ASSN V2 notifications for other apps are rejected.
  APP_BUNDLE_ID?: string;
  // Optional override of the Apple Root CA fingerprint we pin (SHA-256 hex
  // of the DER bytes). Constant unless Apple rotates roots.
  APPLE_ROOT_CA_SHA256?: string;
  KV?: KVNamespace; // ledger + refund queue + moderation + rate limits
}

const DEFAULT_OPERATOR_EMAIL = "mvalasek77@gmail.com";
const DEFAULT_FROM_EMAIL = "Auction Baby <onboarding@resend.dev>";
const DEFAULT_TOPUP_BUFFER_USD = 100;
const DEFAULT_TOPUP_MAX_USD = 200;
const DEFAULT_BUNDLE_ID = "com.valasek.auctionbaby";

/** Resolve the URL base Stripe should bounce women back to after onboarding.
 *  Preference: explicit env override → the Worker's own origin (the built-in
 *  /payout-complete and /payout-refresh routes serve the bounce pages with
 *  zero extra setup). */
function resolvePayoutReturnBase(request: Request, env: Env): string {
  if (env.PAYOUT_RETURN_BASE) return env.PAYOUT_RETURN_BASE;
  try { return new URL(request.url).origin; } catch { return "https://mvalasek77-droid.github.io/Mike_claw"; }
}

interface ConnectRequest {
  accountName: string;
  accountEmail: string;
  country?: string; // ISO 3166-1 alpha-2 (e.g. "CA", "US"); the app sends the woman's region
}

// ── Helpers ─────────────────────────────────────────────────────────────────

// Mirrors Commerce.swift: of net proceeds the woman keeps 85%.
const WOMAN_SHARE = 0.85;
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
    body: new URLSearchParams(flatten(body) as Record<string, string>).toString(),
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
      v.forEach((item, i) => { out[`${key}[${i}]`] = String(item); });
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

/** Per-IP token-bucket limiter in KV. Returns true when the request should be
 *  429'd. The shared-secret model is the primary gate; this is defense-in-depth
 *  for the routes a leaked secret would abuse most. Without KV bound this is a
 *  no-op — we fail open rather than break the app entirely. */
async function rateLimited(env: Env, scope: string, request: Request,
                            capacity: number, refillPerMinute: number): Promise<boolean> {
  if (!env.KV) return false;
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const key = `rl:${scope}:${ip}`;
  const now = Date.now();
  const raw = await env.KV.get(key);
  let tokens = capacity;
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as { tokens: number; last: number };
      const elapsedMin = Math.max(0, (now - parsed.last) / 60_000);
      tokens = Math.min(capacity, parsed.tokens + elapsedMin * refillPerMinute);
    } catch { /* corrupt — start fresh */ }
  }
  if (tokens < 1) {
    await env.KV.put(key, JSON.stringify({ tokens, last: now }), { expirationTtl: 3600 });
    return true;
  }
  tokens -= 1;
  await env.KV.put(key, JSON.stringify({ tokens, last: now }), { expirationTtl: 3600 });
  return false;
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

// ── Connect onboarding ──────────────────────────────────────────────────────

/** POST /payouts/connect — Create a Connect Express account + onboarding link
 *  for a woman who wants her date earnings paid to her bank. */
async function handleConnect(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as ConnectRequest;
  const { accountName, accountEmail, country } = body;
  if (!accountName || !accountEmail) {
    return error("accountName and accountEmail are required");
  }

  // Create the account in her own country when the app supplies one, else the
  // platform's country (CA).
  const acctCountry = (country || env.PLATFORM_COUNTRY || "US").toUpperCase();

  // Idempotency key. Default per-email for safe retry on network blips. When
  // an operator has explicitly released an email via /accounts/release-email
  // (because Stripe rejected the prior account), the KV flag adds a salt so
  // Stripe creates a NEW account instead of returning the rejected cached one.
  let idemKey = `connect_${accountEmail}`;
  if (env.KV) {
    const releaseKey = `connect-release:${accountEmail.toLowerCase()}`;
    const salt = await env.KV.get(releaseKey);
    if (salt) {
      idemKey = `connect_${accountEmail}_${salt}`;
      await env.KV.delete(releaseKey);
    }
  }

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
      product_description: "Auction Baby — earnings from confirmed dates",
      mcc: "7273", // Dating Services
    },
    capabilities: {
      card_payments: { requested: true },
      transfers: { requested: true },
    },
    metadata: {
      platform: "auction-baby",
      app_email: accountEmail,
    },
  }, env.STRIPE_SECRET_KEY, undefined, idemKey);

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
 *  Connect account. Stripe's account_links URLs expire in minutes, so a woman
 *  who returns to finish onboarding after an interruption needs a new link —
 *  without re-creating the account. */
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

/** Public bounce pages Stripe redirects women to after onboarding. Served by
 *  the Worker itself so no extra hosting is required. Styled to match the
 *  app's dark + gold auction-house look. */
function payoutCompleteHTML(accountId: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stripe onboarding complete — Auction Baby</title>
<style>
:root{--bg:#0b0a08;--ink:#f7f4ee;--ink-soft:#d4cec0;--ink-faint:#8f8a7d;--gold:#d4a955;--line:#2a2721;}
*{box-sizing:border-box;}html,body{margin:0;padding:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.wrap{max-width:560px;margin:0 auto;padding:48px 20px;text-align:center;}
h1{font-size:32px;line-height:1.15;letter-spacing:-0.02em;margin:0 0 12px;font-family:ui-serif,Georgia,serif;}
.lede{font-size:18px;color:var(--ink-soft);margin:0 auto 28px;}
.glyph{font-size:64px;line-height:1;margin-bottom:18px;color:var(--gold);}
.card{background:#161410;border:1px solid var(--line);border-radius:14px;padding:20px;margin-top:28px;text-align:left;color:var(--ink-soft);}
.card h3{margin:0 0 8px;color:var(--ink);font-size:17px;}
.card ul{margin:0;padding-left:22px;}
.card li{margin:4px 0;}
.foot{color:var(--ink-faint);font-size:13px;margin-top:32px;}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--ink-faint);}
</style></head><body><div class="wrap">
<div class="glyph">&#x2713;</div>
<h1>You're done with Stripe.</h1>
<p class="lede">Return to Auction Baby. Your payout status refreshes automatically the moment the app comes back to the foreground.</p>
<div class="card"><h3>What happens next</h3><ul>
<li>Stripe verifies the details you submitted (usually minutes; sometimes up to 24 hours).</li>
<li>Once verified, your share of every confirmed date lands in your bank automatically.</li>
<li>You can monitor earnings and payouts from the app any time.</li>
</ul></div>
<p class="foot">Account: <code>${escapeHTML(accountId)}</code></p>
</div></body></html>`;
}

function payoutRefreshHTML(accountId: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stripe onboarding link expired — Auction Baby</title>
<style>
:root{--bg:#0b0a08;--ink:#f7f4ee;--ink-soft:#d4cec0;--ink-faint:#8f8a7d;--gold:#d4a955;--line:#2a2721;}
*{box-sizing:border-box;}html,body{margin:0;padding:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased;}
.wrap{max-width:560px;margin:0 auto;padding:48px 20px;text-align:center;}
h1{font-size:32px;line-height:1.15;letter-spacing:-0.02em;margin:0 0 12px;font-family:ui-serif,Georgia,serif;}
.lede{font-size:18px;color:var(--ink-soft);margin:0 auto 24px;}
.glyph{font-size:64px;line-height:1;margin-bottom:18px;color:var(--gold);}
.foot{color:var(--ink-faint);font-size:13px;margin-top:24px;}
strong{color:var(--ink);}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--ink-faint);}
</style></head><body><div class="wrap">
<div class="glyph">&#x21BB;</div>
<h1>Your Stripe link expired.</h1>
<p class="lede">Stripe's onboarding links time out after a few minutes for security. Return to Auction Baby and tap <strong>Resume Stripe onboarding</strong> on the Payout Setup screen to get a fresh link.</p>
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

// ── Status / balance / cash-out / transfer ──────────────────────────────────

/** GET /payouts/status?account_id=acct_xxx — Check Connect account status */
async function handleStatus(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const accountId = url.searchParams.get("account_id");
  if (!accountId) return error("account_id query param required");

  const account = await stripeGet(`/accounts/${accountId}`, env.STRIPE_SECRET_KEY);

  // Surface `disabled_reason` so the app can show "your application was
  // declined — contact support" instead of silently bouncing her back to
  // "Connect my bank."
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
    availableUSD: available / 100,
    pendingUSD: pending / 100,
    womanShare: WOMAN_SHARE,
    platformShare: PLATFORM_SHARE,
  });
}

/** POST /payouts/cash-out — Trigger payout to the connected bank */
async function handleCashOut(request: Request, env: Env): Promise<Response> {
  const kvGuard = requireKV(env); if (kvGuard) return kvGuard;
  const { amount, account_id } = await request.json() as { amount?: number; account_id: string };
  if (!account_id) return error("account_id is required");

  const balance = await stripeGet(`/balance?stripe_account=${account_id}`, env.STRIPE_SECRET_KEY);
  const availableCents = balance.available?.[0]?.amount ?? 0;
  if (availableCents === 0) return error("No available balance to cash out", 402);

  const payoutAmount = amount
    ? Math.round(Math.min(amount * 100, availableCents))
    : availableCents;
  if (payoutAmount < 100) return error("Minimum cash-out is $1.00", 402);

  // Create the payout ON THE CONNECTED ACCOUNT (Stripe-Account header), so it
  // draws from her balance and lands in her own bank. (Express accounts also
  // auto-pay on a schedule; this is an explicit "pay me now".)
  const currency = (env.PLATFORM_CURRENCY || "usd").toLowerCase();
  let payout: any;
  try {
    payout = await stripe("/payouts", {
      amount: payoutAmount,
      currency,
      metadata: { platform: "auction-baby" },
    }, env.STRIPE_SECRET_KEY, account_id,
       // Minute-precision idempotency: a re-tap within the same minute
       // de-duplicates; an intentional second cash-out an hour later succeeds.
       `cashout_${account_id}_${Math.floor(Date.now() / 60_000)}`);
  } catch (e: any) {
    await recordLedger(env, {
      type: "payout", status: "failed", amountCents: payoutAmount, currency,
      scope: account_id, note: e?.message ?? "payout failed",
    });
    // Alert on EVERY cash-out failure, not just NSF — a bank failing
    // verification produces a 4xx the operator needs to chase.
    await alertNSF(env, {
      kind: isInsufficientFunds(e) ? "cash-out (NSF)" : "cash-out (failed)",
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
    status: payout.status,
    arrivalDate: payout.arrival_date,
  });
}

/** POST /payouts/transfer — Transfer a woman's share (85% of net) to her
 *  Connect account. Called by the platform after each confirmed, paid date. */
async function handleTransfer(request: Request, env: Env): Promise<Response> {
  const kvGuard = requireKV(env); if (kvGuard) return kvGuard;
  const { account_id, amount_usd, date_id, memo, idempotency_key } = await request.json() as {
    account_id: string;
    amount_usd: number;
    date_id?: string;   // the match/date the earning traces to
    memo?: string;
    idempotency_key?: string;
  };

  if (!account_id || !amount_usd) return error("account_id and amount_usd are required");
  if (amount_usd < 0.50) return error("Minimum transfer is $0.50");

  // Per-date idempotency: the app supplies a date-UUID-derived key. Fall back
  // to a fresh UUID so a retry in the same flight doesn't double-pay, while a
  // genuine second date with the same woman still pays.
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
        platform: "auction-baby",
        date_id: date_id ?? "",
        woman_share: String(WOMAN_SHARE),
      },
      description: memo ?? "Auction Baby date earnings",
    }, env.STRIPE_SECRET_KEY, undefined, idem);
  } catch (e: any) {
    await recordLedger(env, {
      type: "transfer", status: "failed", amountCents, currency,
      scope: account_id, refId: date_id, note: e?.message ?? "transfer failed",
    });
    // She is owed but unpaid — queue it so the operator can pay it manually
    // once the float is funded (GET /payouts/unfunded + manual-fund).
    await enqueueUnfunded(env, { accountId: account_id, amountCents, currency, ref: date_id, reason: e?.message ?? "transfer failed" });
    if (isInsufficientFunds(e)) {
      await alertNSF(env, { kind: "date-earnings transfer", scope: account_id, amountCents, currency, detail: e?.message ?? "" });
    }
    return error(e?.message ?? "Transfer failed", 502);
  }

  await recordLedger(env, {
    type: "transfer", status: "succeeded", amountCents, currency,
    scope: account_id, refId: date_id, stripeId: transfer.id,
    note: memo ?? "date earnings",
  });
  await notifySale(env, { amountUSD: amount_usd, date_id, account_id });

  return json({
    transferId: transfer.id,
    amountUSD: amount_usd,
    destination: account_id,
    status: "created",
  });
}

// ── Stripe webhook ──────────────────────────────────────────────────────────

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

/** POST /payouts/webhook — Stripe webhook for Connect/payout/dispute events */
async function handleWebhook(request: Request, env: Env): Promise<Response> {
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
      await recordLedger(env, {
        type: "payout", status: "succeeded", amountCents: payout.amount,
        currency: payout.currency ?? "usd",
        scope: event.account ?? "platform", stripeId: payout.id, note: "payout.paid",
      });
      break;
    }
    case "payout.failed": {
      const payout = event.data.object;
      await recordLedger(env, {
        type: "payout", status: "failed", amountCents: payout.amount,
        currency: payout.currency ?? "usd",
        scope: event.account ?? "platform", stripeId: payout.id,
        note: `payout.failed: ${payout.failure_message ?? payout.failure_code ?? ""}`,
      });
      const code = `${payout.failure_code ?? ""} ${payout.failure_message ?? ""}`;
      if (isInsufficientFunds(code)) {
        await alertNSF(env, {
          kind: "payout (webhook)", scope: event.account ?? "platform",
          amountCents: payout.amount, currency: payout.currency ?? "usd", detail: code.trim(),
        });
      }
      break;
    }
    case "topup.succeeded": {
      // Closes the loop on the auto-topup ledger entry recorded by maybeTopUp().
      const tu = event.data.object;
      await recordLedger(env, {
        type: "topup", status: "succeeded", amountCents: tu.amount,
        currency: tu.currency ?? "usd", scope: "platform", stripeId: tu.id,
        note: "topup.succeeded",
      });
      break;
    }
    case "topup.failed": {
      const tu = event.data.object;
      await recordLedger(env, {
        type: "topup", status: "failed", amountCents: tu.amount,
        currency: tu.currency ?? "usd", scope: "platform", stripeId: tu.id,
        note: `topup.failed: ${tu.failure_message ?? tu.failure_code ?? ""}`,
      });
      // Every transfer until the operator intervenes will NSF.
      await alertNSF(env, {
        kind: "platform topup (webhook)", scope: "platform",
        amountCents: tu.amount, currency: tu.currency ?? "usd",
        detail: tu.failure_message ?? tu.failure_code ?? "",
      });
      break;
    }
    case "charge.refunded": {
      const charge = event.data.object;
      await recordLedger(env, {
        type: "refund", status: "succeeded", amountCents: charge.amount_refunded ?? charge.amount,
        currency: charge.currency ?? "usd", scope: "platform", stripeId: charge.id,
        note: "charge.refunded",
      });
      break;
    }
    case "charge.dispute.created": {
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute", status: "pending", amountCents: dispute.amount,
        currency: dispute.currency ?? "usd", scope: "platform", stripeId: dispute.id,
        note: `dispute opened on ${dispute.charge}; reason: ${dispute.reason ?? "?"}`,
      });
      break;
    }
    case "charge.dispute.funds_withdrawn": {
      // CRITICAL — Stripe already pulled the disputed amount from the float.
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute", status: "funds_withdrawn", amountCents: dispute.amount,
        currency: dispute.currency ?? "usd", scope: "platform", stripeId: dispute.id,
        note: `chargeback on ${dispute.charge}; platform debited`,
      });
      await alertNSF(env, {
        kind: "chargeback debit", scope: "platform",
        amountCents: dispute.amount, currency: dispute.currency ?? "usd",
        detail: `Charge ${dispute.charge} disputed (${dispute.reason ?? "?"}). Float reduced; consider deducting the woman's pending earnings.`,
      });
      break;
    }
    case "charge.dispute.closed": {
      const dispute = event.data.object;
      await recordLedger(env, {
        type: "dispute",
        status: dispute.status === "won" ? "won" : "lost",
        amountCents: dispute.amount,
        currency: dispute.currency ?? "usd", scope: "platform", stripeId: dispute.id,
        note: `dispute closed: ${dispute.status}`,
      });
      break;
    }
    case "transfer.reversed": {
      const transfer = event.data.object;
      await recordLedger(env, {
        type: "transfer", status: "reversed",
        amountCents: transfer.amount_reversed ?? transfer.amount,
        currency: transfer.currency ?? "usd",
        scope: transfer.destination ?? "platform", stripeId: transfer.id,
        note: "transfer reversed",
      });
      await alertNSF(env, {
        kind: "transfer reversal",
        scope: transfer.destination ?? "platform",
        amountCents: transfer.amount_reversed ?? transfer.amount,
        currency: transfer.currency ?? "usd",
        detail: `Transfer ${transfer.id} reversed; her local pending balance is now stale.`,
      });
      break;
    }
    default:
      console.log(`Webhook event: ${event.type}`);
  }

  return json({ received: true });
}

// ── Account deletion ────────────────────────────────────────────────────────

/** POST /accounts/delete — close the connected Stripe account (Apple 5.1.1(v):
 *  in-app account deletion must not leave server-side data behind). Stripe
 *  returns 400 if there's an outstanding balance — the operator must reconcile
 *  before deletion in that case. */
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
  await recordLedger(env, {
    type: "account_closed", status: "succeeded", amountCents: 0, currency: "n/a",
    scope: body.account_id, stripeId: body.account_id,
    note: "Stripe Connect account closed via /accounts/delete",
  });
  return json({ deleted: true });
}

// ── Receipt validation ──────────────────────────────────────────────────────

/** POST /commerce/validate-receipt — server-side check of a StoreKit 2
 *  transaction before the wallet credits Gavels. Enforces payload semantics
 *  + replay protection; full Apple JWS signature verification is the last-mile
 *  TODO (plug in `jose` when moving past on-device trust). */
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

  // Replay protection: if we've validated this transaction id before, deny.
  if (env.KV) {
    const seen = await env.KV.get(`tx:${body.transaction_id}`);
    if (seen === "ok") return json({ valid: true, replay: true, credit_usd: 0 });
  }

  const parts = body.signed_jws.split(".");
  if (parts.length !== 3) return error("malformed signed_jws", 400);
  try {
    const payloadJson = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const payload = JSON.parse(payloadJson);
    if (payload.productId !== body.product_id) return error("product_id mismatch", 400);
    if (payload.transactionId !== body.transaction_id) return error("transaction_id mismatch", 400);
    if (env.KV) {
      await env.KV.put(`tx:${body.transaction_id}`, "ok", { expirationTtl: 60 * 60 * 24 * 90 });
    }
    return json({
      valid: true,
      credit_usd: body.expected_credit_usd ?? 0,
      product_id: body.product_id,
      todo: "Wire Apple JWS signature verification with a JOSE library to fully close the spoof window.",
    });
  } catch {
    return error("couldn't decode JWS payload", 400);
  }
}

// ── App Store Server Notifications V2 ───────────────────────────────────────
//
// When Apple processes a consumable refund it POSTs a signed payload here.
// The client can never see this — consumables disappear from every on-device
// StoreKit sequence the moment they're refunded — so server-side ingest is
// the only path to keep the Gavel wallet honest.
//
// REFUND / REFUND_REVERSED notifications get queued under the buyer's
// `appAccountToken` (the per-user UUID the app attaches to every purchase
// via `Product.PurchaseOption.appAccountToken(_:)` — see AuctionStore.swift).
// The client polls /refunds/pending on launch + foreground and acks via
// /refunds/ack.

/// SHA-256 fingerprint (hex) of Apple Root CA - G3 DER. Constant unless
/// Apple rotates the root; override via APPLE_ROOT_CA_SHA256 if they do.
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
/// X.509 DER cert.
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
/// success, throws on any verification failure.
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
    "raw", rawPubKey, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"],
  );
  const signature = b64urlDecode(parts[2]);
  const data = new TextEncoder().encode(parts[0] + "." + parts[1]);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: { name: "SHA-256" } }, key, signature, data,
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
    // Return 200 so Apple stops retrying a forgery. Log so the operator sees
    // if the pinning needs an update (e.g., Apple rotated the root).
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

  const expectedBundle = env.APP_BUNDLE_ID || DEFAULT_BUNDLE_ID;
  if (txInfo.bundleId && txInfo.bundleId !== expectedBundle) {
    console.error("[ASSN] bundleId mismatch:", txInfo.bundleId, "expected", expectedBundle);
    return json({ ok: false, reason: "bundle mismatch" }, 200);
  }

  if (notificationType === "REFUND") {
    await queueRefund(env, txInfo, "refunded");
  } else if (notificationType === "REFUND_REVERSED") {
    // Apple reversed a refund (rare — usually fraud claim retracted). The
    // credit should be RESTORED; surfaced as a separate queue kind.
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

/// Persist a refund event under the buyer's appAccountToken so the client can
/// drain it on next poll. Key shape:
///   `refund-queue:<appAccountToken>` → JSON array of pending entries.
/// Without an appAccountToken on the tx (legacy purchases), fall back to a
/// global `unattributed` bucket the operator can hand-resolve.
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
  // 90-day TTL — Apple stops retrying long before this, and the client should
  // have polled by then.
  await env.KV.put(key, JSON.stringify(queue), { expirationTtl: 60 * 60 * 24 * 90 });
}

/// GET /refunds/pending?app_account_token=<uuid> — queued refund entries the
/// client hasn't acked. Empty array if none. Auth-required.
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

// ── Moderation (Apple 1.2 — UGC/dating apps require an in-app report flow) ──

async function handleReport(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    profile_id?: string; profile_name?: string;
    reason?: string; details?: string; reporter_email?: string;
    notify_on_resolve?: boolean;
  };
  const id = crypto.randomUUID();
  const ts = new Date().toISOString();

  // Length-cap every operator-visible string so a malicious client can't
  // write 24 MB of garbage into KV.
  const safe = (v: unknown, max: number) =>
    typeof v === "string" ? v.slice(0, max) : "";
  const profileId = safe(body.profile_id, 64);
  const profileName = safe(body.profile_name, 100);
  const reason = safe(body.reason, 100);
  const details = safe(body.details, 2000);
  const reporterEmail = safe(body.reporter_email, 200);

  if (env.KV) {
    // Reverse timestamp so newest sorts first under a prefix scan.
    const reverse = (9999999999999 - Date.now()).toString().padStart(13, "0");
    const record = {
      id, ts, status: "pending" as const,
      profile_id: profileId, profile_name: profileName,
      reason, details, reporter_email: reporterEmail,
      notify_on_resolve: body.notify_on_resolve === true && !!reporterEmail,
      disposition: "" as "" | "removed" | "warned" | "dismissed",
      resolved_at: "" as string,
      resolution_note: "" as string,
    };
    await env.KV.put(`report:pending:${reverse}:${id}`, JSON.stringify(record));
  }

  const subject = `[Auction Baby] Report — ${reason || "Unspecified"}`;
  const lines = [
    `Profile: ${profileName || "(unknown)"}  [${profileId || "?"}]`,
    `Reason: ${reason || "(none)"}`,
    reporterEmail ? `Reporter: ${reporterEmail}` : null,
    "",
    "Details:",
    details.trim() ? details : "(none provided)",
    "",
    `Report id: ${id}`,
    "Open the queue in Admin → Reports to resolve.",
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

/** POST /moderation/reports/{id}/resolve — disposition: removed | warned |
 *  dismissed. Moves the KV key from `report:pending:` to `report:resolved:`. */
async function handleResolveReport(request: Request, env: Env, id: string): Promise<Response> {
  if (!env.KV) return error("KV not bound — moderation queue unavailable", 503);
  const body = await request.json() as { disposition?: string; note?: string };
  const disp = body.disposition ?? "";
  if (!["removed", "warned", "dismissed"].includes(disp)) {
    return error("disposition must be one of: removed, warned, dismissed");
  }
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
  record.resolution_note = typeof body.note === "string" ? body.note.slice(0, 500) : "";
  const reverse = hit.name.split(":")[2]; // preserve original sort
  await env.KV.put(`report:resolved:${reverse}:${id}`, JSON.stringify(record));
  await env.KV.delete(hit.name);

  // Notify the reporter (opt-in at submission time).
  if (record.notify_on_resolve === true &&
      typeof record.reporter_email === "string" &&
      record.reporter_email.includes("@")) {
    const dispCopy: Record<string, string> = {
      removed: "The profile has been removed from the floor.",
      warned: "We've reviewed your report and contacted the user.",
      dismissed: "We reviewed your report and didn't find a policy violation, but thank you for flagging — we keep records of every report and re-review patterns over time.",
    };
    const subject = `[Auction Baby] Your report has been resolved`;
    const note = (typeof record.resolution_note === "string" && record.resolution_note.trim())
      ? `\n\nModerator note: ${record.resolution_note}`
      : "";
    const text = [
      `Hi,`,
      ``,
      `Thanks for reporting "${record.profile_name}". ${dispCopy[disp] ?? ""}${note}`,
      ``,
      `— The Auction Baby moderation team`,
    ].join("\n");
    await sendEmail(env, subject, text, record.reporter_email);
  }

  return json({ resolved: true, id, disposition: disp });
}

// ── Email ───────────────────────────────────────────────────────────────────

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
// KV so that if Stripe ever disagrees with us there's a second source of truth
// to reconcile against. Each entry is immutable; corrections are new entries,
// never edits. Keyed `ledger:<scope>:<ts>:<rand>` where scope is the connected
// account id (or "platform").

interface LedgerEntry {
  ts: string;            // ISO timestamp
  type: string;          // sale | transfer | payout | topup | nsf | refund | dispute | account_closed
  status: string;        // succeeded | failed | pending | reversed | …
  amountCents: number;   // always positive; sign implied by type
  currency: string;
  scope: string;         // accountId or "platform"
  refId?: string;        // date/match id the entry traces to
  stripeId?: string;     // Stripe object id (tr_…, po_…, tu_…) when known
  note?: string;
}

/** Append an immutable entry. Best-effort: a ledger write must never block a
 *  money movement, so failures are logged, not thrown. */
async function recordLedger(env: Env, e: Omit<LedgerEntry, "ts">): Promise<void> {
  if (!env.KV) { console.log(`[ledger skipped — no KV] ${JSON.stringify(e)}`); return; }
  // Dedup on (scope, type, status, stripeId) — Stripe replays webhooks and the
  // app retries failed transfers.
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
    // Write the entry FIRST: if the dedup key were written first and the entry
    // write transiently failed, the retry would see the dedup and skip —
    // losing the entry forever. Worst case this way is a duplicate, which is
    // strictly better than a missing entry.
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

/// Gate for money-moving routes. Without KV bound, recordLedger is a no-op —
/// meaning Stripe transfers/payouts would succeed silently with no audit
/// trail. Refusing the request preserves the operator's ability to detect a
/// misconfigured deployment.
function requireKV(env: Env): Response | null {
  if (env.KV) return null;
  return error("Money-moving routes refused: KV binding missing. Add [[kv_namespaces]] in wrangler.toml so the ledger can record every event.", 503);
}

/** Detect a Stripe insufficient-funds (NSF) condition from a thrown error. */
function isInsufficientFunds(err: unknown): boolean {
  const m = (err instanceof Error ? err.message : String(err)).toLowerCase();
  return m.includes("insufficient")
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
  const subject = `🚨 Auction Baby NSF — ${ctx.kind} of ${cur} ${amt} failed`;
  const body = [
    `A ${ctx.kind} could not complete because of insufficient funds.`,
    ``,
    `Amount:   ${cur} ${amt}`,
    `Account:  ${ctx.scope}`,
    `Stripe:   ${ctx.detail}`,
    ``,
    `What to do: top up the platform Stripe balance (Stripe Dashboard →`,
    `Balance → Add to balance, or wait for the auto-top-up cron), then the`,
    `affected ${ctx.kind} will succeed on the next attempt. The amount has`,
    `NOT been paid out and is still owed — nothing was lost.`,
  ].join("\n");
  await sendEmail(env, subject, body, env.ALERT_EMAIL || env.OPERATOR_EMAIL || DEFAULT_OPERATOR_EMAIL);
}

/** GET /ledger?scope=…&limit=… — the money record for one account (or the
 *  platform). Auth-required. Newest first. */
async function handleLedger(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return json({ entries: [], note: "No KV bound — ledger unavailable." });
  const url = new URL(request.url);
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
 *  compute a woman's true pending balance:
 *      sum(transfer succeeded) - sum(transfer reversed)
 *    - sum(payout succeeded)   - sum(payout pending)
 *  The app uses this to verify its local earnings figure against reality. */
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

/** POST /accounts/release-email — admin tool. Marks an email as "released" so
 *  the next /payouts/connect for that email uses a salted idempotency key,
 *  forcing Stripe to create a FRESH account instead of returning the rejected
 *  cached one. Close the rejected account FIRST via /accounts/delete. */
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

/** GET /admin/kv-export — dump every key+value (under a prefix) as JSON so the
 *  operator can back up reports / ledger before a KV migration. Capped at
 *  1000 keys per call; pass ?cursor=… to continue. */
async function handleKVExport(request: Request, env: Env): Promise<Response> {
  if (!env.KV) return error("KV not bound", 503);
  const url = new URL(request.url);
  const prefix = url.searchParams.get("prefix") ?? "";
  const cursor = url.searchParams.get("cursor") ?? undefined;
  const list = await env.KV.list({ prefix, limit: 1000, cursor });
  const out: Record<string, unknown> = {};
  for (const k of list.keys) {
    const raw = await env.KV.get(k.name);
    if (raw === null) continue;
    try { out[k.name] = JSON.parse(raw); } catch { out[k.name] = raw; }
  }
  return json({
    prefix, count: list.keys.length,
    cursor: list.list_complete ? null : (list as any).cursor ?? null,
    listComplete: list.list_complete,
    values: out,
  });
}

// ── Unfunded queue (owed but unpaid) ────────────────────────────────────────

interface UnfundedEntry {
  id: string;
  ts: string;
  accountId: string;
  amountCents: number;
  currency: string;
  ref?: string;    // date/match id
  reason: string;
}

async function enqueueUnfunded(
  env: Env,
  e: { accountId: string; amountCents: number; currency: string; ref?: string; reason: string },
): Promise<void> {
  if (!env.KV) { console.log(`[unfunded skipped — no KV] ${JSON.stringify(e)}`); return; }
  const id = crypto.randomUUID().slice(0, 12);
  const entry: UnfundedEntry = { id, ts: new Date().toISOString(), ...e };
  try {
    await env.KV.put(`unfunded:${e.accountId}:${id}`, JSON.stringify(entry));
  } catch (err: any) { console.error("unfunded enqueue failed:", err?.message ?? err); }
}

/** GET /payouts/unfunded — every woman currently owed an unpaid transfer. */
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

/** POST /payouts/manual-fund — operator re-pays an owed woman by hand.
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
  // Unique key so a manual re-pay is never deduped against the original transfer.
  const idem = `manual_${body.unfunded_id ?? crypto.randomUUID()}_${Date.now()}`;

  let transfer: any;
  try {
    transfer = await stripe("/transfers", {
      amount: amountCents,
      currency,
      destination: body.account_id,
      metadata: { platform: "auction-baby", manual: "true", reason: body.reason ?? "manual fund" },
      description: body.reason ?? "Auction Baby manual funding",
    }, env.STRIPE_SECRET_KEY, undefined, idem);
  } catch (e: any) {
    await recordLedger(env, {
      type: "transfer", status: "failed", amountCents, currency,
      scope: body.account_id, note: `MANUAL fund failed: ${e?.message ?? ""}`,
    });
    if (isInsufficientFunds(e)) {
      await alertNSF(env, { kind: "manual funding", scope: body.account_id, amountCents, currency, detail: e?.message ?? "" });
    }
    return error(e?.message ?? "Manual fund failed", 502);
  }

  await recordLedger(env, {
    type: "transfer", status: "succeeded", amountCents, currency,
    scope: body.account_id, stripeId: transfer.id, note: `MANUAL fund: ${body.reason ?? ""}`,
  });
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
  salesTodayCount: number;
  salesTodayUSD: number;  // earnings transferred out today (burn)
}

/** Cheap funding snapshot: one balance call + today's sales counter from KV. */
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
    ? `TOP UP NEEDED: ${C} ${f.topUpNeededUSD.toFixed(2)} — make sure your linked bank has it; the auto-top-up cron will pull it to restore the float.`
    : `Float is healthy — no top-up needed right now.`;
  return [
    ``,
    `— Float status —`,
    `Platform balance: ${C} ${f.availableUSD.toFixed(2)}   (target buffer ${C} ${f.bufferUSD.toFixed(2)})`,
    topUp,
    `Paid dates today: ${f.salesTodayCount} (${C} ${f.salesTodayUSD.toFixed(2)} paid out)`,
  ].join("\n");
}

/** Email the operator about a single paid date, with the float footer so one
 *  message answers "did money move?" and "how much do I need to top up?". */
async function notifySale(env: Env, sale: { amountUSD: number; date_id?: string; account_id: string }): Promise<void> {
  if ((env.NOTIFY_EACH_SALE ?? "true") === "false") return;
  await bumpSalesCounter(env, Math.round(sale.amountUSD * 100));
  const f = await platformFunding(env);
  const C = f.currency.toUpperCase();
  const subject = `💰 Auction Baby — ${C} ${sale.amountUSD.toFixed(2)} paid out on a date`;
  const body = [
    `A date was confirmed and paid. Her ${(WOMAN_SHARE * 100).toFixed(0)}% share was transferred to her Stripe balance.`,
    ``,
    `Her share:  ${C} ${sale.amountUSD.toFixed(2)}`,
    `Date id:    ${sale.date_id ?? "(unknown)"}`,
    `Account:    ${sale.account_id}`,
    fundingFooter(f),
  ].join("\n");
  await sendEmail(env, subject, body);
}

/** Keep the platform balance funded so transfers never fail. Pulls from the
 *  linked top-up bank via the Stripe Top-ups API. */
async function maybeTopUp(env: Env): Promise<{ toppedUp: number; availableUSD: number }> {
  const buffer = Number(env.TOPUP_BUFFER_USD ?? DEFAULT_TOPUP_BUFFER_USD);
  const maxTopUp = Number(env.TOPUP_MAX_USD ?? DEFAULT_TOPUP_MAX_USD);
  const balance = await stripeGet(`/balance`, env.STRIPE_SECRET_KEY);
  const cur = (env.PLATFORM_CURRENCY || "usd").toLowerCase();
  const platBal = balance.available?.find((b: any) => b.currency === cur);
  const availableUSD = (platBal?.amount ?? 0) / 100;
  if (availableUSD >= buffer) return { toppedUp: 0, availableUSD };

  // Skip if a top-up is already in flight — they take days to clear and
  // stacking them would over-fund the float.
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
    description: "Auction Baby payout float",
    statement_descriptor: "AUCTIONBABY TOPUP",
  };
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
      // The top-up bank itself bounced — highest-priority alert.
      await alertNSF(env, { kind: "platform float top-up (bank NSF)", scope: "platform", amountCents, currency: cur, detail: e?.message ?? "" });
    }
    throw e; // let the cron's isolated catch log it
  }
  return { toppedUp: amountCents / 100, availableUSD };
}

/** Email the operator a summary of who's owed money and what to do. Reads
 *  balances straight from Stripe (the source of truth). */
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
    const ready = acct.payouts_enabled ? "auto-pays to her bank" : "⚠️ payouts NOT enabled — she must finish Stripe onboarding";
    lines.push(`• ${who} — $${(cents / 100).toFixed(2)} (${ready})  [${acct.id}]`);
  }

  const f = await platformFunding(env);
  const owedBlock = lines.length
    ? `Women with a balance owed:\n\n${lines.join("\n")}\n\nTotal owed: $${owedUSD.toFixed(2)}`
    : `No balances owed right now.`;
  const body = [
    owedBlock,
    fundingFooter(f),
    ``,
    `How payout works: connected women are paid to their own bank by Stripe`,
    `automatically. You only keep the platform float funded (auto-top-up handles`,
    `this — just keep your linked bank funded). For anyone marked ⚠️, nudge her`,
    `to finish Stripe onboarding — Stripe can't pay her until then.`,
  ].join("\n");

  const topUpTag = f.topUpNeededUSD > 0 ? ` · top up ${f.currency.toUpperCase()} ${f.topUpNeededUSD.toFixed(2)}` : "";
  await sendEmail(env, `Auction Baby — ${f.salesTodayCount} paid dates today, $${owedUSD.toFixed(2)} owed${topUpTag}`, body);
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

    // Webhook endpoints — no shared-secret auth (each verifies its own signature)
    if (path === "/payouts/webhook" && method === "POST") {
      return handleWebhook(request, env);
    }
    if (path === "/webhooks/app-store-server" && method === "POST") {
      return handleAppStoreNotification(request, env);
    }

    // Public bounce pages from Stripe-hosted onboarding — no auth (Stripe
    // redirects women here in Safari; they have no Authorization header).
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
      if (path === "/payouts/connect" && method === "POST") {
        // 3 connect attempts / IP / 5 min — creating multiple Stripe accounts
        // is expensive and pollutes the dashboard.
        if (await rateLimited(env, "connect", request, 3, 0.2)) {
          return error("Too many connect attempts — wait a minute and try again.", 429);
        }
        return await handleConnect(request, env);
      }
      if (path === "/payouts/onboarding-link" && method === "POST") {
        return await handleOnboardingLink(request, env);
      }
      if (path === "/payouts/status" && method === "GET") {
        return await handleStatus(request, env);
      }
      if (path === "/payouts/balance" && method === "GET") {
        return await handleBalance(request, env);
      }
      if (path === "/payouts/cash-out" && method === "POST") {
        return await handleCashOut(request, env);
      }
      if (path === "/payouts/transfer" && method === "POST") {
        return await handleTransfer(request, env);
      }

      // Moderation (Apple 1.2 — dating apps must action reports in-app).
      if (path === "/moderation/report" && method === "POST") {
        // 5 reports / IP / minute — stops a leaked secret from spamming
        // the operator inbox or filling KV.
        if (await rateLimited(env, "report", request, 5, 1)) {
          return error("Too many reports — slow down and try again in a minute.", 429);
        }
        return await handleReport(request, env);
      }
      if (path === "/moderation/reports" && method === "GET") {
        return await handleListReports(request, env);
      }
      const resolveMatch = path.match(/^\/moderation\/reports\/([0-9a-fA-F-]{36})\/resolve$/);
      if (resolveMatch && method === "POST") {
        return await handleResolveReport(request, env, resolveMatch[1]);
      }

      if (path === "/commerce/validate-receipt" && method === "POST") {
        return await handleValidateReceipt(request, env);
      }
      if (path === "/refunds/pending" && method === "GET") {
        return await handlePendingRefunds(request, env);
      }
      if (path === "/refunds/ack" && method === "POST") {
        return await handleAckRefunds(request, env);
      }

      if (path === "/ledger" && method === "GET") {
        return await handleLedger(request, env);
      }
      if (path === "/ledger/summary" && method === "GET") {
        return await handleLedgerSummary(env);
      }
      if (path === "/ledger/calculate-balance" && method === "GET") {
        return await handleLedgerCalculateBalance(request, env);
      }

      if (path === "/accounts/release-email" && method === "POST") {
        return await handleReleaseEmail(request, env);
      }
      if (path === "/accounts/delete" && method === "POST") {
        return await handleDeleteAccount(request, env);
      }
      if (path === "/admin/kv-export" && method === "GET") {
        return await handleKVExport(request, env);
      }

      if (path === "/payouts/funding" && method === "GET") {
        return json(await platformFunding(env));
      }
      if (path === "/payouts/unfunded" && method === "GET") {
        return await handleUnfunded(env);
      }
      if (path === "/payouts/manual-fund" && method === "POST") {
        return await handleManualFund(request, env);
      }
      if (path === "/payouts/digest" && method === "POST") {
        return json(await sendPayoutDigest(env));
      }
      if (path === "/payouts/topup" && method === "POST") {
        return json(await maybeTopUp(env));
      }

      if (path === "/stripe/publishable-key" && method === "GET") {
        if (!env.STRIPE_PUBLISHABLE_KEY) {
          return error("STRIPE_PUBLISHABLE_KEY not set", 404);
        }
        return json({ publishableKey: env.STRIPE_PUBLISHABLE_KEY });
      }

      // Health check
      if (path === "/") {
        return json({
          service: "Auction Baby Payout Worker",
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
            "GET  /payouts/funding",
            "GET  /payouts/unfunded",
            "POST /payouts/manual-fund",
            "POST /webhooks/app-store-server",
            "GET  /refunds/pending",
            "POST /refunds/ack",
            "POST /commerce/validate-receipt",
            "POST /moderation/report",
            "GET  /moderation/reports",
            "POST /moderation/reports/{id}/resolve",
            "POST /accounts/delete",
            "POST /accounts/release-email",
            "GET  /ledger",
            "GET  /ledger/summary",
            "GET  /ledger/calculate-balance",
            "GET  /admin/kv-export",
            "GET  /stripe/publishable-key",
            "GET  /payout-complete",
            "GET  /payout-refresh",
          ],
        });
      }

      return error("Not found", 404);
    } catch (err: any) {
      console.error(`Error on ${path}:`, err);
      return error(err.message ?? "Internal server error", 500);
    }
  },

  /** Cron-triggered automation (schedule set in wrangler.toml): keep the
   *  platform float funded, then email the operator the payout digest. */
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil((async () => {
      // Isolated try blocks so a top-up failure can't suppress the digest —
      // the digest is how the operator notices a top-up failed.
      let topup = { toppedUp: 0, availableUSD: 0 };
      try {
        topup = await maybeTopUp(env);
      } catch (err: any) {
        console.error("cron topup error:", err?.message ?? err);
      }
      try {
        const digest = await sendPayoutDigest(env);
        console.log(`cron: topped up $${topup.toppedUp}, ${digest.accounts} women owed $${digest.owedUSD}`);
      } catch (err: any) {
        console.error("cron digest error:", err?.message ?? err);
      }
    })());
  },
};
