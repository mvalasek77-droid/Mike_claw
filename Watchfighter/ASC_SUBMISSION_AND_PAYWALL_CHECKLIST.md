# Watch Fighter — App Store Connect Submission + Paywall Checklist

Grounded in the actual state of this repo as of `b43b2d3`. Items already done
are marked ✅; everything else is ordered by what actually blocks a release.

---

## Part 1 — App Store Connect submission

### Already in place
- ✅ App name/subtitle/keywords/description drafted — `STORE_LISTING.md`
- ✅ `PrivacyInfo.xcprivacy` manifest present (`Resources/PrivacyInfo.xcprivacy`)
- ✅ App icon set (`AppIcon.appiconset`, "Watch Fighter")
- ✅ Bundle ID configured: `com.valasek.watchfighter`
- ✅ CI green: builds, 52 unit tests, copy audit all pass on every push

### 1. Apple Developer Program account
- [ ] Enroll ($99/yr) if not already — required to submit anything.
- [ ] Confirm the team ID used in `project.yml` (`UDM4W27W9V`) matches your
      enrolled account/team.

### 2. App Store Connect app record
- [ ] Create the app record (My Apps → +) with bundle ID `com.valasek.watchfighter`.
- [ ] Category: Games → Action (or Sports if you want the arcade angle).
- [ ] SKU (internal, not user-facing — e.g. `watchfighter001`).
- [ ] Set `CFBundleShortVersionString` = `1.0`, build number = `1` (bump build
      number on every subsequent TestFlight/App Store upload).

### 3. Signing & archive build
- [ ] In Xcode, sign in with your Apple ID under Signing & Capabilities.
- [ ] Switch signing to your real distribution certificate (currently the
      project is set up for simulator/dev builds only — no archive workflow
      exists in CI yet).
- [ ] Archive (Product → Archive) targeting a real watchOS device, not the
      simulator app the CI artifact currently produces.
- [ ] Upload the archive via Xcode Organizer or `xcrun altool`/`notarytool`
      equivalent (Transporter app also works).
- [ ] **Play a full tournament run on a real Apple Watch** — win path, lose
      path (Pit → Hell → Abaddon), Dracula unlock, admin long-press gesture,
      crash-report sheet. Nothing below matters until this is clean on-device.

### 4. Store listing metadata
- [ ] Paste `STORE_LISTING.md` content into App Store Connect (name, subtitle,
      promo text, description, keywords).
- [ ] Support URL — currently a placeholder in `STORE_LISTING.md`; needs a
      real page or repo link before submission.
- [ ] Marketing URL (optional).
- [ ] Copyright line (e.g. "© 2026 [Your name/entity]").

### 5. Screenshots
- [ ] Capture on **every required Apple Watch size** (currently only simulator
      screenshots exist from the CI demo job — good enough for a first pass,
      but check Apple's current required-size list in ASC before finalizing).
- [ ] Cover the 5 shots listed in `STORE_LISTING.md`: mid-combo, VS
      character-select, a story cutscene, the boss/Million Room, main menu.
- [ ] Consider one Hell-fight (Abaddon) and one Dracula/vampire-transform
      screenshot too — they're new hooks worth selling.

### 6. Age rating
- [ ] File the age-rating questionnaire — this app has stylized blood, severed
      limbs/heads, and a horror character (Dracula/vampire transformation).
      Answer "Realistic Violence" / "Blood and Gore" honestly in the
      questionnaire, not just "Cartoon Violence" — the gore was made more
      graphic per your last request, so under-declaring risks a review bounce
      or a post-release rating correction.
- [ ] Expect a 12+ or 17+ rating depending on how ASC's questionnaire scores
      "Blood and Gore" + "Horror/Fear Themes" (Dracula). Don't guess — the
      questionnaire outcome is deterministic from your answers.

### 7. Privacy nutrition label
- [ ] Confirm the app truly collects nothing (no analytics/crash SDK — the
      crash monitor writes locally only, per your ask). If so, declare "Data
      Not Collected" in ASC to match `PrivacyInfo.xcprivacy`.
- [ ] If you add analytics or a remote crash-reporting backend later, this
      section and the manifest both need updating together — they must match
      or review will flag the mismatch.

### 8. Export compliance
- [ ] Answer the encryption question in ASC. If the app only uses standard
      HTTPS/OS-provided crypto (no custom encryption), you qualify for the
      standard exemption — mark accordingly (a doc reference for this already
      exists per an earlier commit; confirm it's still accurate).

### 9. App Review notes
- [ ] No login/demo account needed (no backend) — state that explicitly in
      the review notes so the reviewer doesn't wait on credentials.
- [ ] Mention the hidden admin gesture (long-press title) is a **debug-only**
      entry point, not user-facing content, so the reviewer doesn't flag TEST
      mode as unfinished/placeholder UI if they stumble onto it.

### 10. Submit
- [ ] TestFlight internal build first — sanity-check on your own watch via
      TestFlight before hitting "Submit for Review."
- [ ] Submit. Typical review turnaround is 24–48h; a fighting game with gore
      may take a first-pass manual review — budget a few extra days for v1.0.

---

## Part 2 — Paywall

**Nothing here exists yet** — right now Watch Fighter is entirely free with no
StoreKit code, no IAP products, and no paywall UI. This section is a build
checklist, not a "verify it's done" list.

### 0. Decide the model first (blocks everything else)
Pick one before writing any code — this determines both the ASC product setup
and the StoreKit implementation:

| Model | Fits this game because... | Complexity |
|---|---|---|
| **One-time unlock** ("Full Roster" / "Unlock Watch Fighter") | Simple arcade game, no live-service content — matches player expectation for a $2–5 fighter. Recommended default. | Low |
| **Non-consumable per-character** | Sell Dracula/secret characters individually — but they're currently *earned* (win the tournament), which conflicts with also selling them. Would need a design change (buy OR earn). | Medium |
| **Consumable** (extra continues, meter refills) | Feels bad in a skill-based fighter; typically hurts reviews for this genre. Not recommended. | Low |
| **Subscription** | No ongoing live content to justify recurring billing for a fixed-roster arcade game. Not recommended unless you're planning regular content drops (new floors/characters). | High |

- [ ] Decide, and decide what's free vs. paid (e.g. free: floors 1–5 + Learn
      mode; paid: floors 6–15 + Dracula + Hell). A demo/trial slice is
      standard for arcade-style paid unlocks and helps ASC review + conversion.

### 1. App Store Connect: create the IAP product(s)
- [ ] App Store Connect → Features → In-App Purchases → create product(s)
      matching the model chosen above (Non-Consumable is the likely type).
- [ ] Product ID convention: `com.valasek.watchfighter.fullunlock` (or similar
      — must be unique and can't be reused later even if deleted).
- [ ] Set price tier, display name, description.
- [ ] Upload the required IAP review screenshot (ASC requires one showing the
      purchase in context).
- [ ] Fill in the IAP's own review notes.

### 2. StoreKit 2 implementation (in the Watchfighter target)
- [ ] Add StoreKit capability in `project.yml` / entitlements.
- [ ] `Product.products(for:)` to fetch the product(s) at launch or on paywall
      presentation.
- [ ] `product.purchase()` → handle `.success(.verified)`, `.success(.unverified)`,
      `.userCancelled`, `.pending` (Ask to Buy / parental approval) states
      distinctly — don't silently swallow `.pending`.
- [ ] Listen to `Transaction.updates` for out-of-band purchase completion
      (required — purchases can complete outside your active session, e.g.
      Ask to Buy approval).
- [ ] Call `transaction.finish()` only after unlocking content, never before.
- [ ] Persist entitlement state locally (e.g. in the same store as
      `bestScore`), re-derived from `Transaction.currentEntitlements` on
      launch — don't rely solely on a local flag that could desync.
- [ ] Gate the specific content per the model chosen in step 0 (e.g. floor
      6+ selection, Dracula in the roster, Hell fight) behind the entitlement
      check.

### 3. Paywall UI/UX (Apple App Review Guideline 3.1 compliance)
- [ ] Show price and product name clearly before purchase — no surprise
      charges.
- [ ] **Restore Purchases** button, visible and working — required by Apple,
      not optional. Test on a fresh install with the same Apple ID.
- [ ] Never block the app from launching or force a purchase before any free
      content is playable — Apple rejects paywalls that gate the entire app
      with no preview.
- [ ] Don't use dark patterns (pre-checked boxes, deceptive "continue"
      buttons that trigger purchase) — automatic rejection risk.
- [ ] watchOS-specific: keep the paywall legible at watch screen sizes — a
      simple "Unlock Watch Fighter — $X.XX" card with Buy/Restore is safer
      than a dense feature-comparison table.
- [ ] If subscription (not recommended above): must show terms/EULA link,
      auto-renewal disclosure, and cancellation instructions per guideline
      3.1.2 — significantly more review scrutiny than a one-time purchase.

### 4. Testing
- [ ] Create a StoreKit Configuration file (`.storekit`) in Xcode for local
      testing without hitting the real App Store sandbox — fastest iteration
      loop.
- [ ] Test against the real Sandbox with a Sandbox Tester Apple ID (ASC →
      Users and Access → Sandbox Testers) before submission — local
      `.storekit` config can hide real-environment edge cases.
- [ ] Test: purchase → kill app → relaunch → entitlement persists.
- [ ] Test: fresh install + Restore Purchases → entitlement returns.
- [ ] Test: purchase cancelled mid-flow → app state doesn't get stuck.
- [ ] Test: Ask to Buy (`.pending`) → approve later → `Transaction.updates`
      picks it up without requiring the user to reopen the paywall.

### 5. Submit
- [ ] IAP products get reviewed **alongside** the first app version that
      references them — submit the app build and the IAP product together,
      not the IAP alone first.
- [ ] Mention the paywall/unlock model explicitly in the app's review notes
      so the reviewer knows what's free vs. paid and can test both paths.

---

## Suggested order of operations
1. Finish Part 1 (submission mechanics) up through the on-device play-test —
   that's required regardless of monetization.
2. Decide the paywall model (Part 2, step 0) — this is a product decision,
   not an engineering one, and everything else depends on it.
3. Build StoreKit + paywall UI, test in sandbox.
4. Submit app + IAP together.
