/**
 * Auction Baby — Auth Worker (Sign in with Apple → server user identity).
 *
 * This is Slice 1 of the "spine" — the multi-week backbone that turns Auction
 * Baby from a beautifully-finished single-player simulation into a real
 * two-sided dating app. Slice 1 adds *only* durable server identity: every
 * later slice (push, verification, matching, moderation) joins on the
 * `userId` this Worker issues. Nothing user-visible changes yet beyond a
 * "Sign in with Apple" button in onboarding.
 *
 * Flow:
 *   1. iOS runs SIWA → gets an Apple identity token (a JWT signed with RS256
 *      by an Apple private key we can look up in their JWKS).
 *   2. iOS POSTs it to /auth/apple with an optional name (Apple only returns
 *      the name on the FIRST sign-in, so the client passes it through).
 *   3. This Worker verifies the JWT signature + claims, upserts a row in D1
 *      keyed on the Apple `sub` (stable per-user id), and returns a HMAC-
 *      signed opaque session token the client stores in Keychain.
 *   4. Every future authed request carries `Authorization: Bearer <token>`.
 *
 * Sessions are STATELESS: `userId.expiryMs.signature`, signed with
 * HMAC-SHA256(SESSION_SECRET). No sessions table → no DB round-trip on
 * every request; the tradeoff is that revocation requires rotating
 * SESSION_SECRET (which invalidates every session at once). Fine for slice 1;
 * a `revoked_sessions` table can be added later if we need per-user logout.
 *
 * What is *deliberately not* here (yet):
 *   - Push (slice 2), verification (slice 3), matching (slice 4),
 *     moderation (slice 5). See SPINE_ROADMAP.md.
 *
 * Endpoints:
 *   GET    /health              — liveness + config sanity (no secrets leaked)
 *   POST   /auth/apple          — exchange an Apple identity JWT for our session
 *   GET    /me                  — the authed user record             [auth]
 *   POST   /auth/logout         — client-side hint; refreshes last_seen [auth]
 *   DELETE /me                  — delete the account (GDPR/CCPA)     [auth]
 *
 *   Slice 2 (push notifications):
 *   POST   /devices/register    — register/upsert an APNs device token [auth]
 *   POST   /devices/unregister  — remove a device token (sign-out)     [auth]
 *   POST   /push/send           — dispatch a push to a userId's devices
 *                                 (admin-only, gated by APP_SHARED_SECRET)
 */

interface Env {
  DB: D1Database;
  SESSION_SECRET: string;
  APPLE_CLIENT_ID: string;         // e.g. "com.valasek.auctionbaby" (bundle id)
  SESSION_TTL_SECONDS?: string;    // default 30 days
  APP_SHARED_SECRET?: string;      // gates admin endpoints (POST /push/send)

  // ── Slice 2: APNs push (optional — absent = push send is a no-op) ─────────
  APNS_AUTH_KEY_P8?: string;       // full PEM contents of the .p8
  APNS_KEY_ID?: string;            // 10-char key id from Apple Developer
  APNS_TEAM_ID?: string;           // 10-char Apple Developer team id
}

// ── Constants ────────────────────────────────────────────────────────────────

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
/** Apple rotates their signing keys. Cache the JWKS for 24h — safe because
 *  we look up by `kid` and fall back to a refresh if the key isn't found. */
const JWKS_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

// ── Response helpers ─────────────────────────────────────────────────────────

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
  "Access-Control-Allow-Headers": "Authorization,Content-Type",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}
const err = (message: string, status = 400) => json({ error: message }, status);

// ── Session token (stateless, HMAC-SHA256-signed) ────────────────────────────

function base64UrlEncode(bytes: Uint8Array): string {
  const bin = String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function base64UrlDecode(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacSha256(key: string, message: string): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message));
  return new Uint8Array(sig);
}

/** Build `userId.expiryMs.signature`. */
async function issueSessionToken(userId: string, ttlSeconds: number, secret: string): Promise<string> {
  const expiryMs = Date.now() + ttlSeconds * 1000;
  const payload = `${userId}.${expiryMs}`;
  const sig = base64UrlEncode(await hmacSha256(secret, payload));
  return `${payload}.${sig}`;
}

/** Constant-time verify a session token → returns userId or null. */
async function verifySessionToken(token: string, secret: string): Promise<string | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [userId, expiryStr, sig] = parts;
  const expiry = Number(expiryStr);
  if (!Number.isFinite(expiry) || Date.now() > expiry) return null;
  const expected = base64UrlEncode(await hmacSha256(secret, `${userId}.${expiryStr}`));
  if (expected.length !== sig.length) return null;
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) mismatch |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  return mismatch === 0 && userId ? userId : null;
}

// ── Apple JWKS + JWT verification ────────────────────────────────────────────

interface AppleJwk { kty: string; kid: string; use: string; alg: string; n: string; e: string; }
interface AppleJwks { keys: AppleJwk[]; }

/** Module-level JWKS cache. Workers reuse the isolate across requests, so
 *  this survives across warm invocations and drops on cold-start / restart. */
let jwksCache: { jwks: AppleJwks; fetchedAt: number } | null = null;

async function fetchAppleJwks(force = false): Promise<AppleJwks> {
  if (!force && jwksCache && Date.now() - jwksCache.fetchedAt < JWKS_CACHE_TTL_MS) {
    return jwksCache.jwks;
  }
  const res = await fetch(APPLE_JWKS_URL, { cf: { cacheTtl: 3600, cacheEverything: true } as any });
  if (!res.ok) throw new Error(`Apple JWKS fetch failed: HTTP ${res.status}`);
  const jwks = (await res.json()) as AppleJwks;
  jwksCache = { jwks, fetchedAt: Date.now() };
  return jwks;
}

/** Import a JWK as an RS256 verify key. */
async function importAppleKey(jwk: AppleJwk): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", use: "sig", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["verify"],
  );
}

interface AppleClaims {
  iss: string; sub: string; aud: string;
  iat: number; exp: number; nonce?: string;
  email?: string; email_verified?: boolean | string;
  is_private_email?: boolean | string;
}

/** Verify an Apple identity JWT. Throws on any failure — never returns
 *  partial verification. Returns the parsed claims on success. */
async function verifyAppleIdentityToken(token: string, expectedAudience: string): Promise<AppleClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Malformed JWT");
  const [headerB64, payloadB64, sigB64] = parts;

  const header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerB64))) as { alg: string; kid: string };
  if (header.alg !== "RS256") throw new Error(`Unsupported alg: ${header.alg}`);
  if (!header.kid) throw new Error("Missing kid");

  // Fetch JWKS; if the kid isn't there, force-refresh once (Apple rotated keys).
  let jwks = await fetchAppleJwks(false);
  let jwk = jwks.keys.find((k) => k.kid === header.kid);
  if (!jwk) {
    jwks = await fetchAppleJwks(true);
    jwk = jwks.keys.find((k) => k.kid === header.kid);
  }
  if (!jwk) throw new Error(`Unknown Apple signing key kid: ${header.kid}`);

  const key = await importAppleKey(jwk);
  const signature = base64UrlDecode(sigB64);
  const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signingInput);
  if (!ok) throw new Error("Invalid JWT signature");

  const claims = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadB64))) as AppleClaims;

  // Claim checks. Any failure here is a hard rejection — a valid signature
  // on the wrong claims is exactly the attack we're guarding against.
  if (claims.iss !== APPLE_ISSUER) throw new Error(`Wrong issuer: ${claims.iss}`);
  if (claims.aud !== expectedAudience) throw new Error(`Wrong audience: ${claims.aud}`);
  const now = Math.floor(Date.now() / 1000);
  if (typeof claims.exp !== "number" || claims.exp < now) throw new Error("Token expired");
  if (typeof claims.iat !== "number" || claims.iat > now + 60) throw new Error("Token issued in the future");
  if (!claims.sub || typeof claims.sub !== "string") throw new Error("Missing sub");

  return claims;
}

// ── User store (D1) ──────────────────────────────────────────────────────────

interface UserRow {
  id: string;
  apple_sub: string;
  email: string | null;
  name: string | null;
  date_of_birth: string | null;
  created_at: number;
  last_seen_at: number;
}

/** Look up a user by Apple sub; create if missing. Returns the user + whether
 *  the caller was newly registered (drives an onboarding hint in the client). */
async function upsertUserByAppleSub(
  env: Env,
  appleSub: string,
  email: string | null,
  name: string | null,
): Promise<{ user: UserRow; isNew: boolean }> {
  const existing = await env.DB.prepare(
    "SELECT id, apple_sub, email, name, date_of_birth, created_at, last_seen_at FROM users WHERE apple_sub = ?",
  ).bind(appleSub).first<UserRow>();

  const now = Date.now();
  if (existing) {
    // Refresh last_seen_at + backfill email/name if we got them and were missing.
    const nextEmail = existing.email ?? email;
    const nextName = existing.name ?? name;
    await env.DB.prepare(
      "UPDATE users SET email = ?, name = ?, last_seen_at = ? WHERE id = ?",
    ).bind(nextEmail, nextName, now, existing.id).run();
    return { user: { ...existing, email: nextEmail, name: nextName, last_seen_at: now }, isNew: false };
  }

  const id = crypto.randomUUID();
  await env.DB.prepare(
    "INSERT INTO users (id, apple_sub, email, name, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).bind(id, appleSub, email, name, now, now).run();
  return {
    user: { id, apple_sub: appleSub, email, name, date_of_birth: null, created_at: now, last_seen_at: now },
    isNew: true,
  };
}

/** Public user shape — never leaks apple_sub (Apple asks us not to expose it). */
function publicUser(u: UserRow) {
  return {
    id: u.id, email: u.email, name: u.name, dateOfBirth: u.date_of_birth,
    createdAt: u.created_at, lastSeenAt: u.last_seen_at,
  };
}

// ── Handlers ─────────────────────────────────────────────────────────────────

function handleHealth(env: Env): Response {
  return json({
    ok: true,
    service: "auctionbaby-auth",
    appleClientId: env.APPLE_CLIENT_ID,
    sessionSecretConfigured: Boolean(env.SESSION_SECRET),
    dbBound: Boolean(env.DB),
    apns: {
      configured: Boolean(env.APNS_AUTH_KEY_P8 && env.APNS_KEY_ID && env.APNS_TEAM_ID),
      keyIdConfigured: Boolean(env.APNS_KEY_ID),
      teamIdConfigured: Boolean(env.APNS_TEAM_ID),
    },
    adminGated: Boolean(env.APP_SHARED_SECRET),
  });
}

/** POST /auth/apple  { identityToken, name? }  →  { userId, sessionToken, isNew, user } */
async function handleAppleAuth(request: Request, env: Env): Promise<Response> {
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }

  const identityToken = String(body?.identityToken ?? "").trim();
  const suppliedName = body?.name != null ? String(body.name).trim().slice(0, 80) : null;
  if (!identityToken) return err("identityToken is required");
  if (!env.SESSION_SECRET) return err("Server misconfigured: SESSION_SECRET unset", 500);
  if (!env.DB) return err("Server misconfigured: D1 not bound", 500);

  let claims: AppleClaims;
  try {
    claims = await verifyAppleIdentityToken(identityToken, env.APPLE_CLIENT_ID);
  } catch (e: any) {
    return err(`Apple token rejected: ${e.message}`, 401);
  }

  const { user, isNew } = await upsertUserByAppleSub(
    env, claims.sub, claims.email ?? null, isNew_seedName(suppliedName, claims),
  );
  const ttl = Number(env.SESSION_TTL_SECONDS ?? 60 * 60 * 24 * 30);
  const sessionToken = await issueSessionToken(user.id, ttl, env.SESSION_SECRET);

  return json({
    userId: user.id,
    sessionToken,
    expiresInSeconds: ttl,
    isNew,
    user: publicUser(user),
  });
}

/** Apple only gives us the full name on the FIRST sign-in ever; the client
 *  passes it through as `name`. Prefer whatever the client supplied; fall
 *  back to nothing (never guess from the email). */
function isNew_seedName(supplied: string | null, _claims: AppleClaims): string | null {
  if (supplied && supplied.length > 0) return supplied;
  return null;
}

/** Authenticate a request. Returns the userId on success, null otherwise. */
async function authenticate(request: Request, env: Env): Promise<string | null> {
  const auth = request.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) return null;
  return verifySessionToken(auth.slice(7), env.SESSION_SECRET);
}

/** GET /me  [auth]  → the authed user */
async function handleMe(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const user = await env.DB.prepare(
    "SELECT id, apple_sub, email, name, date_of_birth, created_at, last_seen_at FROM users WHERE id = ?",
  ).bind(userId).first<UserRow>();
  if (!user) return err("User not found", 404);
  // Refresh last_seen_at on every /me hit — cheapest heartbeat we've got.
  await env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(Date.now(), userId).run();
  return json({ user: publicUser(user) });
}

/** POST /auth/logout  [auth] — client-side hint. Stateless tokens can't be
 *  server-side revoked without a revoked table; today we just refresh the
 *  last-seen. The client is expected to delete the token from Keychain. */
async function handleLogout(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  await env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(Date.now(), userId).run();
  return json({ ok: true });
}

/** DELETE /me  [auth] — hard delete for GDPR/CCPA subject-delete requests.
 *  Apple ASO 5.1.1(v): apps that let a user create an account MUST let them
 *  delete it. Slice 1 has minimal PII; later slices will cascade to their
 *  own tables here. */
async function handleDeleteMe(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId).run();
  return json({ ok: true, deleted: userId });
}

// ─────────────────────────────────────────────────────────────────────────────
// Slice 2 — Push notifications (APNs)
// ─────────────────────────────────────────────────────────────────────────────

const APNS_HOST_PROD = "https://api.push.apple.com";
const APNS_HOST_SANDBOX = "https://api.sandbox.push.apple.com";
/** APNs JWTs are valid up to 60 minutes; refresh every 50 to stay comfortably
 *  under Apple's rate limits (they 429 aggressive re-signers). */
const APNS_JWT_TTL_MS = 50 * 60 * 1000;

// ── ES256 signing (for the APNs JWT auth header) ─────────────────────────────

/** Extract the raw base64 body from a PEM block (works for both PKCS#8 and
 *  the older SEC1 EC PRIVATE KEY form; Apple ships PKCS#8). */
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "")
                  .replace(/-----END [^-]+-----/g, "")
                  .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

/** Import the .p8 as a P-256 ECDSA signing key. */
async function importApnsKey(pem: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8", pemToArrayBuffer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false, ["sign"],
  );
}

/** Module-level cache — Workers keep an isolate warm across requests, so this
 *  survives normal traffic. On a cold start we re-sign; still cheap. */
let apnsJwtCache: { jwt: string; signedAt: number; keyId: string; teamId: string } | null = null;

async function apnsJwt(env: Env): Promise<string> {
  if (!env.APNS_AUTH_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) {
    throw new Error("APNs not configured (APNS_AUTH_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID)");
  }
  if (apnsJwtCache
      && apnsJwtCache.keyId === env.APNS_KEY_ID
      && apnsJwtCache.teamId === env.APNS_TEAM_ID
      && Date.now() - apnsJwtCache.signedAt < APNS_JWT_TTL_MS) {
    return apnsJwtCache.jwt;
  }
  const header = { alg: "ES256", kid: env.APNS_KEY_ID, typ: "JWT" };
  const payload = { iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(enc.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await importApnsKey(env.APNS_AUTH_KEY_P8);
  const sigBuf = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, enc.encode(signingInput),
  );
  // WebCrypto returns raw r||s (64 bytes for P-256), which is what JWT
  // ES256 expects (unlike ASN.1/DER — that would be a common footgun).
  const sigB64 = base64UrlEncode(new Uint8Array(sigBuf));
  const jwt = `${signingInput}.${sigB64}`;
  apnsJwtCache = { jwt, signedAt: Date.now(), keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID };
  return jwt;
}

// ── APNs send + token pruning ────────────────────────────────────────────────

interface PushPayload { title: string; body: string; data?: Record<string, unknown> }

interface ApnsResult { token: string; status: number; reason?: string }

/** Send ONE push to ONE device token. Returns the raw APNs response so the
 *  caller can decide whether to prune (410 = BadDeviceToken, and 400 with
 *  reason=Unregistered means the same thing on newer APNs versions). */
async function apnsSend(
  env: Env, token: string, platform: string, jwt: string, payload: PushPayload,
): Promise<ApnsResult> {
  const host = platform === "apns_sandbox" ? APNS_HOST_SANDBOX : APNS_HOST_PROD;
  const body = {
    aps: { alert: { title: payload.title, body: payload.body }, sound: "default" },
    ...(payload.data ?? {}),
  };
  const res = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": env.APPLE_CLIENT_ID,
      "apns-push-type": "alert",
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  let reason: string | undefined;
  if (!res.ok) {
    try { reason = (await res.json() as { reason?: string }).reason; } catch {}
  }
  return { token, status: res.status, reason };
}

/** Dispatch a push to every device registered against `userId`. Prunes the
 *  DB of tokens Apple tells us are dead (410 / Unregistered / BadDeviceToken)
 *  so an old device doesn't keep getting silently retried forever. */
async function sendPushToUser(env: Env, userId: string, payload: PushPayload) {
  if (!env.DB) return { sent: 0, pruned: 0, results: [] as ApnsResult[] };
  const rows = await env.DB.prepare(
    "SELECT token, platform FROM device_tokens WHERE user_id = ?",
  ).bind(userId).all<{ token: string; platform: string }>();
  const tokens = rows.results ?? [];
  if (tokens.length === 0) return { sent: 0, pruned: 0, results: [] as ApnsResult[] };

  const jwt = await apnsJwt(env);
  const results: ApnsResult[] = [];
  const toPrune: string[] = [];
  for (const row of tokens) {
    const r = await apnsSend(env, row.token, row.platform, jwt, payload);
    results.push(r);
    // BadDeviceToken (400) and Unregistered (410) → the device unsubscribed
    // or the token was regenerated. Anything else (auth, quota, transient) we
    // leave in place — the next push will retry with a fresh JWT.
    if (r.status === 410 || (r.status === 400 && (r.reason === "BadDeviceToken" || r.reason === "Unregistered"))) {
      toPrune.push(row.token);
    }
  }
  if (toPrune.length > 0) {
    // D1 doesn't support parameterized IN(?, ?, …) reliably; do individual
    // deletes (small N — a user has ~1-3 devices) so we don't have to build
    // a dynamic SQL string.
    for (const t of toPrune) {
      await env.DB.prepare("DELETE FROM device_tokens WHERE token = ?").bind(t).run();
    }
  }
  return { sent: results.filter(r => r.status < 300).length, pruned: toPrune.length, results };
}

// ── Push handlers ────────────────────────────────────────────────────────────

/** POST /devices/register  { token, platform? }  [auth]
 *  Idempotent: upserts by primary key `token`. Re-registering the same
 *  device token under a different user quietly transfers it. */
async function handleRegisterDevice(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }

  const token = String(body?.token ?? "").trim();
  const platformIn = String(body?.platform ?? "apns").trim().toLowerCase();
  if (!token || token.length < 32 || token.length > 200) return err("token is required (hex string)");
  const platform = platformIn === "apns_sandbox" ? "apns_sandbox" : "apns";

  const now = Date.now();
  // Upsert on the primary key so this endpoint is safe to call repeatedly.
  await env.DB.prepare(
    `INSERT INTO device_tokens (token, user_id, platform, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id,
                                       platform = excluded.platform,
                                       last_seen_at = excluded.last_seen_at`,
  ).bind(token, userId, platform, now, now).run();
  return json({ ok: true });
}

/** POST /devices/unregister  { token }  [auth]
 *  Only removes tokens owned by the authed user — a leaked token can't be
 *  used to yank someone else's registration. */
async function handleUnregisterDevice(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }

  const token = String(body?.token ?? "").trim();
  if (!token) return err("token is required");
  await env.DB.prepare(
    "DELETE FROM device_tokens WHERE token = ? AND user_id = ?",
  ).bind(token, userId).run();
  return json({ ok: true });
}

/** POST /push/send  { userId, title, body, data? }  [admin]
 *  Gated by APP_SHARED_SECRET (bearer). This is the entry-point every OTHER
 *  Worker calls when it needs to notify a user (a bid arrived, a match
 *  accepted, a message came in). Same secret convention as the other
 *  Workers so ops carries one string. */
async function handleSendPush(request: Request, env: Env): Promise<Response> {
  if (!env.APP_SHARED_SECRET) return err("Server misconfigured: APP_SHARED_SECRET unset", 500);
  const auth = request.headers.get("Authorization");
  const supplied = auth?.startsWith("Bearer ") ? auth.slice(7) : (auth ?? "");
  if (!(await constantTimeEqual(supplied, env.APP_SHARED_SECRET))) return err("Unauthorized", 401);

  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const userId = String(body?.userId ?? "").trim();
  const title = String(body?.title ?? "").trim();
  const bodyText = String(body?.body ?? "").trim();
  if (!userId || !title || !bodyText) return err("userId, title, body are all required");

  try {
    const result = await sendPushToUser(env, userId, { title, body: bodyText, data: body?.data });
    return json({ ok: true, ...result });
  } catch (e: any) {
    return err(`Push send failed: ${e.message}`, 502);
  }
}

/** Constant-time string compare over SHA-256 digests so timing can't leak
 *  the admin secret. */
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  if (!a || !b) return false;
  const enc = new TextEncoder();
  const [x, y] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const xv = new Uint8Array(x), yv = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < xv.length; i++) diff |= xv[i] ^ yv[i];
  return diff === 0;
}

// ── Router ───────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const { pathname } = new URL(request.url);
    const m = request.method;

    if (pathname === "/health" && m === "GET") return handleHealth(env);
    if (pathname === "/auth/apple" && m === "POST") return handleAppleAuth(request, env);
    if (pathname === "/me" && m === "GET") return handleMe(request, env);
    if (pathname === "/me" && m === "DELETE") return handleDeleteMe(request, env);
    if (pathname === "/auth/logout" && m === "POST") return handleLogout(request, env);

    // Slice 2 — push
    if (pathname === "/devices/register" && m === "POST") return handleRegisterDevice(request, env);
    if (pathname === "/devices/unregister" && m === "POST") return handleUnregisterDevice(request, env);
    if (pathname === "/push/send" && m === "POST") return handleSendPush(request, env);

    return err("Not found", 404);
  },
};
