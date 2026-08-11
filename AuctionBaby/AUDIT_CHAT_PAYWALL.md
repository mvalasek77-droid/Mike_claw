# Final Audit — Chat, Paywall & Location Matching

Static audit of the messaging surface (`ChatView` + store chat mechanics) and
the subscription paywall (`PaywallView` + `StoreKitService`), plus the answer
to "does the app match by closest location?" — followed by a deep-dive test
plan for each. No Swift toolchain here, so this is a code trace, not a run.

---

## 0. Does the app connect people by closest location?

**No — there is no proximity / distance matching.** No GPS, coordinates,
radius, or "nearest first." Confirmed in code:

- **Client** (`AuctionStore.refreshRemoteFloor`): passes the signed-in user's
  own free-text `location` string to the floor query (`location: me.location`).
- **Server** (`auth` Worker `GET /users/floor`): `AND LOWER(p.location) =
  LOWER(?)` — an **exact, case-insensitive string match** on the city text —
  then `ORDER BY p.updated_at DESC` (**recency**, not distance).

So the floor is: profiles whose **city text exactly equals yours**, newest-
active first. `location` is a typed label, not coordinates.

### ⚠️ Finding: exact-city matching is brittle (real product gap)
"New York" ≠ "New York, NY" ≠ "NYC" ≠ "Manhattan" ≠ "Brooklyn". Two people in
the same real city who typed it differently **will not see each other**. The
codebase already knows this: the leaderboard (`topBiddersInCity`) uses a fuzzy
`sameCity` token match *because* "Exact string equality made every real user's
leaderboard empty." **That fix was never applied to the dating floor** — the
floor still uses strict equality on the server. So:
- The floor and the leaderboard use *different* location logic (inconsistent).
- On a real, sparse user base, an exact-match floor can look empty or tiny.

**Status — (a) applied.** The server floor query now does **fuzzy city
matching**: a profile matches if its location text *contains any substantial
comma-token* (≥3 chars) of the searcher's location, case-insensitively, plus an
exact fallback — so "New York" now finds "Manhattan, New York" and "New York,
NY". 2-letter state codes are excluded (no whole-state over-match) and LIKE
wildcards are stripped from input. This is still a **text** match, not
proximity. **(b) real geocoding + distance ranking remains the v1.1 upgrade**
(what daters expect from "people near me"); logged for `ROADMAP_V11.md`.
Leading-wildcard `LIKE` is a table scan — fine at launch scale, index/geocode
later.

---

## 1. Chat audit (`ChatView` + `AuctionStore` chat)

**Verdict: sound.** The messaging state machine, remote/sim split, and safety
gates hold up. Details:

| Area | Result |
|---|---|
| Remote vs sim send | ✅ `sendDraft` routes remote→`sendRemoteMessage` (optimistic + rollback), sim→`store.send`; `isRemote` = signed-in + matching enabled |
| Optimistic + rollback | ✅ failed remote send restores the draft; **C6** freezes the composer on a 403 (block/DOB) with a clear banner instead of retry-against-a-wall |
| Message ordering / timestamps | ✅ **C4** preserves the local date when the server confirms a send, so messages don't reorder on refresh |
| Reactions | ✅ `toggleReaction` routes through `matchSlot` (mutates whichever of remote/sim holds the match); server sync fire-and-forget; toggles off on repeat |
| Expiry / cold match | ✅ store-level `send` guard (`!isExpired`) backs the composer lock; both sides show the cold banner |
| Opener reconciliation | ✅ accept awaits the opener send, adopts the server id, keeps the local date |
| Read receipts | ✅ Black Card only; woman side correctly skips the bidder-facing paywall CTA |
| Reserve card | ✅ bidder-only, hidden on copycats, gated on `isConsumablesConfigured && enabled` (kill-switch) |
| Icebreakers | ✅ shown only before the first human message AND only when the other party has openers (empty-row guard) |
| Block from chat | ✅ ReportSheet → `blockAndReport` → dismiss pops out of the closed match |
| Accessibility | ✅ message bubbles carry combined labels; typing bubble labeled; reduce-motion honored |

**Watch items (not bugs, verify at runtime):**
- **Message send retry gap** — if a remote opener/message send fails (429/
  network), the local placeholder can be overwritten by the next
  `refreshRemoteMatch` (a known gap noted in code; a retry queue is a follow-up).
- **Typing indicator is sim-only** — it won't appear cross-device; don't treat
  its absence in a two-phone test as a bug.
- **Reaction sync is fire-and-forget** — server truth reconciles on next
  refresh; a dropped sync self-heals but isn't guaranteed instantly.

## 2. Paywall audit (`PaywallView` + `StoreKitService`)

**Verdict: compliant and correct.** Guideline 3.1.2 elements are all present,
and the purchase/restore plumbing is the hardened StoreKit-2 pattern.

| 3.1.2 / correctness item | Result |
|---|---|
| Title, length ("/ month"), price (`displayPrice`) | ✅ per tier |
| Benefits / what's included | ✅ benefits matrix, tier-gated |
| Terms (EULA) + Privacy links | ✅ from `BackendConfig` — ⚠️ **blank until `AB_TERMS_URL`/`AB_PRIVACY_URL` are set** |
| Restore Purchases | ✅ toolbar |
| Auto-renew disclosure | ✅ footer |
| Suggested tier per trigger | ✅ (`readReceipts`→blackcard, `filters/rewind`→reserve, else paddle) |
| Benefits-matrix inclusion logic | ✅ correct tier-index comparison |
| Purchase outcome handling | ✅ success/cancelled/pending/failed distinct; no phantom credit on cancel |
| Demo path | ✅ `demoTier` local grant, no charge (App Review) |
| Money safety (grant/restore/revoke) | ✅ idempotent by `transaction.id`, credit-before-mark, revocation clawback |

**Watch items:**
- 🔴 **Set the two URLs** or the paywall's legal links render blank → 3.1.2
  rejection **and** a broken screenshot (frame 6). Single most important gate.
- **Button enable edge** — the CTA enables if *any* sub loaded even when the
  selected tier's product is missing; `subscribe()` guards `subscriptionProduct`
  and no-ops, so worst case is a tap that does nothing (minor).
- **`hasPass` in sandbox/demo** — a lingering `demoTier` or sandbox sub makes
  `atFreeLimit`/paywall behave as subscribed; reset between test passes.

---

## 3. Deep-dive test plan

### A. Chat — single device (Demo)
- ☐ Accept a bid → match opens with her opener; opener persists on refresh
- ☐ Send a message → appears instantly, correct side/color
- ☐ Rapid-send 5 messages → order stable, no dupes, timestamps monotonic
- ☐ Double-tap a bubble → ❤️; long-press → reaction bar; pick another → replaces;
      same again → removes
- ☐ Icebreakers show before your first message; vanish after; absent when the
      other party has none
- ☐ Let the reply window expire → cold banner + composer locks; sending blocked
- ☐ Reserve the date (demo) → ✓ Reserved on the chat header + match row
- ☐ Report & Block from the chat → pops to "Match closed"; user gone from lists
- ☐ Backgrounding mid-typed-draft → draft preserved on return
- ☐ VoiceOver reads each bubble; Dynamic Type xxxLarge doesn't clip

### B. Chat — cross-device (2 accounts, refresh-first)
- ☐ A sends → B refresh → message appears; B replies → A refresh → appears
- ☐ Reaction from A → visible to B after refresh; change/remove propagates
- ☐ Read receipts (A on Black Card) → Delivered→Seen after B opens
- ☐ A blocks B → B's next send 403-freezes B's composer (C6)
- ☐ Message rate limit → rapid sends throttled with a clear error
- ☐ message.received push → deep-links into that match's chat

### C. Paywall — StoreKit (sandbox)
- ☐ Open paywall from each trigger → correct suggested tier pre-selected
- ☐ Buy a Pass (sandbox) → entitlement active; usage card flips to "Unlimited"
- ☐ Cancel the purchase sheet → no entitlement, no phantom state
- ☐ Pending/Ask-to-Buy → handled without granting
- ☐ Restore Purchases → returns the entitlement on a clean install
- ☐ Terms + Privacy links open the hosted pages (needs URLs set)
- ☐ Auto-renew disclosure visible; matches the App Store description block
- ☐ Downgrade/upgrade across tiers resolves via subscription-group ranking
- ☐ Refund (sandbox/ASC) → entitlement + any Gavels clawed back
- ☐ Demo button (Demo Mode) → grants the tier free, no charge
- ☐ Free-bid limit: 4th pending bid → paywall (with NO active Pass/demoTier)

### D. Paywall — compliance sweep
- ☐ Every visible tier shows title + price + "/month"
- ☐ Restore present; disclosure present; links functional
- ☐ Same subscription facts appear in the App Store description
- ☐ Review screenshot per subscription product uploaded in ASC

---

## Summary
- **Location:** no proximity matching; exact city-text filter + recency. Brittle;
  inconsistent with the leaderboard's fuzzy match. v1.1 candidate.
- **Chat:** sound; three runtime watch-items (send-retry gap, sim-only typing,
  fire-and-forget reactions).
- **Paywall:** 3.1.2-compliant and money-safe; the one hard gate is setting the
  Terms/Privacy URLs.
