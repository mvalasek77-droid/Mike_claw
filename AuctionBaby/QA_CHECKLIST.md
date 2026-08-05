# Auction Baby — Deep-Dive QA Checklist

Every process, every edge case. Run this on a physical device **and** the
simulator before each App Store submission. Check both roles (bidder = man,
lot = woman) and both modes (Demo Mode + signed-in remote).

Legend: ☐ untested · ✅ pass · ❌ fail (file in BUGS.md) · ➖ N/A

---

## 0 · Pre-flight (build & environment)

- ☐ Clean build succeeds (`⌘⇧K` then `⌘B`) with zero warnings
- ☐ `⌘U` full test suite green
- ☐ "Sign in with Apple" capability present in Signing & Capabilities
- ☐ "Push Notifications" capability present; `.entitlements` generated
- ☐ `Config/Secrets.xcconfig` populated (backend URLs, `AB_TERMS_URL`, `AB_PRIVACY_URL`)
- ☐ No secrets or admin credentials committed (`git log -p | grep -i password`)
- ☐ Version + build number bumped (`CFBundleShortVersionString`, `CFBundleVersion`)
- ☐ Runs on min deployment target (iOS 17) — no iOS 18/26-only API crashes
- ☐ Runs on newest simulator (iOS 26 Liquid Glass path exercised)
- ☐ Runs on smallest device (iPhone SE) and largest (Pro Max) without clipping

---

## 1 · Onboarding & auth

- ☐ Fresh install → onboarding appears (no stale state leaking through)
- ☐ Sign in with Apple happy path → lands on correct role's home tab
- ☐ SIWA cancel/abort → returns to onboarding gracefully, no crash
- ☐ SIWA "Hide My Email" relay address handled
- ☐ DOB gate: under-18 DOB is **rejected**, cannot proceed
- ☐ DOB gate: exactly 18 today passes; 17 + 364 days fails
- ☐ Role selection (man vs woman) persists across relaunch
- ☐ Skip-to-Demo path works without Apple sign-in
- ☐ Keychain: token survives app kill + relaunch (stays signed in)
- ☐ Sign out clears token; next launch shows onboarding
- ☐ Delete Account removes server data and returns to onboarding
- ☐ Re-register after delete works (no orphaned unique-constraint error)

---

## 2 · Bidder (man) flows

### Floor browsing
- ☐ Floor loads (sim seed in Demo, real profiles when signed-in)
- ☐ "Real people on the floor" chip appears only when `isRemoteFloor`
- ☐ Pull-to-refresh refetches floor
- ☐ Cards rise-in with staggered animation; no jank on fast scroll
- ☐ ScaleButtonStyle press feedback on every FloorCard tap
- ☐ Copycat profiles render identically to real ones (no pre-bid label)
- ☐ Tapping a card opens AuctioneeDetailView
- ☐ Multi-photo gallery pager swipes; page dots correct
- ☐ Lot of the Day banner shows once/day; intro sheet fires first open only

### Filters
- ☐ Filter sheet opens; sliders move
- ☐ Active filter count badge accurate
- ☐ Closing sheet refetches remote floor with new age/verifiedOnly bounds
- ☐ Filters that hide everyone → EmptyState with pulse animation
- ☐ Location filter narrows floor correctly

### Placing bids
- ☐ Bid sheet opens; amount pre-fills to floor (or 100 if no floor)
- ☐ Quick-add chips (+50 … +100k) increment with selection haptic
- ☐ Reset chip restores starting bid
- ☐ **`Haptics.bidPlaced()` two-beat fires on submit** (heavy → light)
- ☐ Regular bid → appears in My Bids as pending
- ☐ Gilded bid → gold ribbon; Gavels deducted correctly
- ☐ Insufficient Gavels for gild → blocked with clear message
- ☐ Bid Insurance toggle → premium deducted; refund on decline verified
- ☐ Whisper Bid → anonymous, free, no credit hit; hidden on copycats
- ☐ Prompt-context bid → her answer rides at top of the bid
- ☐ Masterpiece-eligible callout shows only for trillionaire ≥ threshold
- ☐ **Free bid limit**: cannot exceed `freeActiveBidLimit` without Pass
- ☐ Free limit reached → paywall CTA + whisper fallback offered
- ☐ Free limit **not bypassable** by killing/relaunching app (seeded at launch)

### My Bids
- ☐ Pending / accepted / declined states render correctly
- ☐ Tab badge = active pending count; updates live on push
- ☐ Declined bid with Insurance shows refund
- ☐ Whisper nodded → routes to correct notification/tab

### Status store (archetypes / Gavels)
- ☐ Archetype store lists tiers with correct pricing
- ☐ Purchasing an archetype updates profile + badge
- ☐ Gavel wallet balance accurate after every spend
- ☐ Boost purchase → countdown timer shows; expires correctly

---

## 3 · Lot (woman) flows

### Inbox
- ☐ Inbox loads (remote when signed-in, sim otherwise)
- ☐ Pending bids sorted: gilded first, then by amount
- ☐ Tab badge = pending count; updates live on push
- ☐ Bidder photo **stays locked** until accept (lock overlay shown)
- ☐ Stats forward: credit, deadbeat score, archetype visible pre-accept
- ☐ Whisper rows show "Someone whispered" with nod-back CTA
- ☐ Gilded bids show gold ribbon
- ☐ "What his bid actually means" explainer present
- ☐ Highest live bid + accepted earnings header accurate

### Accept / decline
- ☐ Accept → **`Haptics.accept()` success** fires; photo unlocks; match opens
- ☐ Decline/Pass → **`Haptics.decline()`** fires; row moves to history
- ☐ Whisper "Nod back" → `Haptics.accept()`; draws real bid path
- ☐ Whisper "Let it fade" → `Haptics.decline()`; fades to history
- ☐ Remote inbox: accept/decline hits Matching Worker, not sim array
- ☐ `nodAtWhisper` guarded on remote inbox (no phantom sim mutation)
- ☐ Summon menu **hidden** when inbox is remote (Demo-only affordance)
- ☐ EmptyState message differs remote vs Demo

### Earnings / listing
- ☐ Earnings total accurate after accepts
- ☐ Starting bid / no-floor toggle reflected on own card
- ☐ Showcase credit + Art Tier render correctly

---

## 4 · Matches & chat

- ☐ Matches list loads; empty state message role-correct
- ☐ ScaleButtonStyle press on each MatchRow
- ☐ MatchRow avatar shows revealed remote photo (not locked)
- ☐ Last message preview + amount + phase tag correct
- ☐ Expiry countdown ticks; expired match dims to 0.55 opacity
- ☐ Tapping a match opens ChatView with correct partner name
- ☐ Chat: send message → appears instantly, persists on refresh
- ☐ Message timestamps preserved across refetch (no reordering)
- ☐ Reactions persist server-side; survive relaunch
- ☐ Chat principal toolbar avatar shows partner photo
- ☐ Reserve the Date: tier picker → reservation; ✓ Reserved checkmark on
      match list **and** chat header
- ☐ Reserve kill-switch respected (remote-disabled → UI hidden)
- ☐ Gavel Confirmed check-in flow completes; date marked done
- ☐ Rate-the-date prompt appears post-`dateDone`
- ☐ No-show review path works
- ☐ Cold/expired match cannot be messaged (server-enforced freshness)

---

## 5 · Money (IAP, paywall, Gavels)

- ☐ StoreKit products load (StoreKit config file in scheme for local test)
- ☐ Buy Pass → unlimited bids unlocked; free-limit gate lifts
- ☐ Buy Gavels consumable → balance credits after transaction
- ☐ Restore Purchases returns Pass entitlement
- ☐ Web-purchased Gavels sync into client
- ☐ Purchase interrupted/cancelled → no phantom credit, no crash
- ☐ Paywall triggers: bid-limit, gild-without-funds, boost — each correct
- ☐ No real-money "payment to another user" anywhere (compliance)
- ☐ "Never wire money / send a deposit" disclosure visible at bid point

---

## 6 · Trust & safety

- ☐ ID verification flow completes; Verified badge appears
- ☐ Unverified state cannot access verified-gated features (if any)
- ☐ Block user → they disappear from floor/inbox; server-enforced
- ☐ Blocked Users screen lists them; unblock restores
- ☐ Report user → server records report; confirmation shown
- ☐ Rate limits: rapid-fire bids throttled server-side with clear error
- ☐ Rate limits: rapid-fire messages throttled
- ☐ DOB gate re-checked on profile writes + floor reads
- ☐ Admin panel: reports list, suspend (reversible), audit log, stats card
- ☐ Admin session auth required; no hardcoded credential path
- ☐ Suspended user blocked from actions; unsuspend restores

---

## 7 · Push notifications & deep links

- ☐ Permission prompt appears; grant registers APNs token to server
- ☐ Deny → app still functions; no repeated nagging
- ☐ Re-register on relaunch (token refresh handled)
- ☐ Foreground banner: shows, does **not** auto-navigate
- ☐ **Tap `bidReceived`** → woman lands on Bids (tag 0) / man on My Bids (tag 4)
- ☐ **Tap `whisperNodded`** → man's My Bids (tag 4)
- ☐ **Tap `bidAccepted`** → Matches tab (tag 2)
- ☐ **Tap `messageReceived`** → Matches tab **and pushes that match's chat**
- ☐ **Tap `matchDateDone`** → Matches tab (rate prompt)
- ☐ `verified` / `other` events → no navigation, no crash
- ☐ Deep link consumed once (`deepLinkEvent` reset; no re-fire on redraw)
- ☐ Cold-launch from notification tap routes correctly

---

## 8 · Backend / remote sync

- ☐ Signed-in floor sourced from Profile/Matching Workers
- ☐ Profile edits sync to server (name, bio, location, prompts, interests)
- ☐ Photo upload → R2 → CDN URL renders on floor + detail + match
- ☐ AsyncImage `.empty` → **shimmer** shows during load
- ☐ AsyncImage `.failure` → graceful monogram fallback (no broken image)
- ☐ Launch `.task` seeds matches + inbox/outgoing (badges correct on open)
- ☐ Foreground (scenePhase active) refreshes matches + inbox/outgoing
- ☐ Network failure on any fetch → cached/sim fallback, no white screen
- ☐ Push arrival auto-refreshes relevant list (slice 7)

---

## 9 · Demo Mode

- ☐ Entire app usable with zero backend / not signed in
- ☐ Summon a bidder / Summon the Trillionaire seeds a bid
- ☐ Sim bids/matches/chat all function on-device
- ☐ No remote-only UI leaks (e.g. real-floor chip stays hidden)
- ☐ Switching Demo → signed-in doesn't duplicate or corrupt state

---

## 10 · Accessibility

- ☐ VoiceOver: every card/button has a meaningful label
- ☐ VoiceOver: locked avatar reads "Hidden photo, unlocks when you accept"
- ☐ VoiceOver: bid row reads name/hidden + amount + gilded + verified + credit
- ☐ VoiceOver: toast announced via `.announcement`
- ☐ **Reduce Motion ON**: shimmer suppressed, pulse suppressed, rise-in
      disabled, ScaleButtonStyle uses no animation — all still functional
- ☐ Dynamic Type at xxxLarge: BidRow, FloorCard, chat legible (no truncation
      of critical info)
- ☐ Dark mode: every screen legible; glass surfaces readable on dark bg
- ☐ Light mode (if supported) parity check
- ☐ Color contrast on gold/rose text meets legibility over backgrounds
- ☐ Tab bar legible over dark gallery background (custom appearance)

---

## 11 · Performance & edge cases

- ☐ Long floor scroll: 60fps, no LazyVStack hitching, memory stable
- ☐ Rapid tab switching → no state loss, no flicker
- ☐ Rapid accept/decline → no double-submit, no `inFlight` flicker
- ☐ Backgrounding mid-bid → returns cleanly, no lost input
- ☐ Airplane mode mid-flow → graceful error, retry works on reconnect
- ☐ Very long bio / note / message → wraps, no layout break
- ☐ Empty states everywhere (no bids, no matches, no floor) render
- ☐ Force-unwrap audit: no `!` crash on empty sim data (bidders fallback)
- ☐ Timezone edge: expiry countdowns correct across DST / TZ change
- ☐ Rotation (if allowed) or locked-portrait behaves as intended
- ☐ Memory: leave app open 10 min on Matches with timers — no runaway

---

## 12 · Distribution / App Store readiness

- ☐ App icon present at all required sizes; no alpha channel
- ☐ Launch screen renders correctly
- ☐ All `Info.plist` usage strings present + honest (camera, photos, etc.)
- ☐ Privacy Nutrition Label matches actual data collection
- ☐ ToS + Privacy Policy links open hosted pages (not placeholder)
- ☐ Age rating set (17+ dating)
- ☐ No debug/test UI reachable in Release build
- ☐ No `print()` / debug logging leaking sensitive data in Release
- ☐ Screenshots current with latest UI
- ☐ App Store description matches in-app terminology (bids/lots/Gavels)
- ☐ TestFlight external build passes review notes
- ☐ Admin credential rotated in Cloudflare Worker secrets ⚠️
- ☐ Backend Workers deployed to production (not local/dev URLs)
- ☐ Crash-free session on TestFlight before public submit

---

### Sign-off

| Pass | Role | Mode | Device | iOS | Date | Tester |
|------|------|------|--------|-----|------|--------|
|  1   | Man  | Demo |        |     |      |        |
|  2   | Man  | Live |        |     |      |        |
|  3   | Woman| Demo |        |     |      |        |
|  4   | Woman| Live |        |     |      |        |

**Ship gate:** all four passes green + section 12 complete + zero open ❌.
