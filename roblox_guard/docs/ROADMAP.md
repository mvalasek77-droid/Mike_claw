# RobloxGuard roadmap

## Shipped (v0.1 — current branch)

- Risk-signal engine on public Roblox data (off-platform handles with
  leetspeak folding, grooming phrases, account-pattern signals, watchlisted
  experiences, quiet hours) with a test-enforced no-labeling wording policy
- Evidence vault: auto profile screenshots + data snapshots, parent uploads,
  SHA-256 chain of custody; erased in full on unlink
- Incident reports readable by a Roblox-novice parent, officer, or NCMEC
  analyst (primer + per-report glossary)
- Versioned threat feed carrying detection rules AND parent-facing content;
  daily Claude-analyzed threat-intelligence proposals with operator review
- Parent feedback loop (mute noise / heighten vigilance), API auth,
  retry/backoff, poll-health surfacing
- StoreKit 2 subscriptions (Single Child / Family, see README "Pricing")
- Durable bug log (rotating file + bug_reports table) and an in-app
  "Report a Bug" flow with mailto: fallback (README "Bug log & reporting a bug")
- Push notifications (APNs, token-based auth) for watch/elevated alerts —
  `push.py` + `PushManager.swift` (see README "Push notifications")
- Original app icon (`Design/generate_app_icon.py`) — not derived from
  Roblox's branding, since this is an unaffiliated third-party app
- Xcode Cloud CI prep (`ci_scripts/ci_post_clone.sh`) and a draft privacy
  policy (`docs/PRIVACY_POLICY.md`) ready to publish
- 150 backend tests incl. full-journey E2E, hostile-input, and perf budgets

## Next (v0.2 — ship blockers for the App Store)

- [ ] Parent accounts + multi-device sync (Sign in with Apple; token per
      account replaces the shared RG_API_TOKEN)
- [ ] Postgres + migrations (Alembic) behind the same Database interface
- [x] Subscription via StoreKit 2 (guideline 3.1.1) — `PurchaseManager.swift`
      + `PaywallView.swift` ship two tiers (Single Child $3.99/mo·$34/yr,
      Family $8.99/mo·$69/yr, see README "Pricing"). Still needed before
      release: create the four product IDs in App Store Connect, and move
      off client-side `Transaction.currentEntitlements` to server-verified
      App Store Server Notifications if the backend ever needs to trust
      subscription state.
- [x] Push notifications (APNs) for watch/elevated alerts — code is done and
      unit-tested against a mocked APNs; still needed before release: a real
      APNs key from App Store Connect (README "Push notifications") and a
      live-device test, since Simulator push delivery can't be fully
      verified without one.
- [ ] Privacy policy, App Privacy labels, COPPA counsel review — draft
      written (`docs/PRIVACY_POLICY.md`), needs counsel review and
      publishing at a real URL (`PaywallView.privacyPolicyURL` is a
      placeholder pointing at it)
- [ ] XCUITest suite + snapshot tests once the Xcode project is generated
      (including the paywall / entitlement-gating flow added for pricing,
      and the notification permission flow)

## v0.3 — iOS 26 Liquid Glass theme

Current build ships a system-materials glass treatment (Theme.swift) that
respects Reduce Transparency and both color schemes. When targeting iOS 26:

- [ ] Adopt native Liquid Glass surfaces for cards, tab bar, and sheets
      (fluid glassmorphism with refraction/depth instead of static blur)
- [ ] Depth effects: parallax layering on the dashboard severity cards
- [ ] Adaptive haptics: replace the fixed UIKit generators in Theme.swift
      with the richer per-severity haptic curves (CHHapticEngine patterns
      that escalate with severity)
- [ ] Motion audit: every animation gated on Reduce Motion

## v0.4 — depth of coverage

- [ ] Roblox official parent-account API integration if/when Roblox opens one
- [ ] Group-membership signals; friend-network graph view for parents
- [ ] Multi-child family dashboard with per-child quiet-hours schedules
- [ ] Android parent app (same backend)
- [ ] Operator console for threat-feed curation and intel-proposal review

## Explicit non-goals

- Reading private chats (impossible without violating Roblox ToS; any
  competitor claiming it is scraping credentials)
- Device-side surveillance of the child (keylogging, screen capture, VPN
  interception) — rejected by Apple and wrong for trust
- Public accusation features of any kind
