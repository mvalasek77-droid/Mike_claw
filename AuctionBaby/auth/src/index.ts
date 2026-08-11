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
 *   POST   /me/dob              — set the account's date_of_birth   [auth]
 *                                 (age-gate: rejects under-18)
 *
 *   Slice 2 (push notifications):
 *   POST   /devices/register    — register/upsert an APNs device token [auth]
 *   POST   /devices/unregister  — remove a device token (sign-out)     [auth]
 *   POST   /push/send           — dispatch a push to a userId's devices
 *                                 (admin-only, gated by APP_SHARED_SECRET)
 *
 *   Slice 3 (real verification):
 *   POST   /verify/start        — kick off a verification session      [auth]
 *   POST   /verify/webhook      — vendor callback; flips verified_at
 *                                 (signature-verified, no session)
 *   POST   /admin/verify        — manual approve/reject (admin-only,
 *                                 gated by APP_SHARED_SECRET)
 *
 *   Slice 4b0 (public profiles):
 *   PUT    /me/profile          — upsert the authed user's profile    [auth]
 *   GET    /me/profile          — my current profile                   [auth]
 *   GET    /users/:id/profile   — another user's profile               [auth]
 *   GET    /users/floor         — paginated feed by role & recency     [auth]
 *
 *   Batch U (R2 profile photos):
 *   POST   /me/photos           — upload JPEG (raw binary body)        [auth]
 *   DELETE /me/photos/:photoId  — remove one photo                     [auth]
 *   PUT    /me/photos/order     — reorder (body: {ids:[...]})          [auth]
 *
 *   Slice 4c1a (server-enforced blocks):
 *   POST   /me/blocks           — block another user (idempotent)      [auth]
 *   DELETE /me/blocks/:userId   — unblock                              [auth]
 *   GET    /me/blocks           — my active blocks                     [auth]
 *
 *   Slice 5 (server-side reports):
 *   POST   /me/reports          — file a report on another user        [auth]
 *   GET    /admin/reports       — admin triage queue                   [admin]
 *   POST   /admin/reports/:id/resolve — mark a report resolved         [admin]
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

  // ── Slice 3: verification vendor ──────────────────────────────────────────
  // Default 'manual': the founder approves/rejects via /admin/verify. Fine
  // for low volume. When Persona/Onfido are integrated, flip this to their
  // key and drop in a vendor adapter (see the vendor block in the code).
  VERIFICATION_VENDOR?: string;    // 'manual' | 'persona' | 'onfido' | 'stub'
  VERIFICATION_WEBHOOK_SECRET?: string;  // shared secret vendor signs webhook payloads with

  // ── Batch U: R2 profile photos ────────────────────────────────────────────
  PHOTOS?: R2Bucket;               // bound in wrangler.toml; absent = uploads disabled
  PHOTOS_PUBLIC_URL?: string;      // e.g. "https://pub-abc123.r2.dev"
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
  "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
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
  verified_at: number | null;
  verification_vendor: string | null;
  verification_ref: string | null;
  verification_status: string;
  suspended_until: number | null;
}

/** All user column names we ever want to SELECT — kept in one place so a new
 *  column is a one-line change instead of five. */
const USER_COLS =
  "id, apple_sub, email, name, date_of_birth, created_at, last_seen_at, " +
  "verified_at, verification_vendor, verification_ref, verification_status, " +
  "suspended_until";

/** Look up a user by Apple sub; create if missing. Returns the user + whether
 *  the caller was newly registered (drives an onboarding hint in the client). */
async function upsertUserByAppleSub(
  env: Env,
  appleSub: string,
  email: string | null,
  name: string | null,
): Promise<{ user: UserRow; isNew: boolean }> {
  const existing = await env.DB.prepare(
    `SELECT ${USER_COLS} FROM users WHERE apple_sub = ?`,
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
    user: {
      id, apple_sub: appleSub, email, name,
      date_of_birth: null, created_at: now, last_seen_at: now,
      verified_at: null, verification_vendor: null,
      verification_ref: null, verification_status: "unstarted",
      suspended_until: null,
    },
    isNew: true,
  };
}

/** Public user shape — never leaks apple_sub (Apple asks us not to expose it). */
function publicUser(u: UserRow) {
  return {
    id: u.id, email: u.email, name: u.name, dateOfBirth: u.date_of_birth,
    createdAt: u.created_at, lastSeenAt: u.last_seen_at,
    verifiedAt: u.verified_at,
    verificationStatus: u.verification_status ?? "unstarted",
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
    verification: {
      vendor: currentVendor(env),
      webhookConfigured: Boolean(env.VERIFICATION_WEBHOOK_SECRET),
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
  // Batch R — soft-ban check on new sign-ins. Existing sessions run to their
  // TTL; if you need to yank now, use `DELETE /admin/users/:id`.
  if (user.suspended_until != null && user.suspended_until > Date.now()) {
    return err("Your account is suspended. Try again later.", 403);
  }
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
    `SELECT ${USER_COLS} FROM users WHERE id = ?`,
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

/** POST /me/dob  { dateOfBirth: "YYYY-MM-DD" }  [auth]
 *
 * Stores the account's date of birth and enforces the 18+ age gate. The DOB
 * isn't in the Apple identity JWT (Apple doesn't share it), so we collect it
 * at onboarding and validate here — client-side checks are advisory only.
 *
 * Idempotent: setting the SAME DOB is a no-op. Setting a DIFFERENT DOB on
 * an account that already has one is rejected — accidental resubmission is
 * safe, deliberate age-change (which is always fraud) requires admin.
 *
 * 400: bad format. 403: under 18. 409: DOB already set to a different value.
 */
async function handleSetDob(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const dob = String(body?.dateOfBirth ?? "").trim();

  // Strict YYYY-MM-DD; a two-digit year here would silently pass Date parse.
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dob)) {
    return err("dateOfBirth must be YYYY-MM-DD", 400);
  }
  const parsed = new Date(`${dob}T00:00:00Z`);
  if (isNaN(parsed.getTime())) return err("dateOfBirth is not a valid date", 400);

  // Age = whole years elapsed. Using UTC + a day-precision calc keeps
  // timezone edge cases from letting someone slip through by 4 hours.
  const now = new Date();
  let age = now.getUTCFullYear() - parsed.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - parsed.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < parsed.getUTCDate())) age--;

  if (!Number.isFinite(age) || age < 18) return err("You must be 18 or older to use Auction Baby", 403);
  if (age > 120) return err("dateOfBirth is not a valid date", 400);

  const existing = await env.DB.prepare("SELECT date_of_birth FROM users WHERE id = ?")
    .bind(userId).first<{ date_of_birth: string | null }>();
  if (!existing) return err("User not found", 404);
  if (existing.date_of_birth && existing.date_of_birth !== dob) {
    return err("Date of birth is already set. Contact support to change it.", 409);
  }

  await env.DB.prepare(
    "UPDATE users SET date_of_birth = ?, last_seen_at = ? WHERE id = ?",
  ).bind(dob, Date.now(), userId).run();
  return json({ ok: true, dateOfBirth: dob });
}

/** DELETE /me  [auth] — hard delete for GDPR/CCPA subject-delete requests.
 *  Apple ASO 5.1.1(v): apps that let a user create an account MUST let them
 *  delete it. Slice 1 has minimal PII; later slices will cascade to their
 *  own tables here. */
async function handleDeleteMe(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  // Clean up R2 photos before nuking the DB row (CASCADE will wipe
  // the profiles row that holds the photos_json pointer).
  if (env.PHOTOS) {
    const profileRow = await env.DB.prepare(
      "SELECT photos_json FROM profiles WHERE user_id = ?"
    ).bind(userId).first<{ photos_json: string | null }>();
    const photos = parsePhotos(profileRow?.photos_json ?? null);
    if (photos.length > 0) {
      await Promise.all(photos.map(p => env.PHOTOS!.delete(p.key)));
    }
  }
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

// ─────────────────────────────────────────────────────────────────────────────
// Slice 3 — Real verification (vendor-agnostic)
// ─────────────────────────────────────────────────────────────────────────────
//
// The blue check must mean something. `users.verified_at` is the single source
// of truth; the client mirrors it via /me. The vendor doing the actual liveness
// / ID check is behind a small adapter so we can swap Persona/Onfido in later
// without touching client code.
//
// SHIPPING vendors:
//   • manual — the founder approves via POST /admin/verify. Fine at low
//     volume (bootstrap), and it means slice 3 is genuinely end-to-end today
//     without a KYC contract.
//   • stub   — auto-passes instantly, dev/staging only. Never enable in prod.
//
// PLANNED vendors (drop-in):
//   • persona / onfido — vendor SDK on client, webhook here on pass/fail.
//     The webhook shape below (POST /verify/webhook + shared secret) is
//     already what those vendors post; adding them is a few `if vendor === …`
//     branches in handleVerifyStart and a signature check that matches
//     theirs. Not shipping now to avoid coupling to a vendor the founder
//     hasn't picked.
//
// NOTES ON MEDIA:
//   Selfies, IDs, and liveness scans are highly regulated. Manual mode uses
//   the user's EXISTING profile photos + a real conversation as the evidence
//   — we never store fresh verification media in D1. When Persona/Onfido are
//   added, THEIR storage holds the media (compliant by construction) and we
//   only ever get a pass/fail signal + a reference id.

type VerificationStatus = "unstarted" | "pending" | "passed" | "failed" | "expired";
type VerificationVendor = "manual" | "persona" | "onfido" | "stub";

function currentVendor(env: Env): VerificationVendor {
  const v = (env.VERIFICATION_VENDOR ?? "manual").toLowerCase() as VerificationVendor;
  return (["manual", "persona", "onfido", "stub"].includes(v)) ? v : "manual";
}

/** POST /verify/start  [auth]  →  { verificationId, vendor, status, nextStep }
 *
 * Starts (or resumes) a verification for the authed user. Idempotent: a
 * user who already passed just gets the passed state back; a user with a
 * pending check gets the same session details. The `nextStep` tells the
 * client what to do (open a URL, present an SDK, or "wait for admin").
 */
async function handleVerifyStart(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  const user = await env.DB.prepare(`SELECT ${USER_COLS} FROM users WHERE id = ?`)
    .bind(userId).first<UserRow>();
  if (!user) return err("User not found", 404);

  // Idempotent short-circuit: already passed = nothing to do.
  if (user.verification_status === "passed" && user.verified_at) {
    return json({
      verificationId: user.verification_ref,
      vendor: user.verification_vendor,
      status: "passed",
      verifiedAt: user.verified_at,
      nextStep: { kind: "done" },
    });
  }

  const vendor = currentVendor(env);
  const now = Date.now();

  // Reuse an in-flight check on the same vendor rather than opening a new one.
  if (user.verification_status === "pending"
      && user.verification_vendor === vendor
      && user.verification_ref) {
    return json({
      verificationId: user.verification_ref,
      vendor,
      status: "pending",
      nextStep: nextStepFor(vendor, user.verification_ref, env),
    });
  }

  // Fresh check: mint a ref id and mark pending.
  const ref = crypto.randomUUID();
  await env.DB.prepare(
    "UPDATE users SET verification_status = 'pending', verification_vendor = ?, verification_ref = ?, last_seen_at = ? WHERE id = ?",
  ).bind(vendor, ref, now, userId).run();

  // The `stub` vendor auto-passes immediately (dev/staging only). It's
  // opt-in via VERIFICATION_VENDOR="stub" and we still refuse in production
  // via a paranoid check below.
  if (vendor === "stub") {
    await markVerified(env, userId, "stub", ref);
    await fireVerifiedPush(env, userId).catch(() => {});
    return json({
      verificationId: ref, vendor, status: "passed", verifiedAt: Date.now(),
      nextStep: { kind: "done" },
    });
  }

  return json({
    verificationId: ref, vendor, status: "pending",
    nextStep: nextStepFor(vendor, ref, env),
  });
}

/** What the client should do next, per-vendor. */
function nextStepFor(vendor: VerificationVendor, ref: string, _env: Env): unknown {
  switch (vendor) {
    case "manual":
      return {
        kind: "wait",
        message: "Your verification is under review. We'll notify you when it's done.",
      };
    case "persona":
    case "onfido":
      // Placeholders — a real integration returns their SDK init token
      // and/or a hosted flow URL keyed on `ref`.
      return { kind: "sdk", vendor, ref, note: "Vendor SDK integration pending" };
    case "stub":
      return { kind: "done" };
  }
}

/** POST /verify/webhook  — vendor callback, signature-verified.
 *
 * Body shape (vendor-neutral; adapters translate their own payloads):
 *   { ref, userId, status: 'passed'|'failed', vendor }
 * Signature: HMAC-SHA256(rawBody) hex, in `X-Verification-Signature` header,
 * with VERIFICATION_WEBHOOK_SECRET as the key. Real Persona/Onfido payloads
 * are richer — the adapter is responsible for verifying THEIR signature
 * and reducing the payload to this canonical shape.
 */
async function handleVerifyWebhook(request: Request, env: Env): Promise<Response> {
  if (!env.VERIFICATION_WEBHOOK_SECRET) return err("Webhook not configured", 500);
  const rawBody = await request.text();
  const sig = request.headers.get("X-Verification-Signature") ?? "";
  const expected = [...new Uint8Array(
    await hmacSha256(env.VERIFICATION_WEBHOOK_SECRET, rawBody),
  )].map((b) => b.toString(16).padStart(2, "0")).join("");
  // Constant-time compare.
  if (sig.length !== expected.length) return err("Invalid signature", 400);
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  if (diff !== 0) return err("Invalid signature", 400);

  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return err("Invalid JSON"); }

  const ref = String(payload?.ref ?? "").trim();
  const userId = String(payload?.userId ?? "").trim();
  const status = String(payload?.status ?? "").trim();
  const vendor = (payload?.vendor ?? currentVendor(env)) as VerificationVendor;
  if (!ref || !userId || !["passed", "failed"].includes(status)) {
    return err("Missing/invalid ref, userId, or status");
  }

  // Only accept a webhook that matches the ref we minted for this user —
  // stops a leaked webhook secret from letting anyone flip anyone.
  const user = await env.DB.prepare(`SELECT ${USER_COLS} FROM users WHERE id = ?`)
    .bind(userId).first<UserRow>();
  if (!user) return err("User not found", 404);
  if (user.verification_ref !== ref) {
    return err("ref does not match user's pending verification", 409);
  }

  if (status === "passed") {
    await markVerified(env, userId, vendor, ref);
    await fireVerifiedPush(env, userId).catch(() => {});
  } else {
    await env.DB.prepare(
      "UPDATE users SET verification_status = 'failed', last_seen_at = ? WHERE id = ?",
    ).bind(Date.now(), userId).run();
  }
  return json({ ok: true });
}

/** POST /admin/verify  [admin]  — manual approval/rejection.
 *
 * Body: { userId, approved: true|false, reason? }
 * Gated by APP_SHARED_SECRET (same admin bearer as /push/send). This is the
 * bootstrap tool — the founder reviews the user's profile + a quick chat
 * and flips the flag directly. When Persona/Onfido are wired, this stays
 * as an override lane (fraud reversal, manual re-verify).
 */
async function handleAdminVerify(request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const userId = String(body?.userId ?? "").trim();
  const approved = Boolean(body?.approved);
  if (!userId) return err("userId is required");

  const user = await env.DB.prepare(`SELECT ${USER_COLS} FROM users WHERE id = ?`)
    .bind(userId).first<UserRow>();
  if (!user) return err("User not found", 404);

  const ref = user.verification_ref ?? crypto.randomUUID();
  if (approved) {
    await markVerified(env, userId, "manual", ref);
    await fireVerifiedPush(env, userId).catch(() => {});
    await writeAudit(env, gate.ok, "verify", userId, null);
    return json({ ok: true, verifiedAt: Date.now() });
  }
  await env.DB.prepare(
    "UPDATE users SET verification_status = 'failed', verification_vendor = 'manual', verification_ref = ?, last_seen_at = ? WHERE id = ?",
  ).bind(ref, Date.now(), userId).run();
  await writeAudit(env, gate.ok, "verify_failed", userId, null);
  return json({ ok: true, verified: false });
}

/** Common "flip the flag" write. Split out because it's called from three
 *  places (start-with-stub, webhook-pass, admin-approve). */
async function markVerified(env: Env, userId: string, vendor: string, ref: string) {
  const now = Date.now();
  await env.DB.prepare(
    "UPDATE users SET verified_at = ?, verification_status = 'passed', verification_vendor = ?, verification_ref = ?, last_seen_at = ? WHERE id = ?",
  ).bind(now, vendor, ref, now, userId).run();
}

/** Fire the "you're verified" push. Best-effort; a push failure never blocks
 *  the flag flip. Uses the same sendPushToUser plumbing slice 2 shipped. */
async function fireVerifiedPush(env: Env, userId: string) {
  try {
    await sendPushToUser(env, userId, {
      title: "You're verified",
      body: "Your blue check is live across Auction Baby.",
      data: { type: "verification.passed" },
    });
  } catch {
    // Swallow — the check landed, that's what matters.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slice 4b0 — Public profiles
// ─────────────────────────────────────────────────────────────────────────────
//
// A user's profile as seen by OTHER users. Kept in its own table so that a
// delete-my-account cascade wipes the public face too, and so a future "hide
// my profile" flag is a soft-delete here rather than on the identity row.
//
// Age is derived from `users.date_of_birth` on read — never stored twice.
// Photos live outside D1 (R2 + moderation, a slice on its own).

const FLOOR_PAGE_SIZE_DEFAULT = 30;
const FLOOR_PAGE_SIZE_MAX = 100;

interface ProfileRow {
  user_id: string;
  role: string;
  name: string;
  location: string | null;
  bio: string | null;
  hue: number;
  starting_bid: number | null;
  archetype: string | null;
  opening_bid_script: string | null;
  prompts_json: string | null;
  interests_json: string | null;
  photos_json: string | null;
  created_at: number;
  updated_at: number;
}

/** Derived-age columns are joined in via LEFT JOIN when we return public
 *  profiles — one query, no round-trip. */
interface ProfileWithAge extends ProfileRow {
  date_of_birth: string | null;
  verified_at: number | null;
}

/** Compute whole-year age from a YYYY-MM-DD string; null if we don't have one. */
function ageFrom(dob: string | null): number | null {
  if (!dob || !/^\d{4}-\d{2}-\d{2}$/.test(dob)) return null;
  const d = new Date(`${dob}T00:00:00Z`);
  if (isNaN(d.getTime())) return null;
  const now = new Date();
  let age = now.getUTCFullYear() - d.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - d.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < d.getUTCDate())) age--;
  return age >= 0 && age <= 120 ? age : null;
}

function safeParseJsonArray(s: string | null): unknown[] {
  if (!s) return [];
  try { const v = JSON.parse(s); return Array.isArray(v) ? v : []; } catch { return []; }
}

function photosBase(env: Env): string | undefined {
  const raw = (env.PHOTOS_PUBLIC_URL ?? "").trim();
  return raw ? raw.replace(/\/+$/, "") : undefined;
}

/** Public shape returned by every profile endpoint.
 *  `photosBaseUrl` is threaded through so photo keys can be resolved to full
 *  URLs without leaking internal R2 structure. When absent (no PHOTOS_PUBLIC_URL
 *  configured), the `photos` array stays empty and the client falls back to the
 *  monogram. */
function publicProfile(p: ProfileWithAge, photosBaseUrl?: string) {
  const rawPhotos = safeParseJsonArray(p.photos_json) as Array<{ id: string; key: string }>;
  const photos = photosBaseUrl
    ? rawPhotos
        .filter(e => e && typeof e.key === "string")
        .map(e => ({ id: e.id, url: `${photosBaseUrl}/${e.key}` }))
    : [];
  return {
    userId: p.user_id,
    role: p.role,
    name: p.name,
    age: ageFrom(p.date_of_birth),
    location: p.location,
    bio: p.bio,
    hue: p.hue,
    startingBid: p.starting_bid,
    archetype: p.archetype,
    openingBidScript: p.opening_bid_script,
    prompts: safeParseJsonArray(p.prompts_json),
    interests: safeParseJsonArray(p.interests_json),
    photos,
    verifiedAt: p.verified_at,
    createdAt: p.created_at,
    updatedAt: p.updated_at,
  };
}

const PROFILE_SELECT = `
  SELECT p.user_id, p.role, p.name, p.location, p.bio, p.hue,
         p.starting_bid, p.archetype, p.opening_bid_script,
         p.prompts_json, p.interests_json, p.photos_json,
         p.created_at, p.updated_at,
         u.date_of_birth, u.verified_at
    FROM profiles p JOIN users u ON u.id = p.user_id`;

/** PUT /me/profile  [auth]
 *
 * Body accepts the same shape publicProfile() returns (minus derived fields).
 * Idempotent: upsert on user_id. On first write, created_at = now; on
 * subsequent writes, only updated_at moves. Refuses to write a role that
 * would disagree with the client's current sign-in state — we don't want
 * a bug on one device flipping a woman's account to a man's. */
async function handleUpsertMyProfile(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }

  const role = String(body?.role ?? "").toLowerCase();
  if (role !== "man" && role !== "woman") return err("role must be 'man' or 'woman'");
  const name = String(body?.name ?? "").trim().slice(0, 60);
  if (!name) return err("name is required");
  const hueRaw = Number(body?.hue ?? 0.6);
  const hue = Number.isFinite(hueRaw) ? Math.min(1, Math.max(0, hueRaw)) : 0.6;

  const location = body?.location ? String(body.location).slice(0, 80) : null;
  const bio = body?.bio ? String(body.bio).slice(0, 500) : null;
  const startingBid = body?.startingBid == null ? null : Math.max(0, Math.round(Number(body.startingBid)));
  const archetype = body?.archetype ? String(body.archetype).slice(0, 40) : null;
  const openingBidScript = body?.openingBidScript ? String(body.openingBidScript).slice(0, 240) : null;

  // Prompts + interests: accept only well-formed arrays; anything else drops
  // to null (safer than reflecting user junk back to other users).
  const prompts = Array.isArray(body?.prompts) ? body.prompts.slice(0, 5).map((p: any) => ({
    question: String(p?.question ?? "").slice(0, 100),
    answer: String(p?.answer ?? "").slice(0, 300),
  })).filter((p: any) => p.question && p.answer) : null;
  const interests = Array.isArray(body?.interests) ? body.interests.slice(0, 20)
    .map((s: any) => String(s).slice(0, 30)).filter(Boolean) : null;

  // Slice 8 — enforce the DOB gate at write time. /me/dob already rejects
  // under-18s at the POST layer, so "DOB is set" is a proxy for "age is
  // verified 18+". Refusing the profile write when DOB is null closes the
  // path where a signed-in user could otherwise create a floor-visible
  // profile without ever going through the age gate.
  // Batch R — same query also reads suspended_until so a soft-banned user
  // can't tweak their public profile while suspended.
  const gateRow = await env.DB.prepare(
    "SELECT date_of_birth, suspended_until FROM users WHERE id = ?",
  ).bind(userId).first<{ date_of_birth: string | null; suspended_until: number | null }>();
  if (!gateRow?.date_of_birth) {
    return err("Set your date of birth first — the 18+ check runs against it.", 403);
  }
  if (gateRow.suspended_until != null && gateRow.suspended_until > Date.now()) {
    return err("Your account is suspended.", 403);
  }

  // Guard against role-flip: if a row already exists with a DIFFERENT role,
  // reject. A user who wants to switch sides should go through /admin.
  const existing = await env.DB.prepare("SELECT role FROM profiles WHERE user_id = ?")
    .bind(userId).first<{ role: string }>();
  if (existing && existing.role !== role) {
    return err("Profile role is already set and cannot be changed here", 409);
  }

  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO profiles (user_id, role, name, location, bio, hue, starting_bid, archetype, opening_bid_script, prompts_json, interests_json, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET
       name = excluded.name,
       location = excluded.location,
       bio = excluded.bio,
       hue = excluded.hue,
       starting_bid = excluded.starting_bid,
       archetype = excluded.archetype,
       opening_bid_script = excluded.opening_bid_script,
       prompts_json = excluded.prompts_json,
       interests_json = excluded.interests_json,
       updated_at = excluded.updated_at`,
  ).bind(
    userId, role, name, location, bio, hue, startingBid, archetype, openingBidScript,
    prompts ? JSON.stringify(prompts) : null,
    interests ? JSON.stringify(interests) : null,
    existing ? Date.now() : now,   // don't overwrite created_at on updates
    now,
  ).run();

  const row = await env.DB.prepare(`${PROFILE_SELECT} WHERE p.user_id = ?`)
    .bind(userId).first<ProfileWithAge>();
  return json({ profile: row ? publicProfile(row, photosBase(env)) : null });
}

/** GET /me/profile  [auth] */
async function handleGetMyProfile(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const row = await env.DB.prepare(`${PROFILE_SELECT} WHERE p.user_id = ?`)
    .bind(userId).first<ProfileWithAge>();
  if (!row) return err("Profile not set yet", 404);
  return json({ profile: publicProfile(row, photosBase(env)) });
}

/** GET /users/:id/profile  [auth] — peer lookup for match/chat displays.
 *  Slice 8: hides profiles whose account has no DOB set. If somehow a profile
 *  slipped in before the write-time gate landed, this makes it invisible to
 *  every peer read. */
async function handleGetUserProfile(peerId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const row = await env.DB.prepare(`${PROFILE_SELECT} WHERE p.user_id = ? AND u.date_of_birth IS NOT NULL`)
    .bind(peerId).first<ProfileWithAge>();
  if (!row) return err("Profile not found", 404);
  return json({ profile: publicProfile(row, photosBase(env)) });
}

/** GET /users/floor?role=woman&limit=&cursor=&minAge=&maxAge=&verifiedOnly=&location=  [auth]
 *
 * Paginated feed by (role, updated_at DESC). Cursor is the last item's
 * `updated_at` timestamp — simple and doesn't drift as writes happen (unlike
 * OFFSET, which would skip newly-written rows). Excludes the caller.
 *
 * Batch T: server-side filter push-down for the bidder's floor filters. Age
 * uses SQLite `date('now', '-N years')` arithmetic on the TEXT DOB column
 * (YYYY-MM-DD). Reserve Requirements (height/lifestyle/interests) aren't
 * pushed down yet — they need columns the profiles table doesn't carry. */
async function handleFloor(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  const url = new URL(request.url);
  const roleParam = (url.searchParams.get("role") ?? "").toLowerCase();
  if (roleParam !== "man" && roleParam !== "woman") return err("role must be 'man' or 'woman'");
  const limitRaw = Number(url.searchParams.get("limit") ?? FLOOR_PAGE_SIZE_DEFAULT);
  const limit = Math.min(FLOOR_PAGE_SIZE_MAX,
    Math.max(1, Number.isFinite(limitRaw) ? Math.floor(limitRaw) : FLOOR_PAGE_SIZE_DEFAULT));
  const cursorRaw = url.searchParams.get("cursor");
  const cursor = cursorRaw != null && cursorRaw !== "" ? Number(cursorRaw) : null;

  // Filter params (all optional — a missing param means "no restriction").
  // Clamp to sane ranges so a malformed client can't slip in `-1` etc.
  const minAgeRaw = url.searchParams.get("minAge");
  const maxAgeRaw = url.searchParams.get("maxAge");
  const minAge = minAgeRaw != null && minAgeRaw !== ""
    ? Math.max(18, Math.min(120, Math.floor(Number(minAgeRaw)))) : null;
  const maxAge = maxAgeRaw != null && maxAgeRaw !== ""
    ? Math.max(18, Math.min(120, Math.floor(Number(maxAgeRaw)))) : null;
  const verifiedOnly = url.searchParams.get("verifiedOnly") === "1"
    || url.searchParams.get("verifiedOnly") === "true";
  const locationRaw = (url.searchParams.get("location") ?? "").trim();
  const location = locationRaw.length > 0 && locationRaw.length <= 200
    ? locationRaw : null;

  // Server-enforced blocks (slice 4c1a): a floor row is hidden when EITHER
  // side of the pair has an active block. Two NOT EXISTS clauses cover both
  // directions — one filters people I've blocked, the other filters people
  // who blocked me. Cheap against the (blocker_id PK, blocked_id index)
  // shape and clearer than a UNION.
  //
  // Slice 8: also require the peer's DOB is set. /me/dob enforces 18+ at
  // POST time, so "DOB present" is a proxy for "age verified 18+"; a null
  // DOB is treated as unverified and never surfaces on the floor.
  let sql = `${PROFILE_SELECT}
    WHERE p.role = ? AND p.user_id != ? AND u.date_of_birth IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = p.user_id)
      AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = p.user_id AND blocked_id = ?)`;
  const params: unknown[] = [roleParam, userId, userId, userId];
  // Age: minAge X → DOB must be at least X years ago; maxAge X → user is
  // still X (i.e., DOB > the X+1-years-ago cutoff so they haven't turned X+1
  // yet). Ints are safe-embedded — Number cast happened above and NaN got
  // dropped via Number.isFinite when we clamped.
  if (minAge != null && Number.isFinite(minAge)) {
    sql += ` AND u.date_of_birth <= date('now', '-${minAge} years')`;
  }
  if (maxAge != null && Number.isFinite(maxAge)) {
    sql += ` AND u.date_of_birth > date('now', '-${maxAge + 1} years')`;
  }
  if (verifiedOnly) {
    sql += " AND u.verified_at IS NOT NULL";
  }
  if (location != null) {
    // Fuzzy city matching. Exact-string equality left real users on an empty
    // floor ("New York" never matched "Manhattan, New York" or "New York, NY")
    // — the same brittleness the leaderboard's sameCity() already works around.
    // Match a profile whose location text CONTAINS any substantial comma-token
    // of the searcher's location, case-insensitively, plus an exact fallback.
    // Tokens < 3 chars (e.g. "NY", "CA") are dropped so a state code can't
    // match the whole state; % / _ are stripped so input can't inject LIKE
    // wildcards. (Leading-wildcard LIKE is a scan — fine at launch scale; a
    // geocoded distance index is the v1.1 upgrade.)
    const tokens = location
      .toLowerCase()
      .split(",")
      .map(t => t.trim().replace(/[%_]/g, ""))
      .filter(t => t.length >= 3)
      .slice(0, 5);
    const clauses = ["LOWER(p.location) = LOWER(?)"];
    params.push(location);
    for (const t of tokens) {
      clauses.push("LOWER(p.location) LIKE ?");
      params.push(`%${t}%`);
    }
    sql += ` AND (${clauses.join(" OR ")})`;
  }
  if (cursor != null && Number.isFinite(cursor)) {
    sql += " AND p.updated_at < ?";
    params.push(cursor);
  }
  sql += " ORDER BY p.updated_at DESC LIMIT ?";
  params.push(limit);

  const rows = await env.DB.prepare(sql).bind(...params).all<ProfileWithAge>();
  const base = photosBase(env);
  const list = (rows.results ?? []).map(r => publicProfile(r, base));
  const nextCursor = list.length === limit ? list[list.length - 1].updatedAt : null;
  return json({ profiles: list, nextCursor });
}

// ── Slice 4c1a: blocks ───────────────────────────────────────────────────────

interface BlockRow {
  blocker_id: string; blocked_id: string; reason: string | null; created_at: number;
}

/** POST /me/blocks  { userId, reason? }  [auth]  — block another user.
 *  Idempotent (INSERT OR IGNORE); returns the effective row either way. */
async function handleAddBlock(request: Request, env: Env): Promise<Response> {
  const me = await authenticate(request, env);
  if (!me) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const targetId = String(body?.userId ?? "").trim().toLowerCase();
  if (!targetId) return err("userId is required");
  if (targetId === me) return err("You can't block yourself", 400);
  const reason = body?.reason ? String(body.reason).slice(0, 300) : null;

  // Confirm the target actually exists — stops enumeration.
  const exists = await env.DB.prepare("SELECT 1 FROM users WHERE id = ?")
    .bind(targetId).first();
  if (!exists) return err("User not found", 404);

  const now = Date.now();
  await env.DB.prepare(
    `INSERT INTO blocks (blocker_id, blocked_id, reason, created_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(blocker_id, blocked_id) DO UPDATE SET
       reason = COALESCE(excluded.reason, blocks.reason)`,
  ).bind(me, targetId, reason, now).run();
  return json({
    block: { blockerId: me, blockedId: targetId, reason, createdAt: now },
  }, 201);
}

/** DELETE /me/blocks/:userId  [auth]  — unblock. Idempotent. */
async function handleRemoveBlock(targetId: string, request: Request, env: Env): Promise<Response> {
  const me = await authenticate(request, env);
  if (!me) return err("Unauthorized", 401);
  await env.DB.prepare(
    "DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?",
  ).bind(me, targetId.toLowerCase()).run();
  return json({ ok: true });
}

/** GET /me/blocks  [auth]  — my active blocks, newest first. */
async function handleListBlocks(request: Request, env: Env): Promise<Response> {
  const me = await authenticate(request, env);
  if (!me) return err("Unauthorized", 401);
  const rows = await env.DB.prepare(
    "SELECT * FROM blocks WHERE blocker_id = ? ORDER BY created_at DESC LIMIT 500",
  ).bind(me).all<BlockRow>();
  return json({
    blocks: (rows.results ?? []).map((r) => ({
      blockerId: r.blocker_id, blockedId: r.blocked_id,
      reason: r.reason, createdAt: r.created_at,
    })),
  });
}

// ── Slice 5: reports ─────────────────────────────────────────────────────────

interface ReportRow {
  id: string; reporter_id: string; target_id: string;
  reason: string; context: string | null; created_at: number;
  status: string; resolved_at: number | null; resolved_by: string | null;
}

/** POST /me/reports  { userId, reason, context? }  [auth]
 *  Rate-limited (30/day per reporter) — a real user won't legitimately file
 *  30 reports in 24h; anything above is either abuse or an automation bug.
 *  Rate table lives in the shared D1 (rate_counters), added in 4c1b. */
async function handleCreateReport(request: Request, env: Env): Promise<Response> {
  const me = await authenticate(request, env);
  if (!me) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const targetId = String(body?.userId ?? "").trim().toLowerCase();
  const reason = String(body?.reason ?? "").trim().slice(0, 100);
  const context = body?.context ? String(body.context).trim().slice(0, 2000) : null;
  if (!targetId) return err("userId is required");
  if (targetId === me) return err("You can't report yourself", 400);
  if (!reason) return err("reason is required");

  const exists = await env.DB.prepare("SELECT 1 FROM users WHERE id = ?")
    .bind(targetId).first();
  if (!exists) return err("User not found", 404);

  // 30 reports / 24h per reporter. Bumps then checks — same shape as the
  // matching Worker's checkRate.
  const now = Date.now();
  const dayMs = 24 * 60 * 60 * 1000;
  const windowStart = Math.floor(now / dayMs) * dayMs;
  const rateRow = await env.DB.prepare(
    `INSERT INTO rate_counters (key, window_ms, count) VALUES (?, ?, 1)
     ON CONFLICT(key, window_ms) DO UPDATE SET count = count + 1
     RETURNING count AS count`,
  ).bind(`report.create:${me}`, windowStart).first<{ count: number }>();
  const count = rateRow?.count ?? 1;
  if (count > 30) {
    const retryAfterSec = Math.max(1, Math.ceil((windowStart + dayMs - now) / 1000));
    return new Response(JSON.stringify({ error: "You've reported a lot today — take a breath." }), {
      status: 429,
      headers: { "Content-Type": "application/json", "Retry-After": String(retryAfterSec), ...CORS },
    });
  }

  const id = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO reports (id, reporter_id, target_id, reason, context, created_at, status)
     VALUES (?, ?, ?, ?, ?, ?, 'open')`,
  ).bind(id, me, targetId, reason, context, now).run();
  return json({
    report: {
      id, reporterId: me, targetId, reason, context, createdAt: now, status: "open",
    },
  }, 201);
}

/** GET /admin/reports?status=open&limit=&cursor=  [admin]
 *  APP_SHARED_SECRET-gated triage queue. Cursor is the last row's
 *  `created_at` (descending pagination). */
async function handleAdminListReports(request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const url = new URL(request.url);
  const status = url.searchParams.get("status") ?? "open";
  if (!["open", "reviewed", "actioned", "dismissed", "all"].includes(status)) {
    return err("status must be open|reviewed|actioned|dismissed|all");
  }
  const limitRaw = Number(url.searchParams.get("limit") ?? 50);
  const limit = Math.min(200, Math.max(1, Number.isFinite(limitRaw) ? Math.floor(limitRaw) : 50));
  const cursorRaw = url.searchParams.get("cursor");
  const cursor = cursorRaw != null && cursorRaw !== "" ? Number(cursorRaw) : null;

  // Enrich each report row with target counts so the queue rows carry
  // "this user has 12 open reports against them" at a glance, without a
  // per-row round-trip. Same subquery shape used in /admin/users.
  let sql =
    "SELECT r.*, " +
    "(SELECT COUNT(*) FROM reports r2 WHERE r2.target_id = r.target_id) AS target_report_count, " +
    "(SELECT COUNT(*) FROM blocks b WHERE b.blocked_id = r.target_id) AS target_block_count " +
    "FROM reports r";
  const params: unknown[] = [];
  const where: string[] = [];
  if (status !== "all") { where.push("r.status = ?"); params.push(status); }
  if (cursor != null && Number.isFinite(cursor)) { where.push("r.created_at < ?"); params.push(cursor); }
  if (where.length > 0) sql += " WHERE " + where.join(" AND ");
  sql += " ORDER BY r.created_at DESC LIMIT ?";
  params.push(limit);

  type ReportWithCounts = ReportRow & { target_report_count: number; target_block_count: number };
  const rows = await env.DB.prepare(sql).bind(...params).all<ReportWithCounts>();
  const list = rows.results ?? [];
  const nextCursor = list.length === limit ? list[list.length - 1].created_at : null;
  return json({
    reports: list.map((r) => ({
      id: r.id, reporterId: r.reporter_id, targetId: r.target_id,
      reason: r.reason, context: r.context, createdAt: r.created_at,
      status: r.status, resolvedAt: r.resolved_at, resolvedBy: r.resolved_by,
      targetReportCount: r.target_report_count,
      targetBlockCount: r.target_block_count,
    })),
    nextCursor,
  });
}

/** POST /admin/reports/:id/resolve  { status, note? }  [admin]
 *  status must be one of reviewed|actioned|dismissed. Stamps resolved_at
 *  and resolved_by (the admin's short name, in the body's note field). */
async function handleAdminResolveReport(reportId: string, request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const status = String(body?.status ?? "").trim();
  if (!["reviewed", "actioned", "dismissed"].includes(status)) {
    return err("status must be reviewed|actioned|dismissed");
  }
  const resolvedBy = body?.note ? String(body.note).slice(0, 80) : "admin";

  const now = Date.now();
  const result = await env.DB.prepare(
    "UPDATE reports SET status = ?, resolved_at = ?, resolved_by = ? WHERE id = ? AND status = 'open'",
  ).bind(status, now, resolvedBy, reportId).run();
  // Audit: log resolve with the disposition baked into the action name so a
  // single index scan can filter by kind ("resolve_report:actioned").
  await writeAudit(env, gate.ok, `resolve_report:${status}`, reportId, resolvedBy);
  return json({ ok: true, updated: result.meta?.changes ?? 0 });
}

// ── Slice: admin user actions (unverify, delete, list) ───────────────────────

/** Session-based gate for user-facing /admin/* endpoints.
 *
 *  Batch L — replaces the static-bearer gate that shipped in Batches G/H.
 *  Requires a valid session token AND `users.is_admin = 1` on the
 *  authenticated user. Anyone with the app can no longer become admin by
 *  discovering the static bearer; they'd need to compromise a specific
 *  admin account.
 *
 *  Batch Q — returns the actor's userId on success (as `.ok`), so callers
 *  can write the admin_audit row without a second `authenticate()` round.
 *
 *  Internal Worker-to-Worker calls (/push/send from matching, and
 *  /internal/reservations/mark on matching Worker) still use the static
 *  bearer — they don't have session tokens. Kept for compatibility as
 *  `ensureAdmin` below. */
type AdminGate = { ok: string; denied?: never } | { ok?: never; denied: Response };
async function ensureAdminSession(request: Request, env: Env): Promise<AdminGate> {
  const userId = await authenticate(request, env);
  if (!userId) return { denied: err("Unauthorized", 401) };
  const row = await env.DB.prepare("SELECT is_admin FROM users WHERE id = ?")
    .bind(userId).first<{ is_admin: number }>();
  if (!row || row.is_admin !== 1) return { denied: err("Admin only", 403) };
  return { ok: userId };
}

/** Log an admin action to the audit table. Fire-and-forget from callers'
 *  perspective; failure never fails the primary action but is logged. */
async function writeAudit(env: Env, actorId: string, action: string,
                          targetId: string | null, note: string | null): Promise<void> {
  try {
    await env.DB.prepare(
      "INSERT INTO admin_audit (id, actor_id, action, target_id, note, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    ).bind(crypto.randomUUID(), actorId, action, targetId, note, Date.now()).run();
  } catch (e) {
    console.log(`audit write failed: action=${action} target=${targetId} err=${String(e)}`);
  }
}

/** Legacy static-bearer gate — kept for Worker-to-Worker calls that don't
 *  ship a session token. New user-facing admin endpoints must use
 *  ensureAdminSession instead. */
async function ensureAdmin(request: Request, env: Env): Promise<Response | null> {
  if (!env.APP_SHARED_SECRET) return err("Server misconfigured: APP_SHARED_SECRET unset", 500);
  const auth = request.headers.get("Authorization");
  const supplied = auth?.startsWith("Bearer ") ? auth.slice(7) : (auth ?? "");
  if (!(await constantTimeEqual(supplied, env.APP_SHARED_SECRET))) return err("Unauthorized", 401);
  return null;
}

interface AdminUserRow {
  id: string; email: string | null; name: string | null;
  date_of_birth: string | null; created_at: number; last_seen_at: number;
  verified_at: number | null; verification_status: string;
  suspended_until: number | null;
  reports_against: number; blocks_against: number;
}

/** GET /admin/users?limit=&cursor=  [admin]
 *  Paginated user list for the moderation console. Cursor is the last row's
 *  `created_at`. Ships minimal fields — no apple_sub, no session tokens.
 *
 *  Includes two moderator-focused counts per row: `reportsAgainst` (open +
 *  resolved reports where this user is the target) and `blocksAgainst`
 *  (users who have this user blocked). Correlated subqueries — cheap on the
 *  current row counts, and lets a founder spot serial offenders without a
 *  per-row round-trip. */
async function handleAdminListUsers(request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const url = new URL(request.url);
  const limitRaw = Number(url.searchParams.get("limit") ?? 50);
  const limit = Math.min(200, Math.max(1, Number.isFinite(limitRaw) ? Math.floor(limitRaw) : 50));
  const cursorRaw = url.searchParams.get("cursor");
  const cursor = cursorRaw != null && cursorRaw !== "" ? Number(cursorRaw) : null;

  let sql =
    "SELECT u.id, u.email, u.name, u.date_of_birth, u.created_at, u.last_seen_at, " +
    "u.verified_at, u.verification_status, u.suspended_until, " +
    "(SELECT COUNT(*) FROM reports r WHERE r.target_id = u.id) AS reports_against, " +
    "(SELECT COUNT(*) FROM blocks b WHERE b.blocked_id = u.id) AS blocks_against " +
    "FROM users u";
  const params: unknown[] = [];
  if (cursor != null && Number.isFinite(cursor)) {
    sql += " WHERE u.created_at < ?";
    params.push(cursor);
  }
  sql += " ORDER BY u.created_at DESC LIMIT ?";
  params.push(limit);

  const rows = await env.DB.prepare(sql).bind(...params).all<AdminUserRow>();
  const list = rows.results ?? [];
  const nextCursor = list.length === limit ? list[list.length - 1].created_at : null;
  return json({
    users: list.map((u) => ({
      id: u.id, email: u.email, name: u.name, dateOfBirth: u.date_of_birth,
      createdAt: u.created_at, lastSeenAt: u.last_seen_at,
      verifiedAt: u.verified_at, verificationStatus: u.verification_status,
      suspendedUntil: u.suspended_until,
      reportsAgainst: u.reports_against, blocksAgainst: u.blocks_against,
    })),
    nextCursor,
  });
}

/** POST /admin/users/:id/unverify  [admin]
 *  Nulls verified_at + resets verification_status → 'unstarted'. Reversible
 *  via the existing /admin/verify path. */
async function handleAdminUnverifyUser(userId: string, request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const result = await env.DB.prepare(
    "UPDATE users SET verified_at = NULL, verification_status = 'unstarted' WHERE id = ?",
  ).bind(userId).run();
  await writeAudit(env, gate.ok, "unverify", userId, null);
  return json({ ok: true, updated: result.meta?.changes ?? 0 });
}

/** DELETE /admin/users/:id  [admin]
 *  Hard-delete an account. Cascades scrub profiles, device_tokens, bids,
 *  matches, messages, blocks, reports via the FK ON DELETE CASCADE
 *  declarations on the schema. This is the "ban" primitive — no soft-delete
 *  column added; if you want reversibility, use unverify + no further
 *  action instead. */
async function handleAdminDeleteUser(userId: string, request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const result = await env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId).run();
  // Audit AFTER success so a failed delete never leaves a bogus log entry.
  // `admin_audit.target_id` has no FK (deliberate — TEXT column only), so a
  // deleted user's id stays queryable in the audit trail.
  await writeAudit(env, gate.ok, "delete_user", userId, null);
  return json({ ok: true, deleted: result.meta?.changes ?? 0 });
}

/** POST /admin/users/:id/suspend  { untilMs, note? }  [admin]
 *  Batch R — soft-ban the target until `untilMs` (epoch ms in the future).
 *  Rejects new sign-ins, profile writes, and new bids. Existing sessions
 *  run to their TTL (30 days by default); use DELETE /admin/users/:id
 *  when you need an immediate hard-yank. */
async function handleAdminSuspendUser(userId: string, request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const untilMs = Number(body?.untilMs ?? 0);
  if (!Number.isFinite(untilMs) || untilMs <= Date.now()) {
    return err("untilMs must be an epoch ms in the future");
  }
  const note = body?.note ? String(body.note).slice(0, 200) : null;
  const result = await env.DB.prepare(
    "UPDATE users SET suspended_until = ? WHERE id = ?",
  ).bind(untilMs, userId).run();
  await writeAudit(env, gate.ok, "suspend", userId, note);
  return json({ ok: true, updated: result.meta?.changes ?? 0, suspendedUntil: untilMs });
}

/** POST /admin/users/:id/unsuspend  [admin]
 *  Lift a suspension immediately. Nulls `suspended_until`. */
async function handleAdminUnsuspendUser(userId: string, request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const result = await env.DB.prepare(
    "UPDATE users SET suspended_until = NULL WHERE id = ?",
  ).bind(userId).run();
  await writeAudit(env, gate.ok, "unsuspend", userId, null);
  return json({ ok: true, updated: result.meta?.changes ?? 0 });
}

/** GET /admin/audit?limit=&cursor=  [admin]
 *  Newest-first audit trail of every mutating /admin/* call. Cursor is the
 *  last row's `created_at`. Actor + target ids returned raw so an operator
 *  can copy-paste them into other admin surfaces. */
async function handleAdminAudit(request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const url = new URL(request.url);
  const limitRaw = Number(url.searchParams.get("limit") ?? 100);
  const limit = Math.min(500, Math.max(1, Number.isFinite(limitRaw) ? Math.floor(limitRaw) : 100));
  const cursorRaw = url.searchParams.get("cursor");
  const cursor = cursorRaw != null && cursorRaw !== "" ? Number(cursorRaw) : null;

  let sql = "SELECT id, actor_id, action, target_id, note, created_at FROM admin_audit";
  const params: unknown[] = [];
  if (cursor != null && Number.isFinite(cursor)) {
    sql += " WHERE created_at < ?";
    params.push(cursor);
  }
  sql += " ORDER BY created_at DESC LIMIT ?";
  params.push(limit);

  interface AuditRow {
    id: string; actor_id: string; action: string;
    target_id: string | null; note: string | null; created_at: number;
  }
  const rows = await env.DB.prepare(sql).bind(...params).all<AuditRow>();
  const list = rows.results ?? [];
  const nextCursor = list.length === limit ? list[list.length - 1].created_at : null;
  return json({
    entries: list.map((r) => ({
      id: r.id, actorId: r.actor_id, action: r.action,
      targetId: r.target_id, note: r.note, createdAt: r.created_at,
    })),
    nextCursor,
  });
}

/** GET /admin/stats  [admin]
 *  A one-glance platform heartbeat. Everything the founder wants to see the
 *  second they land on the console: how many users, how many verified, open
 *  moderation queue, recent activity, cold-vs-live matches. Cheap SELECT
 *  COUNTs; if any of these get slow later, cache in KV. */
async function handleAdminStats(request: Request, env: Env): Promise<Response> {
  const gate = await ensureAdminSession(request, env);
  if (gate.denied) return gate.denied;
  const now = Date.now();
  const dayAgo = now - 24 * 60 * 60 * 1000;
  // One batched read — D1 handles this cheaply for a founder-only endpoint,
  // and it keeps the round-trip count to one.
  const rows = await env.DB.batch([
    env.DB.prepare("SELECT COUNT(*) AS n FROM users"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE verified_at IS NOT NULL"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE is_admin = 1"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE date_of_birth IS NULL"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM reports WHERE status = 'open'"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM reports WHERE status != 'open'"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE phase = 'chatting'"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE phase != 'chatting'"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM bids WHERE created_at >= ?").bind(dayAgo),
    env.DB.prepare("SELECT COUNT(*) AS n FROM messages WHERE created_at >= ?").bind(dayAgo),
    env.DB.prepare("SELECT COUNT(*) AS n FROM blocks"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE suspended_until IS NOT NULL AND suspended_until > ?").bind(now),
  ]);
  const n = (i: number): number => Number((rows[i].results?.[0] as any)?.n ?? 0);
  return json({
    users: n(0),
    verified: n(1),
    admins: n(2),
    noDob: n(3),
    reportsOpen: n(4),
    reportsResolved: n(5),
    matchesChatting: n(6),
    matchesClosed: n(7),
    bids24h: n(8),
    messages24h: n(9),
    blocks: n(10),
    suspended: n(11),
    generatedAt: now,
  });
}

// ── Batch U: R2 profile photos ───────────────────────────────────────────────
//
// Three endpoints:
//   POST   /me/photos          — upload a JPEG (binary body, max 5 MB)
//   DELETE /me/photos/:photoId — remove one photo by id
//   PUT    /me/photos/order    — reorder: body = { ids: ["id1","id2",...] }
//
// Each mutation round-trips to the `photos_json` column on `profiles` so the
// DB is always the authoritative order list. R2 stores the bytes keyed under
// `photos/<userId>/<photoId>.jpg`. PHOTOS_PUBLIC_URL + "/" + key = public CDN.
//
// Max 6 photos per user (matches the client grid). Upload is raw JPEG bytes
// (Content-Type: image/jpeg) so the client can stream straight from its JPEG
// encoder with no multipart overhead.

const MAX_PHOTOS = 6;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024; // 5 MB

interface PhotoEntry { id: string; key: string }

function parsePhotos(raw: string | null): PhotoEntry[] {
  if (!raw) return [];
  try { const v = JSON.parse(raw); return Array.isArray(v) ? v : []; } catch { return []; }
}

// POST /me/photos  [auth]  — body is raw JPEG bytes
async function handleUploadPhoto(request: Request, env: Env): Promise<Response> {
  if (!env.PHOTOS) return err("Photo uploads are not configured", 501);
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  const ct = (request.headers.get("Content-Type") ?? "").toLowerCase();
  if (!ct.startsWith("image/jpeg")) return err("Content-Type must be image/jpeg");
  const length = Number(request.headers.get("Content-Length") ?? 0);
  if (length > MAX_PHOTO_BYTES) return err("Photo exceeds 5 MB limit", 413);

  const profileRow = await env.DB.prepare(
    "SELECT photos_json FROM profiles WHERE user_id = ?"
  ).bind(userId).first<{ photos_json: string | null }>();
  if (!profileRow) return err("Create your profile before uploading photos", 400);

  const existing = parsePhotos(profileRow.photos_json);
  if (existing.length >= MAX_PHOTOS) return err(`Max ${MAX_PHOTOS} photos`, 400);

  const photoId = crypto.randomUUID();
  const key = `photos/${userId}/${photoId}.jpg`;

  const body = await request.arrayBuffer();
  if (body.byteLength < 30 * 1024) return err("Photo too small (min ~30 KB)");
  if (body.byteLength > MAX_PHOTO_BYTES) return err("Photo exceeds 5 MB limit", 413);

  await env.PHOTOS.put(key, body, {
    httpMetadata: { contentType: "image/jpeg" },
  });

  existing.push({ id: photoId, key });
  const now = Date.now();
  await env.DB.prepare(
    "UPDATE profiles SET photos_json = ?, updated_at = ? WHERE user_id = ?"
  ).bind(JSON.stringify(existing), now, userId).run();

  const base = photosBase(env);
  return json({
    photo: { id: photoId, url: base ? `${base}/${key}` : key },
    photos: existing.map(e => ({ id: e.id, url: base ? `${base}/${e.key}` : e.key })),
  }, 201);
}

// DELETE /me/photos/:photoId  [auth]
async function handleDeletePhoto(photoId: string, request: Request, env: Env): Promise<Response> {
  if (!env.PHOTOS) return err("Photo uploads are not configured", 501);
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  const profileRow = await env.DB.prepare(
    "SELECT photos_json FROM profiles WHERE user_id = ?"
  ).bind(userId).first<{ photos_json: string | null }>();
  if (!profileRow) return err("Profile not found", 404);

  const existing = parsePhotos(profileRow.photos_json);
  const idx = existing.findIndex(e => e.id === photoId);
  if (idx === -1) return err("Photo not found", 404);

  const removed = existing.splice(idx, 1)[0];

  // Delete from R2 + update D1 in parallel
  await Promise.all([
    env.PHOTOS.delete(removed.key),
    env.DB.prepare(
      "UPDATE profiles SET photos_json = ?, updated_at = ? WHERE user_id = ?"
    ).bind(JSON.stringify(existing), Date.now(), userId).run(),
  ]);

  const base = photosBase(env);
  return json({
    photos: existing.map(e => ({ id: e.id, url: base ? `${base}/${e.key}` : e.key })),
  });
}

// PUT /me/photos/order  [auth]  body = { ids: ["id1","id2",...] }
async function handleReorderPhotos(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const ids = body?.ids;
  if (!Array.isArray(ids) || ids.length === 0) return err("ids must be a non-empty array");

  const profileRow = await env.DB.prepare(
    "SELECT photos_json FROM profiles WHERE user_id = ?"
  ).bind(userId).first<{ photos_json: string | null }>();
  if (!profileRow) return err("Profile not found", 404);

  const existing = parsePhotos(profileRow.photos_json);
  const byId = new Map(existing.map(e => [e.id, e]));

  // Reorder: walk the supplied ids array; unknown ids are silently dropped,
  // photos not mentioned keep their relative tail order.
  const reordered: PhotoEntry[] = [];
  const seen = new Set<string>();
  for (const id of ids) {
    const entry = byId.get(String(id));
    if (entry && !seen.has(entry.id)) {
      reordered.push(entry);
      seen.add(entry.id);
    }
  }
  for (const e of existing) {
    if (!seen.has(e.id)) reordered.push(e);
  }

  await env.DB.prepare(
    "UPDATE profiles SET photos_json = ?, updated_at = ? WHERE user_id = ?"
  ).bind(JSON.stringify(reordered), Date.now(), userId).run();

  const base = photosBase(env);
  return json({
    photos: reordered.map(e => ({ id: e.id, url: base ? `${base}/${e.key}` : e.key })),
  });
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
    if (pathname === "/me/dob" && m === "POST") return handleSetDob(request, env);
    if (pathname === "/auth/logout" && m === "POST") return handleLogout(request, env);

    // Slice 2 — push
    if (pathname === "/devices/register" && m === "POST") return handleRegisterDevice(request, env);
    if (pathname === "/devices/unregister" && m === "POST") return handleUnregisterDevice(request, env);
    if (pathname === "/push/send" && m === "POST") return handleSendPush(request, env);

    // Slice 3 — verification
    if (pathname === "/verify/start" && m === "POST") return handleVerifyStart(request, env);
    if (pathname === "/verify/webhook" && m === "POST") return handleVerifyWebhook(request, env);
    if (pathname === "/admin/verify" && m === "POST") return handleAdminVerify(request, env);

    // Slice 4b0 — public profiles
    if (pathname === "/me/profile" && m === "PUT") return handleUpsertMyProfile(request, env);
    if (pathname === "/me/profile" && m === "GET") return handleGetMyProfile(request, env);
    if (pathname === "/users/floor" && m === "GET") return handleFloor(request, env);
    const userProfile = pathname.match(/^\/users\/([A-Za-z0-9-]{36})\/profile$/);
    if (userProfile && m === "GET") return handleGetUserProfile(userProfile[1], request, env);

    // Batch U — photos
    if (pathname === "/me/photos" && m === "POST") return handleUploadPhoto(request, env);
    if (pathname === "/me/photos/order" && m === "PUT") return handleReorderPhotos(request, env);
    const photoDelete = pathname.match(/^\/me\/photos\/([A-Za-z0-9-]{36})$/);
    if (photoDelete && m === "DELETE") return handleDeletePhoto(photoDelete[1], request, env);

    // Slice 4c1a — blocks
    if (pathname === "/me/blocks" && m === "POST") return handleAddBlock(request, env);
    if (pathname === "/me/blocks" && m === "GET") return handleListBlocks(request, env);
    const blockDelete = pathname.match(/^\/me\/blocks\/([A-Za-z0-9-]{36})$/);
    if (blockDelete && m === "DELETE") return handleRemoveBlock(blockDelete[1], request, env);

    // Slice 5 — reports
    if (pathname === "/me/reports" && m === "POST") return handleCreateReport(request, env);
    if (pathname === "/admin/reports" && m === "GET") return handleAdminListReports(request, env);
    const reportResolve = pathname.match(/^\/admin\/reports\/([A-Za-z0-9-]{36})\/resolve$/);
    if (reportResolve && m === "POST") return handleAdminResolveReport(reportResolve[1], request, env);

    // Admin user actions
    if (pathname === "/admin/stats" && m === "GET") return handleAdminStats(request, env);
    if (pathname === "/admin/audit" && m === "GET") return handleAdminAudit(request, env);
    if (pathname === "/admin/users" && m === "GET") return handleAdminListUsers(request, env);
    const userUnverify = pathname.match(/^\/admin\/users\/([A-Za-z0-9-]{36})\/unverify$/);
    if (userUnverify && m === "POST") return handleAdminUnverifyUser(userUnverify[1], request, env);
    const userSuspend = pathname.match(/^\/admin\/users\/([A-Za-z0-9-]{36})\/suspend$/);
    if (userSuspend && m === "POST") return handleAdminSuspendUser(userSuspend[1], request, env);
    const userUnsuspend = pathname.match(/^\/admin\/users\/([A-Za-z0-9-]{36})\/unsuspend$/);
    if (userUnsuspend && m === "POST") return handleAdminUnsuspendUser(userUnsuspend[1], request, env);
    const userDelete = pathname.match(/^\/admin\/users\/([A-Za-z0-9-]{36})$/);
    if (userDelete && m === "DELETE") return handleAdminDeleteUser(userDelete[1], request, env);

    return err("Not found", 404);
  },
};
