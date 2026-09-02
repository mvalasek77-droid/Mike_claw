# BoxCall QA Test Plan

Ship-ready test matrix. Run through this before every App Store submission. Automated unit tests cover the pricing / refill math; this document covers the flows a human has to actually watch happen.

## 0 · Preflight

- [ ] `xcodegen generate` from `BoxCall/` produces a clean `BoxCall.xcodeproj` with all six targets (`BoxCall`, `BoxCallWidget`, `BoxCallWatch`, `BoxCallWatchComplication`, `BoxCallTests`, and the app itself).
- [ ] `xcodebuild -project BoxCall.xcodeproj -scheme BoxCall -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build` completes with **zero warnings**.
- [ ] `xcodebuild test -scheme BoxCall -destination 'platform=iOS Simulator,name=iPhone 15 Pro'` — all XCTests green.
- [ ] Instruments' Leaks + Allocations for 60 seconds of active Slate scrolling — no leaks, no runaway allocations.

## 1 · First-run onboarding

- [ ] Fresh install → **Age gate** appears. Reject invalid year, reject year < 13. Accept a valid one.
- [ ] Onboarding pages: Welcome → Calls (payoff chart animates in) → Puts (mirror chart) → Status. "Skip" jumps to app. "Read the full guide" opens LearnView, "Done" returns to onboarding.
- [ ] Push permission requested on first launch AFTER onboarding, not before.
- [ ] Second launch skips both — goes straight to `RootView`.

## 2 · Trading loop

- [ ] Now Showing renders the built-in slate within 200ms cold-launch (or the live TMDB catalog if a key is set). Every film shown must have a release date in the future — if a title that has already opened appears, the `isSettled` filter in `MockMovieProvider` / `loadMockCatalog` has regressed.
- [ ] Opening Night hero shows the film with the soonest release date, and its countdown ticks once per second.
- [ ] Marquee ticker scrolls continuously without a visible seam at the wrap point.
- [ ] Pull-to-refresh on Slate triggers a spinner in the nav bar; "Updated Xs ago" text updates on completion.
- [ ] Tap a movie → detail view. Consensus card has a pulsing green dot. News ticker shows 0–3 recent events. Chain scrolls, each row's sparkline animates every 3s.
- [ ] Tap any chain row → **First-time tutorial** fires for Call OR Put (first time only per side). Skip once → check second row of same side does not re-trigger.
- [ ] TradeSheet ScenarioPrimer reads: "You WIN if…" / "You LOSE if…" with the correct strike numbers. Live mark chart shows S/R lines. Buy button caption reflects the current mark, not the sheet-opening mark.
- [ ] Change quantity → totals update in real time. Toggle Limit → slider appears, Buy label switches to "Place buy-limit @ X".
- [ ] Buy → dismiss sheet → Portfolio shows the new position. **Haptic**: medium tap on buy.

## 3 · Portfolio + settlement

- [ ] Portfolio balance card shows correct number + "Next Monday reset · +N RC in Xd Yh" countdown.
- [ ] Working limit orders appear if any are pending. Cancel refunds the reservation to the balance.
- [ ] "Simulate opening weekends" button settles all near-term movies. Verify: win → success haptic (or celebration for +100 RC), loss → error haptic, streak updates, badges fire toasts, tier promotes if XP crossed threshold, push notification lands.
- [ ] Zero-balance path: force lose all coins. Trading pauses (buys reject with friendly error). "You're out" push fires exactly once. Low-balance banner shows countdown to Monday.

## 4 · Live market

- [ ] Detail view chart mean-reverts inside its S/R band across 30s. Green support and red resistance lines visible with labels.
- [ ] Buy 50 contracts of one strike → mark jumps up on the next tick. Sparkline reflects it.
- [ ] Wait ~30s for a news event to fire (5% per tick, expected ~1 in 20). Verify: matching push arrives if you hold a position on that movie, sparkline shifts direction on all strikes of that movie.

## 5 · Social + moderation

- [ ] Share-as-post toggle on TradeSheet creates a Feed post. Post appears at top of Hot Takes.
- [ ] Like toggles. Comment sheet adds. Follow flips button state. All animate under `Theme.Motion.snap`.
- [ ] Copy call from any live post: TradeSheet opens with the same strike / side / qty pre-filled. Post with an outcome disables the button.
- [ ] Share sheet: renders the shareable card, iMessage receives image + caption.
- [ ] Featured Critics: hero card for #1, up to four supporting cards. Tap opens detail sheet.
- [ ] Report on any non-self post → sheet appears. Submit with "Also block" → post disappears from Feed. Blocked handle also drops from Featured Critics + reviews. Manage in Profile → Blocked users → Unblock.

## 6 · Subscription

- [ ] Profile → Upgrade opens PaywallView. Three tiers with correct prices from the StoreKit config file.
- [ ] Simulate purchase in StoreKit debug menu (or the demo fallback in the app if StoreKit unavailable). Toast fires: "Welcome to Backstage — +5000 RC". Balance updates instantly. Membership card on Profile flips to the paid tier's color.
- [ ] Cancel membership → free-tier weekly rate takes effect on next allowance grant.
- [ ] Restore purchases works after a full uninstall/reinstall.

## 7 · Notifications + Live Activity + widgets

- [ ] Grant push permission. Trigger every notification path (settlement win/loss, follower, badge, tier promotion, opening reminder, market event, out-of-coins) and verify each has the correct emoji + copy.
- [ ] Buy a contract on a movie opening in the next 24h. Live Activity appears on Lock Screen; Dynamic Island (iPhone 14 Pro+) shows compact leading emoji + trailing P&L. Update ticks live. Settlement changes it to "Opened at $X.XM".
- [ ] Home screen: add the Next Opening widget in small + medium. Add Top Position widget. Verify both refresh within one minute of a chain change in the app.
- [ ] Paired Apple Watch: complication (circular + rectangular) shows correct data. Watch app opens with the same snapshot; no "waiting for iPhone" state after 5s.

## 8 · Auth + cloud sync

- [ ] Guest state fully functional. AuthCard says "Playing as a guest".
- [ ] Sign in with Apple → handle populates from given name if it was "you". AuthCard flips to "Signed in with Apple".
- [ ] Sign out → local credentials cleared, handle unchanged, positions preserved.
- [ ] Revoke the credential in Settings → app auto-signs-out on next launch.

## 9 · Referrals + custom markets

- [ ] Profile → Invite friends: my code renders in monospace. Copy + Share both work. Redeem another code → +500 RC to me, doubles-redeem rejected with "already redeemed", self-code rejected.
- [ ] Profile → Prop markets: as a free user, "Propose" opens the paywall. Upgrade to Mogul in StoreKit sim → the Propose row switches to opening the ProposeMarketSheet. Submit with < 20 chars of details → validation error; submit valid → market appears in pendingReview with the LIVE/REVIEW badge.

## 10 · Edge cases

- [ ] Airplane mode: pull-to-refresh on Slate shows the "Refresh failed" footer but keeps the cached slate. No crash.
- [ ] Kill the app mid-Live-Activity → the activity persists on the Lock Screen and stales out on its own.
- [ ] Force a movie's release date into the past → simulateSettlements picks it up; the movie is pruned from the Slate on the next refresh IF you have no open position on it, ELSE stays.
- [ ] Change the system time forward across a Monday boundary → next launch grants exactly ONE allowance (not multiple stacked).
- [ ] Localization: switch simulator to Spanish → tabs, actions, and portfolio strings are translated. Fallback to English for anything not in Localizable.strings.
- [ ] Accessibility: turn on VoiceOver. Every chart reads a summary. All buttons have labels. Rotor navigates the Feed in reading order.
- [ ] Dynamic Type: bump to accessibility-1. All screens remain usable — no truncation of critical numbers, chart axis text stays readable via `.clampDynamicType`.
- [ ] Dark mode is the default; there is no Light-mode surface treatment in v1. Confirm the app is legible under Increase Contrast.

## 11 · Performance

- [ ] Launch time (cold, iPhone 15 Pro): under 800ms to first paint.
- [ ] 60fps sustained scrolling on Slate + Feed at accessibility-1 Dynamic Type.
- [ ] Memory footprint after 10 min of use: under 120 MB.
- [ ] Battery drain over a 30-minute active session in Instruments: within 5% of Xcode's baseline for a comparable social app.
- [ ] Backgrounding the app → returning after 10 minutes: MarketService resumes ticking; the widget snapshot is at most one tick old.

## 12 · Security / privacy

- [ ] No PII in analytics event NDJSON on the backend. Only `signed_in` bool + membership + event name + props.
- [ ] No secret keys shipped in the app binary — YouTube key is optional and read from Info.plist; X API key never leaves the backend.
- [ ] Privacy Policy + ToS linked from Profile and match `appstore/category_and_rating.txt` App Privacy answers.
- [ ] Delete-account path: sign out clears local credentials; server deletion via email per policy.

## 13 · App Store gates (final)

- [ ] Ten screenshots per `appstore/screenshots.md`, at 1290×2796 and 1179×2556.
- [ ] `appstore/review_notes.txt` pasted into the App Review notes field.
- [ ] App Privacy questionnaire answered per `appstore/category_and_rating.txt`.
- [ ] Content Rights: no third-party content requiring rights clearance beyond public metadata (TMDB/IMDb) used informationally.
- [ ] Age rating: 12+ (UGC + moderation, no simulated gambling).

If every checkbox above is green, the app is ready to submit.
