# Auction Baby — QA Sweep Bug Log

**Sweep date:** 2026-07-13
**Commits:** `5ad2a78` (P0 + P1 fixes), `16ef258` (P2 polish + roadmap)
**Branch:** `claude/auction-baby-dating-app-rezanv`
**Method:** Six agents split across the app (bidder side, woman side, safety, payments, polish, roadmap) audited every flow, then findings were triaged into P0/P1/P2 and fixed in one coherent pass.

---

## P0 — Crash (1 finding)

### P0-1 · Integer overflow in `startingBid`
- **File:** `AuctionStore.swift:449` (`setStartingBid`), `AuctionStore.swift:826` (`seedIncomingBids`), `AuctionStore.swift:510` (`summonBidder`)
- **Failure scenario:** Woman opens onboarding, enters `Int.max` (or any absurd number) as her floor. On seeding, `(me.startingBid ?? 150) * 2` overflows → EXC_BAD_INSTRUCTION → hard crash on registration.
- **Fix:** Introduced `AuctionStore.maxStartingBid = 10_000_000`. All entry points clamp to this ceiling; overflow-safe `&*` used in the seed multiplication.
- **Status:** ✅ Fixed in `5ad2a78`

---

## P1 — Correctness / money / retention (12 findings)

### P1-1 · Blocked man reappears via `summonBidder`
- **File:** `AuctionStore.swift:502-527`
- **Failure scenario:** Woman blocks a bidder → later taps "Summon a bidder" → the block is not honoured because `summonBidder` sampled from the raw pool.
- **Fix:** Pool now filtered by `blockedIDs` before sampling; empty pool early-returns.
- **Status:** ✅ Fixed

### P1-2 · Boost "Extend" resets the timer instead of extending
- **File:** `AuctionStore.swift:363-372`
- **Failure scenario:** Woman/man is 25 min into a 30-min Boost, taps Extend, gets 30 min (loses 25 min they paid for).
- **Fix:** When already boosted, base the new expiry on the current `boostUntil` (not `Date.now`), so paid time is preserved.
- **Status:** ✅ Fixed

### P1-3 · `completeAsWoman` discards the woman's review text/stars
- **File:** `AuctionStore.swift:659-701`
- **Failure scenario:** Woman writes a review with stars + text after a date; her ratings never appear on the man's record because the `stars`/`text` parameters weren't referenced.
- **Fix:** Woman's stars + text now written to the man's `reviews` array via the bidders roster.
- **Status:** ✅ Fixed

### P1-4 · Earnings never reversed on deadbeat verdict
- **File:** `AuctionStore.swift` (`completeAsWoman`)
- **Failure scenario:** Woman accepts a bid → `earnings += amount` at acceptance. Man is later flagged deadbeat. Earnings stayed inflated, misrepresenting real cash-in-hand.
- **Fix:** On `paid == false`, `earnings = max(0, earnings - bid.amount)`.
- **Status:** ✅ Fixed

### P1-5 · Demo fallback "+10,000 Gavels" button ungated
- **File:** `GavelStoreView.swift:124-132` (`unavailableCard`)
- **Failure scenario:** Production user with poor connectivity hits the store while products haven't loaded → sees "Demo: +10,000 Gavels" button → free currency in a live build.
- **Fix:** Button now gated on `store.demoMode`.
- **Status:** ✅ Fixed

### P1-6 · Daily claim card promises the wrong reward
- **File:** `DailyClaimCard.swift:10-20`
- **Failure scenario:** User misses a day → their streak resets to 1 on next claim, but the card still previewed `dailyStreak + 1`, so the reward number displayed did not match what was actually credited.
- **Fix:** `nextReward` now checks whether the streak will continue (via `lastDailyClaim` +1 day comparison) and previews accordingly.
- **Status:** ✅ Fixed

### P1-7 · Simulation timers not re-armed after relaunch
- **File:** `AuctionStore.swift:917-921` (`load`)
- **Failure scenario:** User places a bid, kills the app before the 2.5–4s decision timer fires. On relaunch the bid stays `.pending` forever ("Live" with no resolution).
- **Fix:** After `load()` restores state, iterate `outgoingBids` and re-schedule `scheduleWomanDecision` for every pending bid.
- **Status:** ✅ Fixed

### P1-8 · Lapsed Pass leaves premium filters stuck ON
- **File:** `FiltersView.swift:59-116`
- **Failure scenario:** User had Reserve, enabled `verifiedOnly` + interest chips, cancelled the sub → toggle became `.disabled`, so they couldn't turn it off. Floor filtered on filters they no longer had access to.
- **Fix:** Toggle now always allows OFF; only tries to turn ON when subscribed (otherwise opens paywall). "Clear premium filters" button appears when stuck values are detected.
- **Status:** ✅ Fixed

### P1-9 · Advanced filters gated on wrong tier
- **File:** `FiltersView.swift:60-79`
- **Failure scenario:** Marketing copy in `PaywallView.benefits` says filters are a **Reserve** perk, but code gated on `storeKit.hasPass` (any Pass, including Paddle) — so Paddle buyers got a perk they didn't pay for.
- **Fix:** New `hasReserve` computed check gates the entire advanced-filter card on `.reserve` or `.blackcard`.
- **Status:** ✅ Fixed

### P1-10 · Phantom perk — reserve price reveal
- **File:** `AuctioneeDetailView.swift`
- **Failure scenario:** Paywall advertised "Reveal her reserve price" as a Reserve+ perk; code had no reveal anywhere.
- **Fix:** Added a `hasReserve`-gated card on the woman detail view showing her `startingBid` under the "Her reserve price" label, styled to match the perk marketing.
- **Status:** ✅ Fixed

### P1-11 · Phantom perk — auto-rebid on decline
- **File:** `AuctionStore.swift:786-808`, `AuctionBabyApp.swift:26-33`
- **Failure scenario:** Paywall promised "Auto-rebid to stay on top" for Reserve+; no such code existed.
- **Fix:** Added `autoRebidEnabled` flag on `AuctionStore`; app root syncs it from `storeKit.activeTier`. When a Reserve+ bidder is declined on a non-copycat, an auto-rebid at +20% is placed and its own decision scheduled.
- **Status:** ✅ Fixed

### P1-12 · Phantom perk — priority placement (Black Card)
- **File:** `AuctionStore.swift:762-764`, `AuctionBabyApp.swift`
- **Failure scenario:** Paywall promised "Priority placement in every inbox" for Black Card; had no effect on acceptance odds or sort order.
- **Fix:** Added `priorityPlacementEnabled` flag; app root wires it to Black Card. Simulation now adds a +0.20 acceptance bonus when set.
- **Status:** ✅ Fixed

---

## P2 — Polish / accessibility (shipped this pass)

### P2-1 · Toasts not announced to VoiceOver
- **File:** `GlassKit.swift:154-172`
- **Fix:** `ToastView.onAppear` posts a `UIAccessibility.announcement`. Also carries an explicit `accessibilityLabel`.

### P2-2 · Missing accessibility labels on FloorCard
- **File:** `AuctionFeedView.swift:169-244`
- **Fix:** `.accessibilityElement(children: .combine)` + a semantic label ("`{name}, {age}, {location}, verified, starting bid ...`"). "Bid" button carries its own label.

### P2-3 · Missing accessibility labels on BidRow
- **File:** `IncomingBidsView.swift`
- **Fix:** Semantic label including bidder identity (or "Hidden bidder"), amount, gilded state, verified state, and credit score.

---

## P2 — Polish (backlog, not yet shipped)

These were flagged by the sweep but deferred because they're non-blocking or better done together with the iOS 26 Liquid Glass theme pass:

| # | Area | Item |
|---|---|---|
| P2-4 | Accessibility | Dynamic Type support on 26pt+ heavy headers |
| P2-5 | Accessibility | WCAG contrast audit — `Theme.inkFaint` on glass falls below 4.5:1 on the lightest sheets |
| P2-6 | Accessibility | VoiceOver reading order in `MatchCelebrationView` |
| P2-7 | UI | iPad targeting: full-width sheets on regular width; `.presentationDetents` don't help there |
| P2-8 | Perf | Image cache: `AvatarView` re-renders full-res for the small circle sizes |
| P2-9 | UX | Celebration queue when two accepts land inside a frame |
| P2-10 | UX | Match expiry enforcement — the 24h `expiresAt` isn't actually enforced anywhere |
| P2-11 | UX | Dead footer links — `auctionbaby.app/terms` + `/privacy` are placeholders |
| P2-12 | UX | Woman-side inbox: sort by priority-placement bonus explicitly, not just by amount |
| P2-13 | Roadmap | iOS 26 Liquid Glass theme pass — 8 concrete items now in `ROADMAP.md` |

---

## Not reproduced / no action

- **Report wiring to backend:** `SafetyCenterView` and `ReportSheet` correctly call `store.blockAndReport`, which handles local state. Backend `handleReport` exists; wiring `blockAndReport` → `BackendService.report(...)` is a v1.1 item (needs live worker URL first).
- **Blocked user messaging:** Confirmed matches with blocked profiles are removed by `blockAndReport`; no dangling channels exist.

---

## Test harness

- `AuctionLogicTests` (`AuctionBaby/AuctionBabyTests/AuctionLogicTests.swift`) covers 60+ synchronous domain assertions.
- `StoreKitService` has `#if DEBUG` affordances: `suspendListenerForTesting`, `resetForTesting()`, `drainPendingForTesting()`, `simulateRefundForTesting(productID:)`.
- Backend has `smoke-test.sh` for a full staging round-trip.

## Sign-off

Two commits pushed:
1. `5ad2a78` — Fix P0 integer overflow + 12 P1 bugs from QA sweep
2. `16ef258` — Polish: VoiceOver toasts, accessibility labels, iOS 26 roadmap

Ready for TestFlight after a physical-device compile pass (this environment can't run Xcode).
