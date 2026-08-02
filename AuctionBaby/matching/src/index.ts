/**
 * Auction Baby — Matching Worker (bids, matches, messages between real users).
 *
 * This is Slice 4 of the spine (see SPINE_ROADMAP.md) — the "two phones
 * actually see each other" layer. Bids placed on one signed-in user's phone
 * land in the target user's inbox on their phone; accepts create a match on
 * both sides; messages flow through here.
 *
 * SHARES ITS D1 with the auth Worker (`auctionbaby-users`) so `bidder_id`
 * and `lot_id` are foreign keys into `users` — one identity, one database.
 * Session tokens are ALSO issued by the auth Worker; we verify them with the
 * same shared `SESSION_SECRET` (stateless HMAC — no cross-Worker round-trip).
 *
 * PUSH PIPE: this Worker never talks to APNs directly. When a bid, accept, or
 * message should wake the other phone, it POSTs to `<AUTH_URL>/push/send` on
 * the auth Worker (gated by `AUTH_ADMIN_SECRET`, which is auth's
 * `APP_SHARED_SECRET`). The push infrastructure lives in one place.
 *
 * WHAT SHIPS IN THIS SLICE (4a): the DATA plane. Every endpoint you'd need
 * to run the full bid → accept → message → mark-done loop with two real users
 * exists here and works. WHAT'S NEXT: wiring the iOS UI to consume these
 * endpoints (slice 4b/4c). Today the on-device simulation is still the
 * default; signed-in users will opt into the real backend as UI migrates.
 *
 * Endpoints:
 *   GET  /health                           liveness + config sanity
 *   POST /bids                             place a bid on another user     [auth]
 *   GET  /bids/incoming                    my inbox (pending bids on me)   [auth]
 *   GET  /bids/outgoing                    my outgoing bids                 [auth]
 *   POST /bids/:id/accept                  accept a bid → mint a match     [auth]
 *   POST /bids/:id/decline                 decline a bid                   [auth]
 *   POST /bids/:id/withdraw                withdraw MY pending bid         [auth]
 *   GET  /matches                          my matches (both sides)         [auth]
 *   GET  /matches/:id                      one match with messages         [auth]
 *   POST /matches/:id/messages             send a message                  [auth]
 *   POST /matches/:id/mark-seen            mark other side's msgs as read  [auth]
 *   POST /matches/:id/mark-date-done       both sides move to review phase [auth]
 *
 * Slice 4c1a — block enforcement lives here. Blocks are OWNED by the auth
 * Worker (`/me/blocks/*`), stored in the shared `blocks` table, and read
 * from every list/write endpoint above: a blocked pair (either direction)
 * gets 403 on writes and their rows are hidden from lists.
 *
 * Slice 4c1b — rate limits on the spammable writes: 20 bids/hour per
 * bidder (`POST /bids`) and 30 messages/minute per sender
 * (`POST /matches/:id/messages`). Fixed-window counters in `rate_counters`
 * (shared D1). Over-cap responses are 429 with `Retry-After`.
 */

interface Env {
  DB: D1Database;
  SESSION_SECRET: string;
  AUTH_URL?: string;
  AUTH_ADMIN_SECRET?: string;
  /** Batch I — shared bearer used by the consumables Worker's reservation
   *  webhook to stamp `matches.reserved_at`. Same value as
   *  APP_SHARED_SECRET on the consumables Worker by convention. */
  APP_SHARED_SECRET?: string;
}

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

// ── Session token verification (must match the auth Worker) ──────────────────

function base64UrlEncode(bytes: Uint8Array): string {
  const bin = String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmacSha256(key: string, message: string): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message)));
}

/** Verify `userId.expiryMs.signature`. Same shape as the auth Worker issues.
 *  Constant-time compare to keep timing side-channels closed. */
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

async function authenticate(request: Request, env: Env): Promise<string | null> {
  const auth = request.headers.get("Authorization");
  if (!auth || !auth.startsWith("Bearer ")) return null;
  return verifySessionToken(auth.slice(7), env.SESSION_SECRET);
}

// ── Fire-and-forget push to the auth Worker ──────────────────────────────────

interface PushInput { userId: string; title: string; body: string; data?: Record<string, unknown> }

/** Best-effort push dispatch. Never throws — a push failure must not block
 *  the state change that triggered it. Silently no-ops when auth isn't wired
 *  (fresh dev setups); logs otherwise. */
async function firePush(env: Env, payload: PushInput): Promise<void> {
  if (!env.AUTH_URL || !env.AUTH_ADMIN_SECRET) return;
  const url = env.AUTH_URL.replace(/\/$/, "") + "/push/send";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${env.AUTH_ADMIN_SECRET}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (!res.ok) {
      console.log(`push send ${res.status} for ${payload.userId}`);
    }
  } catch (e) {
    console.log(`push send transport error: ${String(e)}`);
  }
}

// ── Rows + shapes ────────────────────────────────────────────────────────────

interface BidRow {
  id: string; bidder_id: string; lot_id: string; amount: number; note: string | null;
  status: string; gilded: number; insured: number; is_whisper: number;
  prompt_ref: string | null; created_at: number; resolved_at: number | null;
}

interface MatchRow {
  id: string; bid_id: string; bidder_id: string; lot_id: string;
  amount: number; phase: string; created_at: number; expires_at: number | null;
  reserved_amount_cents: number | null; reserved_at: number | null;
}

interface MessageRow {
  id: string; match_id: string; from_id: string; text: string;
  created_at: number; seen_at: number | null; reaction: string | null;
}

/** Public bid shape — booleans instead of 0/1, no extra fields to leak. */
function publicBid(b: BidRow) {
  return {
    id: b.id, bidderId: b.bidder_id, lotId: b.lot_id, amount: b.amount,
    note: b.note, status: b.status,
    gilded: b.gilded === 1, insured: b.insured === 1, isWhisper: b.is_whisper === 1,
    promptRef: b.prompt_ref, createdAt: b.created_at, resolvedAt: b.resolved_at,
  };
}

function publicMatch(m: MatchRow) {
  return {
    id: m.id, bidId: m.bid_id, bidderId: m.bidder_id, lotId: m.lot_id,
    amount: m.amount, phase: m.phase, createdAt: m.created_at, expiresAt: m.expires_at,
    reservedAmountCents: m.reserved_amount_cents, reservedAt: m.reserved_at,
  };
}

function publicMessage(m: MessageRow) {
  return {
    id: m.id, matchId: m.match_id, fromId: m.from_id, text: m.text,
    createdAt: m.created_at, seenAt: m.seen_at, reaction: m.reaction,
  };
}

// ── Helpers used by multiple handlers ────────────────────────────────────────

async function getUserName(env: Env, userId: string): Promise<string> {
  const row = await env.DB.prepare("SELECT name FROM users WHERE id = ?")
    .bind(userId).first<{ name: string | null }>();
  return row?.name ?? "Someone";
}

/** Return the match if `userId` is one of its two participants; null otherwise.
 *  Used before every match-scoped write so a leaked matchId can't be poked. */
async function fetchMatchIfParticipant(env: Env, matchId: string, userId: string): Promise<MatchRow | null> {
  const row = await env.DB.prepare(
    "SELECT * FROM matches WHERE id = ? AND (bidder_id = ? OR lot_id = ?)",
  ).bind(matchId, userId, userId).first<MatchRow>();
  return row ?? null;
}

/** In a match, who is the OTHER participant relative to `userId`? */
function otherOf(match: MatchRow, userId: string): string {
  return match.bidder_id === userId ? match.lot_id : match.bidder_id;
}

/** Slice 4c1b — fixed-window rate limit. Bumps then checks: two racers each
 *  land their bump, only the one under cap succeeds; the loser burns quota
 *  (fine trade-off for a spam defense). Returns `.ok = false` when the
 *  effective count for this window is now over `cap`. */
async function checkRate(env: Env, key: string, windowMs: number, cap: number): Promise<{ ok: boolean; retryAfterSec: number }> {
  const now = Date.now();
  const windowStart = Math.floor(now / windowMs) * windowMs;
  const row = await env.DB.prepare(
    `INSERT INTO rate_counters (key, window_ms, count) VALUES (?, ?, 1)
     ON CONFLICT(key, window_ms) DO UPDATE SET count = count + 1
     RETURNING count AS count`,
  ).bind(key, windowStart).first<{ count: number }>();
  const count = row?.count ?? 1;
  if (count <= cap) return { ok: true, retryAfterSec: 0 };
  const retryAfterSec = Math.max(1, Math.ceil((windowStart + windowMs - now) / 1000));
  return { ok: false, retryAfterSec };
}

/** 429 response with a `Retry-After` header — the standard signal the client
 *  can key off for a "slow down" toast. */
function tooManyRequests(message: string, retryAfterSec: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status: 429,
    headers: {
      "Content-Type": "application/json",
      "Retry-After": String(retryAfterSec),
      ...CORS,
    },
  });
}

/** Slice 4c1a — true iff EITHER side of the pair has an active block on the
 *  other. Reads the shared `blocks` table (owned by the auth Worker). One
 *  query, both directions — cheap against the PK / index shape. */
async function isBlockedEitherWay(env: Env, a: string, b: string): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT 1 FROM blocks
      WHERE (blocker_id = ?1 AND blocked_id = ?2)
         OR (blocker_id = ?2 AND blocked_id = ?1)
      LIMIT 1`,
  ).bind(a, b).first();
  return row != null;
}

/** Compact money display for push copy — "$1K", "$1.2M", plain dollars below 1K. */
function moneyCompact(n: number): string {
  if (n >= 1_000_000) {
    const m = n / 1_000_000;
    return `$${m >= 10 ? Math.round(m) : m.toFixed(1)}M`;
  }
  if (n >= 1_000) {
    const k = n / 1_000;
    return `$${k >= 10 ? Math.round(k) : k.toFixed(1)}K`;
  }
  return `$${n}`;
}

// ── Handlers ─────────────────────────────────────────────────────────────────

function handleHealth(env: Env): Response {
  return json({
    ok: true,
    service: "auctionbaby-matching",
    sessionSecretConfigured: Boolean(env.SESSION_SECRET),
    dbBound: Boolean(env.DB),
    push: {
      configured: Boolean(env.AUTH_URL && env.AUTH_ADMIN_SECRET),
      authUrlSet: Boolean(env.AUTH_URL),
    },
  });
}

/** Constant-time compare for a bearer secret. Same shape as auth Worker. */
async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  if (a.length !== b.length) return false;
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return mismatch === 0;
}

/** POST /internal/reservations/mark  { matchId, amountCents, at }
 *  Called by the consumables Worker's reservation webhook after a paid
 *  Stripe checkout completes (or is refunded). Stamps
 *  `matches.reserved_at` + `reserved_amount_cents` so every device sees
 *  the state via GET /matches. `at: null` clears the flag (refund path).
 *
 *  Bearer-gated with the shared APP_SHARED_SECRET convention. NOT a
 *  session-authed endpoint — the consumables Worker doesn't have session
 *  tokens, only the operator's admin bearer. */
async function handleInternalReservationMark(request: Request, env: Env): Promise<Response> {
  if (!env.APP_SHARED_SECRET) return err("Server misconfigured: APP_SHARED_SECRET unset", 500);
  const auth = request.headers.get("Authorization");
  const supplied = auth?.startsWith("Bearer ") ? auth.slice(7) : (auth ?? "");
  if (!(await constantTimeEqual(supplied, env.APP_SHARED_SECRET))) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const matchId = String(body?.matchId ?? "").trim();
  if (!matchId) return err("matchId is required");
  const amountCentsRaw = Number(body?.amountCents ?? 0);
  const amountCents = Number.isFinite(amountCentsRaw) ? Math.round(amountCentsRaw) : 0;
  const atRaw = body?.at;
  const at = atRaw == null ? null : Number(atRaw);
  await env.DB.prepare(
    "UPDATE matches SET reserved_at = ?, reserved_amount_cents = ? WHERE id = ?",
  ).bind(at, at == null ? null : amountCents, matchId).run();
  return json({ ok: true });
}

/** POST /bids  { lotId, amount, note?, gilded?, insured?, isWhisper?, promptRef? }
 *  → creates a bid, fires a push to the lot. */
async function handlePlaceBid(request: Request, env: Env): Promise<Response> {
  const bidderId = await authenticate(request, env);
  if (!bidderId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }

  const lotId = String(body?.lotId ?? "").trim();
  const amount = Math.round(Number(body?.amount ?? 0));
  if (!lotId) return err("lotId is required");
  if (lotId === bidderId) return err("You can't bid on yourself", 400);
  if (!Number.isFinite(amount) || amount <= 0) return err("amount must be a positive integer");
  // A hard ceiling that matches the app's `maxStartingBid` — stops obvious
  // client tampering (a $999,999,999 bid) from ever hitting the DB.
  if (amount > 1_000_000_000) return err("amount is out of range");

  // Refuse to write a bid pointing at a non-existent user — cheap defense
  // against enumeration or a leaked userId being used to spam. Both sides
  // must also have their DOB set on the auth-Worker `users` table — /me/dob
  // is where the 18+ check runs, so "DOB present" is the age-verified
  // proxy. Applies to both the bidder and the lot so a null-DOB user can
  // neither send nor receive.
  const parties = await env.DB.prepare(
    "SELECT id, date_of_birth FROM users WHERE id IN (?, ?)",
  ).bind(bidderId, lotId).all<{ id: string; date_of_birth: string | null }>();
  const rows = parties.results ?? [];
  const lotRow = rows.find((r) => r.id === lotId);
  const bidderRow = rows.find((r) => r.id === bidderId);
  if (!lotRow) return err("Lot not found", 404);
  if (!bidderRow?.date_of_birth) return err("Set your date of birth first — the 18+ check runs against it.", 403);
  if (!lotRow.date_of_birth) return err("Bid can't be delivered", 403);

  // Server-enforced blocks: either direction stops the bid. Deliberately
  // vague error to avoid leaking who blocked whom.
  if (await isBlockedEitherWay(env, bidderId, lotId)) {
    return err("Bid can't be delivered", 403);
  }

  // Rate limit: 20 bids/hour per bidder. Sized for real dating behavior
  // (nobody legitimately writes 20 different bids in an hour) — anything
  // above is spam / a rogue script. Bumps then checks so racers get
  // deterministic enforcement.
  const bidRate = await checkRate(env, `bid.place:${bidderId}`, 60 * 60 * 1000, 20);
  if (!bidRate.ok) {
    return tooManyRequests("Too many bids in a short time — take a breath.", bidRate.retryAfterSec);
  }

  const isWhisper = Boolean(body?.isWhisper);
  const bid: BidRow = {
    id: crypto.randomUUID(),
    bidder_id: bidderId,
    lot_id: lotId,
    amount: isWhisper ? 0 : amount,
    note: body?.note ? String(body.note).slice(0, 500) : null,
    status: "pending",
    gilded: Boolean(body?.gilded) && !isWhisper ? 1 : 0,
    insured: Boolean(body?.insured) && !isWhisper ? 1 : 0,
    is_whisper: isWhisper ? 1 : 0,
    prompt_ref: body?.promptRef ? String(body.promptRef).slice(0, 200) : null,
    created_at: Date.now(),
    resolved_at: null,
  };
  await env.DB.prepare(
    `INSERT INTO bids (id, bidder_id, lot_id, amount, note, status, gilded, insured, is_whisper, prompt_ref, created_at, resolved_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    bid.id, bid.bidder_id, bid.lot_id, bid.amount, bid.note, bid.status,
    bid.gilded, bid.insured, bid.is_whisper, bid.prompt_ref, bid.created_at, bid.resolved_at,
  ).run();

  const bidderName = await getUserName(env, bidderId);
  await firePush(env, {
    userId: lotId,
    title: isWhisper ? "Someone whispered" : `${moneyCompact(amount)} bid`,
    body: isWhisper
      ? `${bidderName} is testing the water — send a nod if you're curious.`
      : `${bidderName} just bid ${moneyCompact(amount)} on you.`,
    data: { type: "bid.received", bidId: bid.id },
  });

  return json({ bid: publicBid(bid) }, 201);
}

/** Minimal profile fields we ship inline with a bid so the UI can render
 *  "who's bidding" without a per-row round-trip. `verified_at` from `users`
 *  drives the blue check. `name` may be null before the peer sets a profile. */
interface PeerRow {
  peer_id: string;
  peer_name: string | null;
  peer_hue: number | null;
  peer_archetype: string | null;
  peer_verified_at: number | null;
}

function publicPeer(r: PeerRow) {
  return {
    id: r.peer_id,
    name: r.peer_name,
    hue: r.peer_hue,
    archetype: r.peer_archetype,
    verifiedAt: r.peer_verified_at,
  };
}

/** GET /bids/incoming  [auth]  — my pending inbox, newest first. Each row
 *  ships a minimal `bidder` profile snapshot (LEFT JOIN) so the UI can render
 *  who's bidding without a per-row profile fetch. */
async function handleIncoming(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  // Block-aware inbox: hide rows where either side of the pair has an active
  // block. A bid placed BEFORE the block was set is filtered out on read.
  const rows = await env.DB.prepare(
    `SELECT b.*,
            b.bidder_id AS peer_id,
            p.name      AS peer_name,
            p.hue       AS peer_hue,
            p.archetype AS peer_archetype,
            u.verified_at AS peer_verified_at
       FROM bids b
       LEFT JOIN profiles p ON p.user_id = b.bidder_id
       LEFT JOIN users u    ON u.id      = b.bidder_id
      WHERE b.lot_id = ?1 AND b.status = 'pending'
        AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = ?1 AND blocked_id = b.bidder_id)
        AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = b.bidder_id AND blocked_id = ?1)
      ORDER BY b.created_at DESC LIMIT 100`,
  ).bind(userId).all<BidRow & PeerRow>();
  const results = rows.results ?? [];
  return json({
    bids: results.map((r) => ({ ...publicBid(r), bidder: publicPeer(r) })),
  });
}

/** GET /bids/outgoing  [auth]  — my outgoing, newest first. Symmetric to
 *  `/bids/incoming`: each row ships a minimal `lot` profile snapshot. */
async function handleOutgoing(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  // Symmetric filter for the bidder's outgoing list.
  const rows = await env.DB.prepare(
    `SELECT b.*,
            b.lot_id    AS peer_id,
            p.name      AS peer_name,
            p.hue       AS peer_hue,
            p.archetype AS peer_archetype,
            u.verified_at AS peer_verified_at
       FROM bids b
       LEFT JOIN profiles p ON p.user_id = b.lot_id
       LEFT JOIN users u    ON u.id      = b.lot_id
      WHERE b.bidder_id = ?1
        AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = ?1 AND blocked_id = b.lot_id)
        AND NOT EXISTS (SELECT 1 FROM blocks WHERE blocker_id = b.lot_id AND blocked_id = ?1)
      ORDER BY b.created_at DESC LIMIT 100`,
  ).bind(userId).all<BidRow & PeerRow>();
  const results = rows.results ?? [];
  return json({
    bids: results.map((r) => ({ ...publicBid(r), lot: publicPeer(r) })),
  });
}

/** POST /bids/:id/accept  [auth]  — the LOT accepts. Creates a match. */
async function handleAcceptBid(bidId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);

  const bid = await env.DB.prepare("SELECT * FROM bids WHERE id = ?")
    .bind(bidId).first<BidRow>();
  if (!bid) return err("Bid not found", 404);
  if (bid.lot_id !== userId) return err("Only the lot can accept this bid", 403);
  if (bid.status !== "pending") return err(`Bid is already ${bid.status}`, 409);

  // Block enforcement — a block placed AFTER the bid landed must prevent
  // the match from minting. Deliberately vague error to avoid leaking who
  // blocked whom.
  if (await isBlockedEitherWay(env, userId, bid.bidder_id)) {
    return err("This bid can't be accepted", 403);
  }

  const now = Date.now();
  // Whispers resolve softly — a nod is a signal, not a match. Match creation
  // is skipped, the bid moves to `accepted` (a nod), and the bidder gets a
  // push inviting them back with a real number.
  if (bid.is_whisper === 1) {
    await env.DB.prepare(
      "UPDATE bids SET status = 'accepted', resolved_at = ? WHERE id = ?",
    ).bind(now, bidId).run();
    const lotName = await getUserName(env, userId);
    await firePush(env, {
      userId: bid.bidder_id,
      title: `${lotName} nodded`,
      body: "Your whisper was noticed. Send a real bid.",
      data: { type: "whisper.nodded", bidId: bid.id },
    });
    return json({ bid: publicBid({ ...bid, status: "accepted", resolved_at: now }) });
  }

  // Real bid → mint a match. Guard the UNIQUE(bid_id) constraint at the app
  // level too, so a double-tap on accept returns the existing match instead
  // of a 500.
  const matchId = crypto.randomUUID();
  try {
    await env.DB.batch([
      env.DB.prepare(
        "UPDATE bids SET status = 'accepted', resolved_at = ? WHERE id = ? AND status = 'pending'",
      ).bind(now, bidId),
      env.DB.prepare(
        `INSERT INTO matches (id, bid_id, bidder_id, lot_id, amount, phase, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, 'chatting', ?, ?)`,
      ).bind(matchId, bidId, bid.bidder_id, bid.lot_id, bid.amount, now, now + 24 * 3600 * 1000),
    ]);
  } catch {
    // Likely raced with another accept. Return the winning match.
    const existing = await env.DB.prepare("SELECT * FROM matches WHERE bid_id = ?")
      .bind(bidId).first<MatchRow>();
    if (existing) return json({ match: publicMatch(existing), raced: true });
    return err("Failed to accept", 500);
  }

  const lotName = await getUserName(env, userId);
  await firePush(env, {
    userId: bid.bidder_id,
    title: `${lotName} accepted`,
    body: `Your ${moneyCompact(bid.amount)} bid landed. She wants to talk.`,
    data: { type: "bid.accepted", bidId: bid.id, matchId },
  });

  return json({
    match: publicMatch({
      id: matchId, bid_id: bidId, bidder_id: bid.bidder_id, lot_id: bid.lot_id,
      amount: bid.amount, phase: "chatting", created_at: now,
      expires_at: now + 24 * 3600 * 1000,
      reserved_amount_cents: null, reserved_at: null,
    }),
  }, 201);
}

/** POST /bids/:id/decline  [auth]  — the LOT declines. No match. */
async function handleDeclineBid(bidId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const bid = await env.DB.prepare("SELECT * FROM bids WHERE id = ?").bind(bidId).first<BidRow>();
  if (!bid) return err("Bid not found", 404);
  if (bid.lot_id !== userId) return err("Only the lot can decline this bid", 403);
  if (bid.status !== "pending") return err(`Bid is already ${bid.status}`, 409);

  const now = Date.now();
  await env.DB.prepare(
    "UPDATE bids SET status = 'declined', resolved_at = ? WHERE id = ? AND status = 'pending'",
  ).bind(now, bidId).run();
  // No push on decline by design — spares the bidder a "rejected" notification
  // (they can see it in their outgoing list next time they check). If we
  // change our mind later, this is where it goes.
  return json({ bid: publicBid({ ...bid, status: "declined", resolved_at: now }) });
}

/** POST /bids/:id/withdraw  [auth]  — the BIDDER pulls a still-pending bid. */
async function handleWithdrawBid(bidId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const bid = await env.DB.prepare("SELECT * FROM bids WHERE id = ?").bind(bidId).first<BidRow>();
  if (!bid) return err("Bid not found", 404);
  if (bid.bidder_id !== userId) return err("Only the bidder can withdraw this bid", 403);
  if (bid.status !== "pending") return err(`Bid is already ${bid.status}`, 409);

  const now = Date.now();
  await env.DB.prepare(
    "UPDATE bids SET status = 'withdrawn', resolved_at = ? WHERE id = ? AND status = 'pending'",
  ).bind(now, bidId).run();
  return json({ bid: publicBid({ ...bid, status: "withdrawn", resolved_at: now }) });
}

/** GET /matches  [auth]  — every match I'm part of, newest first. Each row
 *  ships a minimal `peer` snapshot (the OTHER participant, computed via
 *  a CASE expression + LEFT JOIN) so `MatchesView` can render rows without
 *  N+1 profile fetches. */
async function handleListMatches(request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  // Bind userId three times: once to pick the peer column, twice to JOIN
  // profiles / users on that column. Ugly but D1 supports it and it beats
  // client-side N+1 fetches.
  const rows = await env.DB.prepare(
    `SELECT m.*,
            CASE WHEN m.bidder_id = ?1 THEN m.lot_id ELSE m.bidder_id END AS peer_id,
            peer_p.name       AS peer_name,
            peer_p.hue        AS peer_hue,
            peer_p.archetype  AS peer_archetype,
            peer_u.verified_at AS peer_verified_at
       FROM matches m
       LEFT JOIN profiles peer_p
         ON peer_p.user_id = (CASE WHEN m.bidder_id = ?1 THEN m.lot_id ELSE m.bidder_id END)
       LEFT JOIN users peer_u
         ON peer_u.id = (CASE WHEN m.bidder_id = ?1 THEN m.lot_id ELSE m.bidder_id END)
      WHERE (m.bidder_id = ?1 OR m.lot_id = ?1)
        AND NOT EXISTS (
          SELECT 1 FROM blocks
           WHERE (blocker_id = ?1 AND blocked_id = CASE WHEN m.bidder_id = ?1 THEN m.lot_id ELSE m.bidder_id END)
              OR (blocked_id = ?1 AND blocker_id = CASE WHEN m.bidder_id = ?1 THEN m.lot_id ELSE m.bidder_id END)
        )
      ORDER BY m.created_at DESC LIMIT 100`,
  ).bind(userId).all<MatchRow & PeerRow>();
  const results = rows.results ?? [];
  return json({
    matches: results.map((r) => ({ ...publicMatch(r), peer: publicPeer(r) })),
  });
}

/** GET /matches/:id  [auth]  — one match + its messages (oldest first).
 *  Ships the peer snapshot alongside for the chat header to render without a
 *  separate profile round-trip. */
async function handleGetMatch(matchId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const match = await fetchMatchIfParticipant(env, matchId, userId);
  if (!match) return err("Match not found", 404);
  // Fetch the peer snapshot alongside the messages — one extra query, avoids
  // a per-open round-trip for the chat header.
  const peerId = match.bidder_id === userId ? match.lot_id : match.bidder_id;
  const [peerRow, msgs] = await Promise.all([
    env.DB.prepare(
      `SELECT ? AS peer_id,
              p.name       AS peer_name,
              p.hue        AS peer_hue,
              p.archetype  AS peer_archetype,
              u.verified_at AS peer_verified_at
         FROM users u LEFT JOIN profiles p ON p.user_id = u.id
        WHERE u.id = ?`,
    ).bind(peerId, peerId).first<PeerRow>(),
    env.DB.prepare(
      "SELECT * FROM messages WHERE match_id = ? ORDER BY created_at ASC LIMIT 500",
    ).bind(matchId).all<MessageRow>(),
  ]);
  return json({
    match: {
      ...publicMatch(match),
      peer: peerRow ? publicPeer(peerRow) : null,
    },
    messages: (msgs.results ?? []).map(publicMessage),
  });
}

/** POST /matches/:id/messages  { text }  [auth]  — send + push. */
async function handleSendMessage(matchId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { return err("Invalid JSON body"); }
  const text = String(body?.text ?? "").trim().slice(0, 2000);
  if (!text) return err("text is required");

  const match = await fetchMatchIfParticipant(env, matchId, userId);
  if (!match) return err("Match not found", 404);
  if (match.phase !== "chatting") return err(`Match is ${match.phase} — no more messages`, 409);

  // Block enforcement — a block placed AFTER the match freezes new messages
  // in either direction. Existing history stays visible on the reader side
  // for context (report evidence), but nothing new lands.
  const otherIdEarly = otherOf(match, userId);
  if (await isBlockedEitherWay(env, userId, otherIdEarly)) {
    return err("Message can't be delivered", 403);
  }

  // Rate limit: 30 messages/minute per sender across ALL matches. A real
  // conversation never comes close; a spam pattern (blast the same line to
  // every match) trips instantly.
  const msgRate = await checkRate(env, `message.send:${userId}`, 60 * 1000, 30);
  if (!msgRate.ok) {
    return tooManyRequests("Slow down — you're sending too fast.", msgRate.retryAfterSec);
  }

  const now = Date.now();
  const msg: MessageRow = {
    id: crypto.randomUUID(), match_id: matchId, from_id: userId,
    text, created_at: now, seen_at: null, reaction: null,
  };
  // Sending clears the freshness clock — the ball moves to the other side.
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO messages (id, match_id, from_id, text, created_at, seen_at) VALUES (?, ?, ?, ?, ?, NULL)",
    ).bind(msg.id, msg.match_id, msg.from_id, msg.text, msg.created_at),
    env.DB.prepare("UPDATE matches SET expires_at = NULL WHERE id = ?").bind(matchId),
  ]);

  const otherId = otherOf(match, userId);
  const senderName = await getUserName(env, userId);
  await firePush(env, {
    userId: otherId,
    title: senderName,
    body: text.length > 120 ? text.slice(0, 117) + "…" : text,
    data: { type: "message.received", matchId, messageId: msg.id },
  });

  return json({ message: publicMessage(msg) }, 201);
}

/** POST /matches/:id/mark-seen  [auth]  — mark the OTHER side's unread messages
 *  in this match as seen (drives Black Card read receipts). */
async function handleMarkSeen(matchId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const match = await fetchMatchIfParticipant(env, matchId, userId);
  if (!match) return err("Match not found", 404);
  const now = Date.now();
  const result = await env.DB.prepare(
    "UPDATE messages SET seen_at = ? WHERE match_id = ? AND from_id != ? AND seen_at IS NULL",
  ).bind(now, matchId, userId).run();
  return json({ ok: true, updated: result.meta?.changes ?? 0 });
}

/** POST /matches/:matchId/messages/:messageId/react  { emoji?: string }  [auth]
 *  Set (or clear) the single-slot reaction on a message. Either participant
 *  may react; overwrites are visible to both — matches ChatMessage.reaction
 *  on the client. Nil / empty `emoji` clears the reaction. Blocked pairs
 *  can't react either (403). */
async function handleReactMessage(matchId: string, messageId: string,
                                  request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  let body: any;
  try { body = await request.json(); } catch { body = {}; }
  const raw = body?.emoji;
  const emoji = raw == null ? null : String(raw).slice(0, 10);

  const match = await fetchMatchIfParticipant(env, matchId, userId);
  if (!match) return err("Match not found", 404);
  const otherId = otherOf(match, userId);
  if (await isBlockedEitherWay(env, userId, otherId)) {
    return err("Reaction can't be delivered", 403);
  }
  const result = await env.DB.prepare(
    "UPDATE messages SET reaction = ? WHERE id = ? AND match_id = ?",
  ).bind(emoji && emoji.length > 0 ? emoji : null, messageId, matchId).run();
  return json({ ok: true, updated: result.meta?.changes ?? 0, reaction: emoji });
}

/** POST /matches/:id/mark-date-done  [auth]  — either side advances the match
 *  to review phase. Idempotent. */
async function handleMarkDateDone(matchId: string, request: Request, env: Env): Promise<Response> {
  const userId = await authenticate(request, env);
  if (!userId) return err("Unauthorized", 401);
  const match = await fetchMatchIfParticipant(env, matchId, userId);
  if (!match) return err("Match not found", 404);
  if (match.phase === "closed") return err("Match is already closed", 409);
  // Block enforcement — freezing the phase transition still allows the state
  // change locally, but no push wakes the blocker on the other side. Return
  // 403 instead so both clients agree the match is inert.
  const otherId = otherOf(match, userId);
  if (await isBlockedEitherWay(env, userId, otherId)) {
    return err("This match can't be advanced", 403);
  }
  await env.DB.prepare(
    "UPDATE matches SET phase = 'dateDone' WHERE id = ? AND phase = 'chatting'",
  ).bind(matchId).run();
  // Nudge the other side to leave their review too.
  const advancerName = await getUserName(env, userId);
  await firePush(env, {
    userId: otherId,
    title: "Date marked done",
    body: `${advancerName} says you two met. Leave your review.`,
    data: { type: "match.dateDone", matchId },
  });
  return json({ ok: true });
}

// ── Router ───────────────────────────────────────────────────────────────────

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    const { pathname } = url;
    const m = request.method;

    if (pathname === "/health" && m === "GET") return handleHealth(env);

    // Internal: reservation mirror from the consumables Worker.
    if (pathname === "/internal/reservations/mark" && m === "POST") {
      return handleInternalReservationMark(request, env);
    }

    // Bids
    if (pathname === "/bids" && m === "POST") return handlePlaceBid(request, env);
    if (pathname === "/bids/incoming" && m === "GET") return handleIncoming(request, env);
    if (pathname === "/bids/outgoing" && m === "GET") return handleOutgoing(request, env);
    let match = pathname.match(/^\/bids\/([A-Za-z0-9-]{36})\/accept$/);
    if (match && m === "POST") return handleAcceptBid(match[1], request, env);
    match = pathname.match(/^\/bids\/([A-Za-z0-9-]{36})\/decline$/);
    if (match && m === "POST") return handleDeclineBid(match[1], request, env);
    match = pathname.match(/^\/bids\/([A-Za-z0-9-]{36})\/withdraw$/);
    if (match && m === "POST") return handleWithdrawBid(match[1], request, env);

    // Matches
    if (pathname === "/matches" && m === "GET") return handleListMatches(request, env);
    match = pathname.match(/^\/matches\/([A-Za-z0-9-]{36})$/);
    if (match && m === "GET") return handleGetMatch(match[1], request, env);
    match = pathname.match(/^\/matches\/([A-Za-z0-9-]{36})\/messages$/);
    if (match && m === "POST") return handleSendMessage(match[1], request, env);
    match = pathname.match(/^\/matches\/([A-Za-z0-9-]{36})\/mark-seen$/);
    if (match && m === "POST") return handleMarkSeen(match[1], request, env);
    match = pathname.match(/^\/matches\/([A-Za-z0-9-]{36})\/messages\/([A-Za-z0-9-]{36})\/react$/);
    if (match && m === "POST") return handleReactMessage(match[1], match[2], request, env);
    match = pathname.match(/^\/matches\/([A-Za-z0-9-]{36})\/mark-date-done$/);
    if (match && m === "POST") return handleMarkDateDone(match[1], request, env);

    return err("Not found", 404);
  },

  // Cron trigger (see wrangler.toml [triggers].crons).
  // Prune rate_counters rows whose window closed more than 48h ago. Only
  // historical windows are safe to delete — anything within 48h could still
  // be re-consulted by an in-flight burst. Cheap D1 delete; bounded blast
  // radius by the WHERE clause.
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const cutoff = Date.now() - 48 * 60 * 60 * 1000;
    try {
      const result = await env.DB.prepare(
        "DELETE FROM rate_counters WHERE window_ms < ?",
      ).bind(cutoff).run();
      console.log(`rate_counters cleanup: pruned ${result.meta?.changes ?? 0} rows older than ${new Date(cutoff).toISOString()}`);
    } catch (e) {
      console.log(`rate_counters cleanup failed: ${String(e)}`);
    }
  },
};
