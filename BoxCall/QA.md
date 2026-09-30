# BoxCall QA Test Plan

Ship-ready test matrix. Run through this before every App Store submission. Automated unit tests cover the pricing / refill math; this document covers the flows a human has to actually watch happen.

## 0 · Preflight

- [ ] `xcodegen generate` from `BoxCall/` produces a clean `BoxCall.xcodeproj` with all six targets (`BoxCall`, `BoxCallWidget`, `BoxCallWatch`, `BoxCallWatchComplication`, `BoxCallTests`, and the app itself).
- [ ] `xcodebuild -project BoxCall.xcodeproj -scheme BoxCall -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build` completes with **zero warnings**.
- [ ] `xcodebuild test -scheme BoxCall -destination 'platform=iOS Simulator,name=iPhone 15 Pro'` — all XCTests green.
- [ ] Instruments' Leaks + Allocations for 60 seconds of active Slate scrolling — no leaks, no runaway allocations.

## 1 · First-run onboarding

- [ ] Fresh install → **Age gate** appears. Reject invalid year, reject year < 13. Accept a valid one.
- [ ] Tour has 9 pages: Welcome → Pick a movie → Bigger or smaller → Buy → Watch it move → Results on Sunday → How each week works → Fair-play rules → The goal. "Skip" jumps to the app; "Read the full guide" opens LearnView.
- [ ] Pages 2, 4 and 5 show real movies from the live Slate (soonest tradable first) with the real predicted opening and a real contract price. The Sunday example is the real Resident Evil result ($60.1M, Sept 18–20).
- [ ] The goal page's rivals show the SIM tag.
- [ ] Push permission requested on first launch AFTER onboarding, not before.
- [ ] Second launch skips both — goes straight to `RootView`.

## 2 · Trading loop

- [ ] Now Showing renders the verified built-in slate within 200ms cold-launch (or the enriched TMDB catalog if a key is set). Every film shown must be a real announced release and must not be settled — if one appears, `VerifiedMovieProvider` / `loadVerifiedCatalog` has regressed.
- [ ] Opening Night hero shows the film with the soonest release date, and its countdown ticks once per second.
- [ ] Marquee ticker scrolls continuously without a visible seam at the wrap point.
- [ ] Pull-to-refresh on Slate triggers a spinner in the nav bar; "Updated Xs ago" text updates on completion.
- [ ] Tap a movie → detail view. Consensus card has a pulsing green dot. Chain scrolls, each row's sparkline animates every 3s.
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
- [ ] No text anywhere claims news about a real film. The Trading Desk's "What moved it" list only shows your trades, Hot Takes, reviews and feed signals.
- [ ] Every other trader (leaderboard, feed, spotlight reviews, movie reviews) shows a SIM tag.

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

- [ ] Grant push permission. Trigger every notification path (settlement win/loss, badge, tier promotion, opening reminder, voided market, out-of-coins) and verify each has the correct emoji + copy.
- [ ] Buy a contract on a movie opening in the next 24h. Live Activity appears on Lock Screen; Dynamic Island (iPhone 14 Pro+) shows compact leading emoji + trailing P&L. Update ticks live. Settlement changes it to "Opened at $X.XM".
- [ ] Home screen: add the Next Opening widget in small + medium. Add Top Position widget. Verify both refresh within one minute of a chain change in the app.
- [ ] Paired Apple Watch: complication (circular + rectangular) shows correct data. Watch app opens with the same snapshot; no "waiting for iPhone" state after 5s.

## 8 · Sign in with Apple (sets the trader name; nothing syncs)

- [ ] Guest state fully functional. AuthCard says "Playing as a guest".
- [ ] Sign in with Apple → handle populates from given name if it was "you". AuthCard flips to "Signed in with Apple".
- [ ] Sign out → local credentials cleared, handle unchanged, positions preserved.
- [ ] Revoke the credential in Settings → app auto-signs-out on next launch.

## 9 · Challenge friends

- [ ] Profile → Challenge friends: the share sheet opens with the App Store link. No codes, no coin rewards.

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

- [ ] No network calls besides the data feed (raw.githubusercontent.com), TMDB when a key is set, and YouTube when a key is set. Analytics stay on device.
- [ ] No secret keys shipped in the app binary — TMDB and YouTube keys are optional and read from Info.plist.
- [ ] Privacy Policy + ToS linked from Profile and match `appstore/category_and_rating.txt` App Privacy answers.
- [ ] Delete-account path: Profile › Delete account and data wipes trades, coins, posts, reviews and sign-in, and returns to the age gate.
- [ ] Force-quit and relaunch: coins, open/settled positions and resting limit orders are all still there.
- [ ] Leaderboard ranks by total profit, not balance: buying Mogul (40,000 RC bonus) does not move your rank; a winning settlement does. Sunday's reset leaves total profit unchanged.
- [ ] Spotlight: get into the top 5, write a review, force-quit and relaunch — your review is still on Marquee with your real rank and profit. Outside the top 5, Marquee shows how many RC you need to get in.
- [ ] Settlement waits for real results: with no actual published, an opened movie shows "Awaiting results" instead of settling on a guess.
- [ ] Weekly cycle (set the device clock): on Friday the opening movie shows "Trading locked" and its positions show "Settles Sun"; unreleased movies still trade. Sunday: balance drops to profit only; open trades untouched. Monday: fresh stake lands; a winning opener trade pays back its stake then credits the profit; a losing one owes nothing.

## 13 · Market-making desk (sentiment-driven quotes)

Automated coverage lives in `MarketMakingAgentTests`, `MarketMakingDeskTests`, and `SentimentEngineTests`. This section covers what a human has to watch happen.

- [ ] Open any contract's Trade Sheet → a **Market makers** section shows bid, ask, spread percentage, liquidity grade, and the crowd mood.
- [ ] Tap **See the desk that made this price** → Trading Desk opens with the sentiment gauge, all five agents, and the chatter feed.
- [ ] Leave the desk open for 60 seconds. The gauge needle, the agent quotes, and the chatter list all update without stutter. No flicker on the numeric transitions.
- [ ] Every agent row shows a rationale sentence that matches its numbers — an agent marked *Bidding* has the larger size on the bid.
- [ ] **Trend Rider** and **Fade Desk** visibly disagree on a movie whose crowd score is past ±0.5.
- [ ] **The Anchor** always shows size on both sides, at every sentiment reading.
- [ ] Place a large trade on a movie you are watching. The Momentum metric spikes, and at least one agent widens or steps away.
- [ ] After the shock decays, spreads visibly tighten again and the stepped-away agents come back.
- [ ] Buy 20 contracts of one strike → the crowd chatter feed gains an **Order flow** entry, and the desk's inventory skew shades its next quotes down.
- [ ] Post a Hot Take from the Trade Sheet → a **Chatter** entry appears on that movie's desk within one tick.
- [ ] Submit a 5-star review → a positive **Review** entry appears; a 1-star review produces a negative one.
- [ ] Buy at the ask, then immediately close the position. Proceeds come back at the **bid**, so a round trip loses the spread. This is expected, not a bug.
- [ ] Movie Detail shows the **Market makers** roll-up card with average spread and a headline that matches the state of the chain.
- [ ] Learn → section 7 **The desk** renders fully, with all five agent descriptions.

### Desk edge cases

- [ ] A movie added mid-session (pull to refresh with a TMDB key set) gets a book within one tick; no contract renders a dash for both sides.
- [ ] With no API keys configured, ambient chatter still moves the gauge — the desk never sits perfectly still.
- [ ] VoiceOver on the Trading Desk reads the gauge, the inside market, and each agent row as single coherent elements.
- [ ] Dark mode and accessibility-3 Dynamic Type: the agent rows wrap without clipping and the depth bars stay aligned.

## 14 · App Store gates (final)

- [ ] Ten screenshots per `appstore/screenshots.md`, at 1290×2796 and 1179×2556.
- [ ] `appstore/review_notes.txt` pasted into the App Review notes field.
- [ ] App Privacy questionnaire answered per `appstore/category_and_rating.txt`.
- [ ] Content Rights: no third-party content requiring rights clearance beyond public metadata (TMDB/IMDb) used informationally.
- [ ] Age rating: 12+ (UGC + moderation, no simulated gambling).

If every checkbox above is green, the app is ready to submit.
