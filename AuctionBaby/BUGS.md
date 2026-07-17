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

## Sign-off (first sweep)

Two commits pushed:
1. `5ad2a78` — Fix P0 integer overflow + 12 P1 bugs from QA sweep
2. `16ef258` — Polish: VoiceOver toasts, accessibility labels, iOS 26 roadmap

Ready for TestFlight after a physical-device compile pass (this environment can't run Xcode).

---

# Sweep 2 — post-launch bundle

**Sweep date:** 2026-07-14
**Method:** Six-plus agents in successive waves audited photo uploads, IAP end-to-end, monetization + retention mechanics, mainstream + niche dating-app features, and every metadata surface. Findings triaged into implementation commits below.

## Shipped (feature commits)

| Commit | What |
|---|---|
| `d2efdb3` | **IAP refund gap closed** — client now polls Worker's `/refunds/pending` and claws Gavels back with a shared dedup set (`rev-<txID>`), restores on `REFUND_REVERSED`. Wrangler.toml KV placeholder story made loud. |
| `4275c8d` | **Multi-photo upload** — `PhotoUploadStep` (PhotosPicker, ≤ 6, primary/reorder, ≥600×600 gate, JPEG resize) wired into onboarding + Profile → Edit photos. Info.plist got `NSPhotoLibraryUsageDescription`. Metadata FACT fixes: Auction Credit 300–900 across docs; "Showcase score" UI card corrected to "Showcase Credit"; `Reserve+` → `Reserve`; privacy nutrition label qualified for the founder Worker. |
| `c4aa6ad` | **Reserve Requirements** — height/smoking/drinking/kids/education dealbreakers gated on Reserve tier; seeded on the sample floor via deterministic UUID-driven `Lifestyle`; Lifestyle card on woman detail view. Roadmap updated with the agent-flagged deferred P1s. |
| `13df7ff` | **Gavel Confirmed** — mutual meetup verification; corroborated reviews feed +72 (men) / +60 (women) into the credit reports. Toggle in `RateDateView`, seal on `ReviewRow`. |
| `dc98b53` | **Opening Bid Script + Whisper Bid** — Bumble-style woman-authored opener that auto-sends on accept + anonymous zero-Gavel signal that doesn't count against the free live-bid ceiling. Whisper seeded in the woman-side inbox for demo visibility. |
| `72b8fba` | **Lot of the Day + On the Floor Now** — full-screen daily intro sheet (`LotOfTheDayIntroSheet`) fires once per calendar day; live-presence dot on ~30% of non-copycat profiles, deterministic on (id, hour). Headliner banner rebranded. |
| `f8ea9bf` | **Bid Insurance + The Docket + The Standing** — 200-Gavel insurance premium with decline refund + Gilded credit; streak-freeze inventory + mystery-box daily rewards + 500-Gavel buy CTA; weekly cosmetic city leaderboards (`StandingView`) client-computed per-week. |

## Fixed (metadata + polish)

- **`179cb73` — metadata tear-down (four agents)**:
  - **PLIST:** `LSApplicationCategoryType` `lifestyle` → `social-networking` (dating-app category); `APP_STORE.md` primary/secondary category flipped.
  - **FACT:** README Masterpiece $9,999 → $1,000,000 (confused Masterpiece with plain Trillionaire verification); README "no IAP / no network" rewritten to match the shipped Worker + StoreKit; APP_STORE + ROADMAP "Showcase Score" → "Showcase Credit"; USER_BUG_REPORT placeholder-domain disclaimer + redirect to in-app flow.
  - **UI copy:** Sam Okafor prompt "The way to win me over" → "…over is"; DailyClaimCard "Day streak ready" fragment → "Daily streak ready"; British → US spelling (honoured/cancelled).
  - **Renames:** `AuctionStore.headliner` → `lotOfTheDay`, `HeadlinerBanner` → `LotOfTheDayBanner`, test renamed to `testLotOfTheDayIsRealAndOnFloor`, ROADMAP v1.0 bullet updated. Test credit ceiling assertion 850 → 900 (stale). ROADMAP "Whisper Bid" → "Whisper" (canonical UI); Gilded Bid Title Case; "ON THE FLOOR" chip → "ON THE FLOOR NOW"; non-user-facing Reserve+ → Reserve in code comments.

## Deferred backlog (unchanged from Sweep 1 unless noted)

Everything in Sweep 1's Deferred backlog (P2-4 through P2-13) still applies unless the ROADMAP or a later commit closed it. New deferrals from Sweep 2:

- **Motion Placard** (video prompts), **Call from the Floor** (voice prompts), **Floor Call** (voice notes in chat) — all need AVKit/mic permission + upload plumbing beyond this pass.
- **Podium Authentication** (live-selfie liveness) — needs `AVCaptureSession` + Vision; `NSCameraUsageDescription` already landed in Info.plist so it's ready when the code ships.
- **NSFW moderation** on uploaded photos — needs `SCSensitivityAnalyzer` integration; upload flow currently validates only size/dimensions.
- **Provenance Check / Provenance Report** — external services (ID verify, Garbo-style background check).
- **Wrangler KV namespace IDs** — `wrangler.toml` still ships placeholders. Two `wrangler kv namespace create KV` calls (prod + `--env staging`) needed before first deploy or the refund queue silently no-ops.
- **Backend secrets to xcconfig** — done in `Config/Secrets.xcconfig` (untracked, `.example` template committed, `Build.xcconfig` includes it optionally).

## Test harness

- `AuctionLogicTests` covers 60+ synchronous domain assertions; test renames landed in `179cb73`.
- `FlowTests` covers the async simulation flow.
- `StoreKitService` retains its `#if DEBUG` affordances.
- Backend `smoke-test.sh` for a full staging round-trip.

## Sign-off (Sweep 2)

Ten commits pushed since Sweep 1, all on `claude/auction-baby-dating-app-rezanv`. App is v1.0-feature-complete against the P1 bundle from the feature-gap agent's launch recommendation. Ready for TestFlight after a physical-device compile pass and provisioning of the KV namespace IDs + Secrets.xcconfig.

---

# Sweep 3 — full-feature QA (five parallel agents)

**Sweep date:** 2026-07-17
**Method:** Five agents traced every feature domain end-to-end: bidder flows, woman flows, retention features, money infrastructure, persistence/state machine. ~20 findings; all P0s and P1s fixed, P2s fixed where cheap.

## P0 — fixed

1. **Codable decode wipe (persistence agent).** Every struct in the snapshot graph used synthesized `Codable`; Swift's synthesized decoder throws on ANY missing key for non-optional fields — inline defaults don't help. Confirmed via git history: every release since the `auctionbaby.state.v5` key added non-optional fields (gilded, verified, archetype, lifestyle, minHeightCm, photoGallery, manConfirmedMet, isWhisper, insured, gavelConfirmed…) without a key bump, so upgrading decode-failed → silent total account wipe → next save() overwrites the good bytes → `appAccountToken` regenerates → server-side web-Gavel balance + refund queue orphaned. **Fix:** custom `init(from:)` with `decodeIfPresent` + defaults on Profile, Bid, Match, ChatMessage, DateReview, FilterPreferences (explicit memberwise inits preserved); `load()` now decodes BOTH stores and keeps the newer (`savedAt` stamp) so a failed archive write can't shadow fresher UserDefaults data; on total decode failure the raw bytes are stashed under a `.rescue` key before any save can clobber them.
2. **Bid Insurance money printer (two agents independently).** Decline payout was unconditionally `premium + gildedBidCost` (450) against a 200 premium — a guaranteed-decline farm minted +250 Gavels per cycle. **Fix:** payout = premium + (gild fee only if the bid was actually gilded); payout can never exceed spend. BidSheet copy updated.
3. **Concurrent web-Gavel sync double credit (money agent).** Launch `.task` and scenePhase `.active` fire `refreshPendingRefunds` nearly simultaneously; `@MainActor` doesn't exclude across `await`, so two overlapping syncs each drained the same balance under different idempotency keys → double wallet credit, no crash needed. **Fix:** `webGavelSyncInFlight` re-entrancy guard set synchronously before the first await.

## P1 — fixed

- **402 drain-retry black hole:** Worker's `/consume` 402 body is `{ok, reason}` but the client only decoded `{error}` → message "HTTP 402" → the `insufficient` check never matched → stale pending drain retried forever. Client now decodes both shapes.
- **`checkout.session.async_payment_succeeded` unhandled** in the consumables Worker — delayed payment methods (ACH/SEPA) would be charged but never credited. Now handled by the same credit routine.
- **Partial Stripe refunds debited the full pack.** Now proportional to the newly-refunded slice, cumulative-tracked per payment_intent (`refundedCents`), idempotent across repeated partial events.
- **Copycat presence leak:** copycats never showed "On the Floor Now," so absence-of-presence identified them over time. They now roll the same deterministic ~30%.
- **The Standing:** exact-string city match made real users' boards empty/single-row; pool read stale `SampleData` and ignored `blockedIDs`. Now: live roster, blocked filter, loose last-token city match, widen-to-floor fallback when < 3 rows, `photoData` on entries so the YOU row shows the uploaded photo.
- **SuitorDetailView leaked whisper anonymity** (identity dossier + "Accept $0" CTA one tap from the anonymous inbox row). Whispers now get a dedicated anonymous sheet with Nod back / Let it fade.
- **Summon-Trillionaire impostor:** with the seeded Trillionaire blocked, the fallback sent a $1M bid from a random man that could never mint. Now toasts "The Trillionaire isn't on your floor right now." instead.
- **`trillionaireVerified` only set on the match snapshot** — now also written to the live `bidders` roster so he stops reading "Pending" everywhere else.
- **Whispers leaked into MyBidsView rank/raise flow** ("$0" amount, always-outbid rank, a Rebid button that silently mutated the whisper). Whispers now show a dedicated status row, whisper badge, She nodded/Faded badges; `raiseBid` guards `isWhisper`.
- **`resetAccount` leaks:** now clears streakFreezeCount, lastLotOfDaySeen, pendingNodManIDs, autoRebid/priorityPlacement flags, pending web-drain + refund-dedup UserDefaults keys, the rescue blob — and rotates `appAccountToken` (a reset is a new identity).

## P2 — fixed

- Whispers excluded from the woman's demand dashboard (liveBidCount / totalOnTable / highestLiveBid / acceptedCount).
- DailyClaimCard reward preview now mirrors claimDaily's streak-freeze math exactly.
- Docket freeze copy scales to actual coverage ("covers N missed days").
- Auto-rebid capped at 3 rounds + amount clamped to maxStartingBid; whisper decisions run on a genuinely lighter 1.5–2.5s cadence.
- Whisper nod follow-up persisted (`pendingNodManIDs` in the snapshot) and re-armed in `load()`.
- Opening Bid Script hard-clamps at 240 chars live (no silent truncation at save).
- Store-level expiry guard in `send()` (composer lock was view-only).
- Stale "copycats are flagged in place" comment corrected to the actual no-pre-bid-labelling rule.

## Deferred (documented, not fixed)

- Chat simulation timers (`scheduleSuitorReply`/read receipts) aren't re-armed on relaunch — cosmetic, no money at risk.
- Expired matches never transition to `.closed` — they sit dimmed with a locked composer, acceptable.
- `buyStreakFreeze` has no inventory cap — product decision (monetization escape valve vs. streak-pressure purity).
- EncryptedArchive key is device-only while the archive file can ride device backups — new-phone restores fall back to the UD path by design; revisit with real accounts.
