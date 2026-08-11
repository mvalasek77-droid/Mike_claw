# Deep Test Checklist — Paywall & Chat

Every checkbox is traced to real behavior in `PaywallView.swift`,
`StoreKitService.swift`, `ChatView.swift`, and the store. Run **Demo Mode**
(name = `demo`) for the single-device passes and **sandbox** for money paths.
Reset between passes: relaunch with `-uiTestReset` (DEBUG) or delete + reinstall
so no stale `demoTier` / sandbox sub bleeds across runs.

Legend: ☐ to run · 🔴 must-pass gate · 💰 money-safety · ♿ accessibility

---

# PART 1 — PAYWALL

## 1.1 Trigger → pre-selected tier (the conversion core)
Open the paywall from each entry point; confirm the **suggested tier is
pre-highlighted** and the headline/icon match. Mapping is in `PaywallTrigger`.

- ☐ `.rankReveal` (tap locked "am I winning?" rank row) → **Paddle** pre-selected; headline "She's comparing bids…", icon `chart.bar.fill`
- ☐ `.bidLimit` (spend all free bids, place one more) → **Paddle**; "Out of free bids…", `hand.raised.slash.fill`
- ☐ `.filters` (open a premium filter) → **Reserve**; "Cut the noise…", `slider.horizontal.3`
- ☐ `.readReceipts` (chat → "Did she read it?") → **Black Card**; "She read it…", `checkmark.message.fill`
- ☐ `.rewind` (undo a bid without Reserve) → **Reserve**; "Bid too soon?…", `arrow.uturn.backward.circle.fill`
- ☐ `.general` (store → Upgrade) → **Paddle**; "Win the bid you can't see", `crown.fill`

## 1.2 Tier picker
- ☐ Tap each of the 3 cards → selection moves; selected card gets gold tint, gold border, `1.03` scale; haptic fires
- ☐ Price shows StoreKit `displayPrice` when products loaded; falls back to `$19.99 / $39.99 / $99.99` only when not loaded
- ☐ "/ month" renders under every price
- ☐ Long tier titles don't clip (`minimumScaleFactor(0.7)`, `lineLimit(1)`)

## 1.3 Benefits matrix (inclusion logic)
Selecting a tier must light up **exactly** the benefits at that tier and below
(`tiers.firstIndex(of: benefit) <= tiers.firstIndex(of: selected)`).

- ☐ **Paddle** selected → first 3 rows ✓ (Unlimited bids, top-bid, 1 Boost/wk); the other 6 show 🔒 with the required-tier chip ("Reserve"/"Black Card")
- ☐ **Reserve** selected → first 7 rows ✓ (adds reserve price, auto-rebid, filters, rewind); last 2 🔒 "Black Card"
- ☐ **Black Card** selected → all 9 ✓, no lock rows
- ☐ Locked rows show the correct **upgrade chip** naming the lowest tier that unlocks them

## 1.4 CTA states
- ☐ Not subscribed, products loaded → "Continue with <tier>" enabled; Black Card uses the prestige gradient, others gold
- ☐ Already subscribed to the selected tier → CTA replaced by "**<tier> is active**" seal (no purchase button)
- ☐ 🔴 Products **not** loaded (sim without `.storekit` config) → button still enabled if *any* sub loaded (known edge), but `subscribe()` guards `subscriptionProduct` and **no-ops safely** — a tap does nothing, never a crash or phantom charge. The "Products load from the App Store…" helper line shows when `subscriptionProduct == nil`
- ☐ `isWorking` → full-screen dimmed `ProgressView` overlay blocks double-taps

## 1.5 Purchase outcomes (sandbox) 💰
Buy the selected Pass; verify each StoreKit result is handled distinctly
(`PurchaseOutcome`).

- ☐ **success** → success haptic + "Welcome to <tier>…" toast + sheet dismisses; entitlement active; benefits/usage reflect it
- ☐ **userCancelled** → no toast, no entitlement, **no phantom state**, sheet stays open
- ☐ **pending** (Ask-to-Buy / SCA) → no grant; resolves later via `Transaction.updates` when approved
- ☐ **failed** (network drop mid-purchase) → `errorMessage` set, no entitlement, retry works
- ☐ Buy while a different tier is active → subscription-group ranking resolves (upgrade/downgrade), not a second charge

## 1.6 Restore
- ☐ Toolbar **Restore** → `AppStore.sync()` + drain; prior entitlement returns on a clean install
- ☐ Restore with nothing to restore → no error, no false entitlement
- ☐ Restore prompts for Apple ID password (Apple requirement for sub apps)

## 1.7 Demo CTA (App Review path)
Only visible when `store.demoMode` and the tier isn't already active.

- ☐ "Demo: activate <tier> free" → `demoTier` set, success haptic, "Demo <tier> active — no charge" toast, dismiss
- ☐ Demo grant persists across relaunch (`demoTierKey`)
- ☐ Demo grant makes `hasPass` / `isSubscribed` true **without any charge** — reviewer can exercise Black Card read-receipts + top tier
- ☐ 🔴 Demo button is **absent** in a non-demo (real) build → reviewers can't get it free by accident, real users can't either

## 1.8 Footer & 3.1.2 compliance sweep 🔴
- ☐ Auto-renew disclosure present verbatim: "Auto-renews monthly until canceled at least 24h before…"
- ☐ **Terms** link opens `BackendConfig.termsURL`; **Privacy** opens `privacyURL` — 🔴 both **blank if `AB_TERMS_URL`/`AB_PRIVACY_URL` unset** (Step 3 of the runbook); must render + open the hosted pages
- ☐ Every visible tier shows title + price + "/month"
- ☐ Restore present; disclosure present; links functional
- ☐ The same subscription facts (name, price, period, benefits) appear in the App Store description block (`ASC_METADATA.md`)
- ☐ A per-subscription **review screenshot** is uploaded in ASC

## 1.9 Money-safety invariants 💰 (StoreKitService)
- ☐ Kill the app mid-purchase before `finish()` → relaunch drains `Transaction.unfinished`, credit lands once, never double
- ☐ Same transaction replayed → `processed` set keyed by `transaction.id` blocks a second credit
- ☐ Refund a Gavel pack (ASC sandbox) → `checkRevocation` claws back exactly the pack's Gavels once (`rev-<id>` dedupe)
- ☐ Refund a **status archetype** → badge drops to best still-owned tier (`onStatusRevoked`)
- ☐ Buy a Gavel pack before the wallet hook is wired (cold launch) → `grant` returns false, tx stays unfinished, post-wiring drain credits it (buyer never loses money)
- ☐ Consumable credits **before** it marks processed (crash overpays, never under-credits)

## 1.10 IAP-wide sandbox matrix (all 16 products) 💰
For **each** product id (3 subs, 4 Gavel packs, 1 Boost, 8 status): buy → restore → cancel → interrupted.
- ☐ Gavel packs credit 1,000 / 5,000 / 14,000 / 30,000 respectively
- ☐ `boost.spotlight` grants a 30-min Boost via `onBoost`, no Gavels
- ☐ Each status archetype equips its badge on purchase (`onStatusPurchased`) and is owned forever (re-wear free)
- ☐ 🔴 `status.trillionaire` at **$9,999.99** requires ASC custom pricing; verify it loads a live `displayPrice` and purchases in sandbox

## 1.11 ♿ Paywall accessibility
- ☐ VoiceOver reads each tier (title, price, selected state) and benefit rows
- ☐ Dynamic Type xxxLarge → tiers/benefits don't clip or overlap
- ☐ Dark + light mode both legible; gold/rose contrast holds
- ☐ Reduce Motion → hero/appear animations respect `Motion.prefersReducedMotion`

---

# PART 2 — CHAT

## 2.1 Entry & remote-vs-sim resolution
`isRemote = !demoMode && matching.isEnabled`. Sim path only for Demo/local-only.

- ☐ Demo Mode match → sim path (`store.send`), no Worker calls
- ☐ Signed-in + matching wired → remote path; `.task(id:)` fires `refreshRemoteMatch`
- ☐ 🔴 **Cold tap-through-push** into a match not yet in `remoteMatches` → ChatView still loads and `refreshRemoteMatch` inserts the row (no permanent "Match closed")
- ☐ Truly missing match (closed/blocked) → "Match closed" empty state, not a crash

## 2.2 Sending (optimistic + rollback) 💰-adjacent
- ☐ Send a message → appears instantly on the right (gold gradient), draft clears, auto-scrolls to bottom
- ☐ Send button disabled when draft is empty/whitespace (`0.5` opacity) and while `sending`
- ☐ Remote send **fails** (network/429) → draft is **restored** into the field, message doesn't stick
- ☐ 🔴 **C6 freeze**: remote send returns 403 with "can't be delivered" → composer replaced by "This match can no longer be messaged" lock banner (no infinite retry)
- ☐ Rapid-send 5 messages → order stable, no dupes, each scrolls into view
- ☐ Multi-line draft grows 1→4 lines then scrolls (`lineLimit(1...4)`)

## 2.3 Message ordering & timestamps
- ☐ Server confirm of a sent message **preserves the local date** (C4) → no reorder/jump on refresh
- ☐ New message → `onChange(messages.count)` scrolls to `"bottom"`
- ☐ On open, view starts pinned to bottom (`onAppear` scrollTo)

## 2.4 Reactions
- ☐ **Double-tap** a bubble → ❤️ with bouncy animation + haptic
- ☐ **Long-press** → 5-emoji reaction bar (❤️ 😂 😮 👍 🔥) slides in
- ☐ Pick a different emoji → replaces the existing reaction; bar closes
- ☐ Toggle the same emoji again → removes it (`toggleReaction` off-on-repeat)
- ☐ Reaction routes through `matchSlot` (remote or sim, whichever holds the match)
- ☐ Reaction badge overlays the correct corner (mine bottom-leading, theirs bottom-trailing)
- ☐ Server sync is fire-and-forget → a dropped sync self-heals on next `refreshRemoteMatch` (don't treat brief desync as a bug)

## 2.5 Icebreakers (visibility rules)
Shown only when the **other** party has openers AND you haven't sent a real
(non-system) message yet.

- ☐ Woman with icebreakers, before your first message → "NEED AN OPENER?" chip row; tapping a chip fills the draft
- ☐ After you send one real message → chips vanish
- ☐ Other party has **no** icebreakers (common for men) → no empty header/row renders
- ☐ Chips scroll horizontally, don't wrap/clip

## 2.6 Expiry / cold match
- ☐ Open reply window → live countdown banner "Reply within mm:ss or this goes cold" (monospaced digits)
- ☐ Window expires → snowflake "This match went cold…" banner; composer swaps to the locked "No replies land here anymore" state
- ☐ Store-level `send` guard (`!isExpired`) blocks any send even if UI is stale
- ☐ Both bidder and woman see the cold state

## 2.7 Read receipts
- ☐ **Black Card** holder, last message is yours → "Delivered" then "Seen" (`seenByOther`) with verify tint
- ☐ Non-subscriber **man** → "Did she read it?" 🔒 teaser → tap opens `PaywallView(.readReceipts)` pre-set to Black Card
- ☐ 🔴 **Woman side** → shows Delivered/Seen if she's Black Card, but **never** the bidder-facing "Did she read it?" paywall CTA (copy would be wrong)
- ☐ Receipt only renders when `phase == .chatting` and last message `fromMe`

## 2.8 Reserve-the-date card (bidder-only)
- ☐ 🔴 **Woman never sees** the Reserve card (whole `reserveCard` gated `role == .man`)
- ☐ 🔴 **Hidden on copycats** (`!match.bid.onCopycat` wraps it + the date-done button)
- ☐ Live: shows only when `backend.isConsumablesConfigured && reserveEnabled` (kill-switch) — otherwise dormant even for men
- ☐ Demo: seeds the 5 tiers ($10/15/25/50/100), picker works, "Demo: reserve free" marks booked with no Stripe
- ☐ Live: tier selected → "Reserve for $X" → opens Stripe Checkout in Safari; on return, next foreground reflects reserved (`refreshReservations`); `about:blank` = already booked server-side → marks reserved directly
- ☐ Disclosure copy present: booking fee "goes to Auction Baby… never to <her name>… unlocks nothing in the app"
- ☐ Button disabled until a tier is chosen (`selectedTierCents == nil` → 0.5 opacity)
- ☐ Reserved → card flips to "Date reserved — you're locked in"; bid banner shows the ✓ seal + reserved label

## 2.9 Date lifecycle (phase machine)
- ☐ `.chatting` → composer + "We went on the date" ghost button (hidden on copycat)
- ☐ Tap "We went on the date" → `markDateDone` → phase `.dateDone` → composer becomes "Leave your review" (rose for woman, gold for man)
- ☐ Submit review → phase `.closed` → "Reviews posted · lot closed" footer, no composer
- ☐ Review sheet presents at `.large` with material background

## 2.10 Report & block
- ☐ Toolbar ⋯ → "Report & Block" → ReportSheet at medium/large detent
- ☐ Complete report → `blockAndReport` scrubs the match from `remoteMatches` → `onReported` pops out of ChatView (doesn't strand on "Match closed")
- ☐ Blocked user gone from floor, matches, and can't message back (their next send 403-freezes them, C6)

## 2.11 Bid banner & header
- ☐ Banner shows "Accepted bid · $amount"; "· Copycat" tag when `onCopycat`
- ☐ Header shows other's avatar + name + verified badge (if verified), revealed
- ☐ Reserved → seal + reserved label in the banner

## 2.12 Typing indicator
- ☐ Sim reply pending → 3-dot bouncing TypingBubble; scrolls into view
- ☐ **Sim-only** — won't appear cross-device; its absence in a 2-phone test is **not** a bug
- ☐ Reduce Motion → dots don't bounce (`Motion.prefersReducedMotion` guard), bubble still shows

## 2.13 ♿ Chat accessibility
- ☐ Each bubble VoiceOver-reads "You/<name>: <text>, reacted <emoji>"
- ☐ Typing bubble labeled "Typing"
- ☐ Dynamic Type xxxLarge → bubbles wrap, don't clip; composer stays usable
- ☐ System messages centered, read as plain text

## 2.14 Backgrounding / resilience
- ☐ Background with a typed (unsent) draft → return → draft preserved
- ☐ Background mid-chat → foreground → `refreshRemoteMatch` reconciles without dupes
- ☐ Kill + relaunch into the match → history intact, pinned to bottom

---

# PART 3 — CROSS-DEVICE (2 accounts, refresh-first)

- ☐ A sends → B refresh → appears; B replies → A refresh → appears
- ☐ Reaction from A → visible to B after refresh; change/remove propagates
- ☐ Read receipts (A on Black Card) → Delivered→Seen after B opens
- ☐ A blocks B → B's next send **403-freezes B's composer** (C6)
- ☐ Rate limit → rapid remote sends throttled with a clear error, draft restored
- ☐ `message.received` push → deep-links into that match's chat (use `push-payloads/4-message.received.apns`)
- ☐ `bid.accepted` push → opens the new match's chat (`push-payloads/3-*`)

---

## Known watch-items (verify, don't file as bugs)
- **Send-retry gap** — a failed remote opener/message can be overwritten by the next `refreshRemoteMatch`; a retry queue is a follow-up, not a v1 blocker.
- **Typing is sim-only** — never cross-device.
- **Reactions are fire-and-forget** — reconcile on next refresh.
- **CTA-enabled edge** — button can enable with the selected product missing; `subscribe()` no-ops, so worst case is an inert tap.

## Pass criteria
All 🔴 gates green, all 💰 invariants hold across kill/restore/refund, and the
3.1.2 sweep (§1.8) complete **with the Terms/Privacy links rendering** — that
last one is the single hardest paywall gate and depends on the runbook's Step 3.
