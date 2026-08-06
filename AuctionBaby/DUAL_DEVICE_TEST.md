# Auction Baby — Two-Phone / Dual-Device Test Plan

End-to-end verification that **two real accounts on two devices**, talking
through the same Cloudflare Workers, see each other's actions correctly —
the bid → match → chat → push loop that single-device testing can't cover.

Run at least one full pass before every TestFlight/App Store build.

Legend: ☐ untested · ✅ pass · ❌ fail (log in BUGS.md) · ➖ N/A

---

## 0 · What "two-phone" requires (read first)

Cross-device flows are **remote-only**. Demo Mode is on-device sim and never
crosses the wire, so both clients must be **signed in with Apple** against the
**same deployed Workers**. Confirm before starting:

- ☐ Both builds share identical `Config/Secrets.xcconfig` (auth, matching,
      profiles, push Worker URLs + shared secret)
- ☐ Workers are the **production/staging deployment**, not `wrangler dev` on
      one machine only reachable by one client
- ☐ Two **distinct Apple IDs** — one per device. (SIWA on the Simulator needs
      the sim signed into iCloud in Settings; two sims need two Apple IDs, or
      use one Simulator + one physical device.)
- ☐ Push capability enabled + `.entitlements` present in the build
- ☐ Roles assigned: **Phone A = man (bidder)**, **Phone B = woman (lot)**

Naming below: **A** = bidder, **B** = lot.

### The two ways state crosses devices
1. **Pull-to-refresh / foreground refresh** — always works, no push needed.
   Most rows below can be verified this way alone.
2. **Push** — real-time deep-link + auto-refresh. Test separately (§9); the
   Simulator needs `simctl push` (real APNs to a sim is unreliable).

Test each cross-device row **refresh-first** (deterministic), then re-run the
push variant.

---

## 1 · Pairing & discovery

- ☐ A signs in (Apple ID #1), sets DOB, role = man → floor loads
- ☐ B signs in (Apple ID #2), sets DOB, role = woman, sets a floor/starting bid
- ☐ B's profile syncs to server (no error toast on submit)
- ☐ On A: pull-to-refresh the floor → **B appears as a lot**
- ☐ B's R2 photo loads on A's floor card (shimmer → photo, not monogram)
- ☐ `isRemoteFloor` flipped — "Real people on the floor" chip shows on A
- ☐ A opens B's detail → bio, prompts, interests, photos all match what B set
- ☐ A's age filter excludes B when B's age is out of range; includes when in
- ☐ Verified-only filter (Reserve) hides B until B is verified (§8)
- ☐ Location filter narrows correctly for B's city

---

## 2 · Bid → inbox (A bids, B receives)

- ☐ A places a standard bid on B → success toast, appears in A's My Bids as Live
- ☐ On B: pull-to-refresh inbox → **A's bid appears as pending**
- ☐ B sees A's stats (credit, deadbeat, archetype) but **photo is LOCKED**
- ☐ A's name shows as "Hidden bidder" on B's side (not revealed pre-accept)
- ☐ A gilds a bid → on B it carries the gold ribbon **and sorts above** plain bids
- ☐ Gild debits A's Gavels; short balance → falls back to standard (toast)
- ☐ A sends a **whisper** → on B it reads "Someone whispered", fully anonymous,
      no amount, no identity
- ☐ Whisper is **not** offered on copycats (N/A cross-device — copycats are sim)
- ☐ A's **free-bid limit (3)** counts these real bids — 4th is gated to paywall
- ☐ Free limit is **not** bypassable by force-quitting + relaunching A
- ☐ Bid Insurance premium debits on A; refunded if B declines (§3)
- ☐ Prompt-context bid: A bids from one of B's prompts → the answer rides at the
      top of the bid on B's side

### Rate limiting (server-enforced)
- ☐ A places bids rapid-fire → server throttles with a clear error toast, no crash
- ☐ Throttle lifts after the window; A can bid again

---

## 3 · Accept / decline → match (B decides, A sees result)

- ☐ B accepts A's bid → B feels success haptic, row moves to History, **match opens**
- ☐ On A: refresh Matches → **the match appears**
- ☐ A's photo is now **UNLOCKED** on B's side (lock overlay gone, real photo)
- ☐ B's opener message is present in the chat **on both devices**
- ☐ B's earnings ledger increments by the bid amount; **A's does not**
- ☐ A's My Bids shows the bid as **Accepted**
- ☐ B declines a different A bid → on A it shows **Passed**; **no** match created
- ☐ Bid Insurance: A's declined-and-insured bid refunds premium on A
- ☐ Accept is server-authoritative — if B accepts while offline, it does **not**
      mint on A until B reconnects and the write lands (no phantom match on A)

---

## 4 · Chat (bidirectional, the core loop)

- ☐ B's opener is visible to A on first open of the match
- ☐ A sends a message → on B: refresh → **A's message appears**, correct side/color
- ☐ B replies → on A: refresh → **B's reply appears**
- ☐ Message **order is identical** on both devices
- ☐ Timestamps are consistent (no reordering after a refresh — C4)
- ☐ A reacts (double-tap ❤️ or long-press bar) → on B: refresh → **reaction shows**
- ☐ B changes/removes the reaction → A sees the change after refresh
- ☐ Read receipts (A on Black Card): A sees **Delivered → Seen** after B opens
- ☐ Icebreaker strip only shows before the human's first real message; hidden
      once either side has sent one (and hidden when the other has no openers)
- ☐ Expiry: leave a match without replying past the window → **both** devices
      show the cold/expired banner; composer locks on both
- ☐ Sending into a cold match is blocked on both (server + view guard)
- ☐ Long message / emoji-only / whitespace-only (rejected) all behave on both

---

## 5 · Whisper-nod loop (A ⇄ B, the two-sided path)

- ☐ A whispers B → B's inbox shows the anonymous whisper
- ☐ B taps **Nod back** → B feels accept haptic; whisper moves to History
- ☐ On A: refresh My Bids → the whisper shows **nodded** (server-confirmed)
- ☐ A now places a **real bid** on B → lands in B's inbox as a normal pending bid
- ☐ No match is minted by the nod alone (only the real bid → accept mints)

---

## 6 · Reserve the date (A reserves, B sees it)

- ☐ Reserve card visible to **A only** (bidder), hidden for B, hidden on copycats
- ☐ A picks a tier → completes Stripe Checkout (or demo path if web shop off)
- ☐ On A: match row + chat header show **✓ Reserved** with the tier label
- ☐ On B: refresh → **✓ Reserved** appears on B's match row + chat header too
- ☐ Remote kill-switch off → Reserve card hidden on A fleet-wide (no rebuild)

---

## 7 · Trust & safety (cross-device enforcement)

- ☐ A blocks B → B **disappears from A's** floor/inbox/matches immediately
- ☐ Server-enforced: **B can no longer message A** — B's next send in the shared
      chat returns 403 and B's composer **freezes** with the "can no longer be
      messaged" banner (C6)
- ☐ A reports B → server records the report (verify in admin panel §admin)
- ☐ B blocks A reciprocally → same enforcement in the other direction
- ☐ Blocked user list on A shows B; unblock restores B on next floor refresh
- ☐ Message rate limit: B spams messages → server throttles with clear error

---

## 8 · Verification cross-effect

- ☐ B completes ID verification → server flips B's `verifiedAt`
- ☐ On A: refresh → **B shows the verified badge** on floor card + detail + match
- ☐ A's verified-only filter (Reserve) now **includes** B
- ☐ B's own profile reflects verified state after the `verified` push (§9)

---

## 9 · Push notifications (deep-link + auto-refresh)

Reliable Simulator method: grab each device's APNs token from the Xcode console
(logged on registration), then send with `simctl push` (payloads in the
appendix). Real devices can use the live Worker path directly.

For each: send to the **recipient** device, verify **foreground** (banner, no
auto-nav) and **background/locked tap** (deep-link) separately.

- ☐ `bid.received` → **B**: tap lands on B's **Bids** tab; inbox auto-refreshes
- ☐ `whisper.nodded` → **A**: tap lands on A's **My Bids** tab
- ☐ `bid.accepted` → **A**: tap lands on A's **Matches** tab; match present
- ☐ `message.received` → recipient: tap lands on Matches **and opens that
      match's chat** (matchId deep-link pushes the chat onto the nav path)
- ☐ `match.dateDone` → tap lands on Matches (rate-the-date prompt)
- ☐ `verified` → recipient: no navigation, badge updates, no crash
- ☐ Foreground banner does **not** auto-navigate (only the tap does)
- ☐ Deep link consumed once — redrawing the view doesn't re-navigate
- ☐ **Cold launch** from a notification tap routes correctly (kill app first)
- ☐ Permission denied on one device → that device still works via refresh; no
      repeated prompting
- ☐ Token re-registers on relaunch (kill + reopen, confirm new token logged)
- ☐ Malformed/empty `type` payload → ignored, no crash

---

## 10 · Concurrency & network edge cases

- ☐ A and B act **simultaneously** (A bids while B refreshes) → both consistent
      after a refresh, no dupes
- ☐ A bids while B is **mid-accept** on a previous bid → no lost/duplicated match
- ☐ Airplane-mode A mid-bid → error toast; on reconnect + refresh, state correct
      on both (no phantom bid on B, Gavels not stranded on A)
- ☐ Airplane-mode B mid-accept → no phantom match on A until B reconnects
- ☐ Both devices edit their profile → each other's floor view reflects the last
      synced state after refresh (last-write-wins, no corruption)
- ☐ Kill A mid-chat-send → message either sent (visible on B after refresh) or
      not sent (A can retry); never a half-sent duplicate
- ☐ Sign out on A → B's existing match with A stays; A returns to onboarding
- ☐ Delete account on A → server scrubs; on B, the match/chat with A degrades
      gracefully (no crash; "Match closed" or A drops from lists after refresh)

---

## 11 · Two-device parity sanity

- ☐ Same match's bid amount, phase tag, and reserved state read identically on
      both devices after both refresh
- ☐ Money never appears to move between users on either device (compliance)
- ☐ No copycat/AI content ever appears in a **real** cross-device session
      (copycats are sim-only — a real remote peer must never render as one)

---

## Appendix · `simctl push` payloads

1. Get the target sim's booted id: `xcrun simctl list devices | grep Booted`
2. Save a payload as `push.apns` (bundle id must match the app).
3. Send: `xcrun simctl push <device-udid> com.valasek.auctionbaby push.apns`

Keys mirror what the matching Worker sends — `type` drives routing; `bidId` /
`matchId` / `messageId` may sit at top level **or** nested under `data`
(the client checks both).

**Bid received → send to B**
```json
{
  "aps": { "alert": { "title": "New bid", "body": "Someone bid on you" }, "sound": "default" },
  "type": "bid.received",
  "bidId": "<uuid-of-the-bid>"
}
```

**Bid accepted → send to A**
```json
{
  "aps": { "alert": { "title": "You matched", "body": "She accepted your bid" }, "sound": "default" },
  "type": "bid.accepted",
  "bidId": "<uuid>",
  "matchId": "<uuid-of-the-match>"
}
```

**Message received → send to recipient (deep-links into the chat)**
```json
{
  "aps": { "alert": { "title": "New message", "body": "You have a message" }, "sound": "default" },
  "data": { "type": "message.received", "matchId": "<uuid>", "messageId": "<uuid>" }
}
```

**Whisper nodded → send to A**
```json
{
  "aps": { "alert": { "title": "She nodded back", "body": "Come back with a real bid" } },
  "type": "whisper.nodded",
  "bidId": "<uuid>"
}
```

**Verified → send to recipient**
```json
{ "aps": { "alert": { "title": "You're verified" } }, "type": "verified" }
```

> Swap `<uuid>` values for ids from a real row (read them from the Worker's D1
> tables or the client logs) so the deep-link actually resolves to a match/bid
> that exists on the recipient. A bogus `matchId` should degrade to the Matches
> tab without opening a chat — worth testing that fallback too.

---

### Sign-off

| Pass | A device | B device | Workers env | Date | Tester |
|------|----------|----------|-------------|------|--------|
|  1   |          |          |             |      |        |

**Gate:** §1–§9 green on one full A↔B pass, plus the §10 network cases, before
shipping a build that touches the matching/push path.
