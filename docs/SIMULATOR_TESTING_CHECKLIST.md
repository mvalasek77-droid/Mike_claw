# Prompt Coach — Simulator / iPhone Testing Checklist

Everything below needs Xcode and either the Simulator or a real device —
none of it can run in this Linux container. This is the list that turns
`docs/PROMPT_COACH_TEST_REPORT.md`'s 550 static contract-test passes into an
actually-verified app. Work through it in order; each section builds on the
last.

Two targets, two schemes: **`PromptCoach`** (paid, all 5 models) and
**`PromptCoachLite`** (free, 2 models, no Sharpen/token-report/adaptive
controls). Most sections below run on both — the checklist says which.

---

## 0. Setup

- [ ] `cd ios/PromptCoach && xcodegen generate` — regenerates `.xcodeproj`
      from `project.yml`. Re-run this any time `project.yml` changes; the
      `.xcodeproj` itself isn't committed.
- [ ] Open `PromptCoach.xcodeproj` in Xcode 16+.
- [ ] Set a real `DEVELOPMENT_TEAM` (currently `""` in `project.yml`) so both
      targets can sign and run on a device, not just the Simulator.
- [ ] Confirm both schemes appear in the scheme picker: `PromptCoach`,
      `PromptCoachLite`.

## 1. Clean build

- [ ] `PromptCoach` scheme builds with **zero warnings** on iPhone 16
      Simulator (iOS 17 target, but build against the latest available SDK).
- [ ] `PromptCoachLite` scheme builds clean too — this is the first real
      signal on whether the `#if LITE` gating even compiles. It's the
      single biggest unknown in the whole app right now: every Lite code
      path in `AppTier.swift`, `ModelPack.swift`, `CoachEngine.swift`,
      `LearningStore.swift`, `AppState.swift`, `ResultView.swift`, and
      `SettingsView.swift` has only ever been read, never compiled.
- [ ] Both the iOS 26 `glassEffect` path and the `.ultraThinMaterial`
      fallback compile — check with `#available`/`#if compiler(>=6.2)`
      guards intact (build against an iOS <26 SDK too, if available, to
      confirm the fallback path actually compiles).

## 2. XCTest suite — `PromptCoach` scheme only

`PromptCoachLite` has no test target (documented gap — see the roadmap).

- [ ] `xcodebuild test -scheme PromptCoach -destination 'platform=iOS Simulator,name=iPhone 16'`
- [ ] **All 58 XCTests green.** If any fail, that's a real bug the static
      contract tests couldn't see — fix before anything else on this list.
- [ ] Note which of the 58 exercise Lite-adjacent logic (`AppTier`,
      `availableModels`) — none currently do, since the test target only
      compiles under the paid tier. That's expected, not a gap to fix here.

## 3. Core flow — `PromptCoach` (paid)

- [ ] **First launch, no history.** Empty states on Ramble and History read
      sensibly, not like a bug.
- [ ] **Ramble → Coach It → Result.** Type a rambling prompt, get a coached
      one. Report card shows a score below 100 on the raw ramble.
- [ ] **Model override.** Tap each of the 5 chips in Result — background
      tint and content re-render for that model (`Glass.tint(for:)`).
      Confirm the "recommended" label follows the actual recommendation,
      not whichever chip is selected.
- [ ] **Sharpen.** Tap "Sharpen it further" — prompt restructures into
      tagged `<task>`/`<success_criteria>` sections. Button becomes
      "Sharpened" and doesn't re-fire.
- [ ] **Token/cost card.** Appears under the report card. Numbers are
      labeled "approx." / "not an exact count." Coach a very short ramble
      (e.g. "fix bug") and confirm it honestly shows the coached prompt as
      *longer* than the ramble, rather than hiding that case.
- [ ] **Copy / Share.** Both trigger `app.noteAccepted` — no visible
      effect to check directly, but confirm neither crashes and the share
      sheet contains the coached prompt text.
- [ ] **History.** Coaching a session saves it; re-coaching against a
      different model updates the same entry (no duplicate); search and
      delete both work; "Clear all" empties it.
- [ ] **Settings → Model reference.** All 5 models listed with full detail
      (rewrite rules, do/don't, API facts). Tapping each opens
      `ModelDetailView` without truncation.
- [ ] **Settings → Technique library.** All techniques browsable, search
      filters correctly, retired-patterns section renders.
- [ ] **Settings → Adapts to you (adaptive controls).** Drive a signal to
      its threshold — override the model chip away from the recommendation
      3× for the same task type, or tap Sharpen 3× on 3 different sessions
      of the same task — and confirm the adjustment shows up in plain
      language. Then **Reset** and confirm the on/off switch and any muted
      techniques survive (only inferred adjustments clear).
- [ ] **Technique muting.** In a technique's Learn sheet, mute it; confirm
      it stops appearing in future coached prompts and shows a MUTED badge
      in the technique library list.
- [ ] **Terms / Privacy.** Both render fully, no clipped text, correct
      "one-time purchase, no IAP" language.

## 4. Core flow — `PromptCoachLite` (free)

Switch scheme to `PromptCoachLite`, delete the app from Simulator first if
it was previously installed as `PromptCoach` (different bundle ID, so this
is about a clean slate, not a real conflict).

- [ ] **Model picker shows exactly 2 chips** everywhere one appears
      (Result screen) — Haiku 4.5, Sonnet 5. No Opus 5 / Opus 4.8 / Fable 5
      chip anywhere in the coaching flow.
- [ ] **No Sharpen button** on the Result screen at all (not disabled —
      absent).
- [ ] **No token/cost card** on the Result screen.
- [ ] **Settings has no "Adapts to you" row.** The whole adaptive-controls
      section should be structurally absent, not just empty.
- [ ] **Settings shows the "Unlock all 5 models" upsell card** near the top,
      above the Learn section. Tapping it should attempt to open the App
      Store — expect it to fail or 404 right now since
      `AppTier.paidAppStoreURL` is still the placeholder
      `apps.apple.com/app/id0000000000`; confirm the tap at least doesn't
      crash the app.
- [ ] **Model reference: 2 unlocked + 3 locked.** Haiku 4.5 and Sonnet 5
      open full detail as normal. Opus 5, Opus 4.8, and Fable 5 show as
      dimmed rows with a lock icon and "In the full app" — tapping one
      opens the App Store link (same placeholder-URL caveat as above).
- [ ] **History caps at 3.** Coach a 4th distinct ramble and confirm the
      oldest entry drops off rather than the list growing unbounded.
- [ ] **Technique library is fully browsable**, same as paid — this one is
      intentionally *not* stripped.
- [ ] **Terms / Privacy read as the free-app versions** — "entirely free,"
      no claim that a purchase happened, mentions the link to the separate
      paid app.
- [ ] **App name reads "Prompt Coach Lite"** on the home screen and in
      Settings → About.

## 5. Regression — `PromptCoach` unaffected by the Lite refactor

The two targets sharing one source tree is the main risk this change
introduced. Re-run the relevant parts of Section 3 after confirming Section
4, specifically:

- [ ] All 5 models still selectable and still route correctly on `PromptCoach`.
- [ ] Sharpen and the token card still appear on `PromptCoach`.
- [ ] Adaptive controls still work end-to-end on `PromptCoach`.
- [ ] `PromptCoach`'s Terms/Privacy still show the paid-app text, not Lite's.

## 6. Accessibility

Run each of these against **both** schemes if time allows; at minimum
against `PromptCoach`.

- [ ] **Dynamic Type at the largest accessibility size** (Settings →
      Accessibility → Display & Text Size, or Simulator's Text Size
      slider). Check the model chips, report-card rows, and API-facts
      key/value rows in `ModelDetailView` — these are the likely
      truncation points given no fixed-size fonts anywhere in the app.
- [ ] **VoiceOver sweep.** Model chips announce "recommended"/"selected";
      the copy button announces "Copied"; model reference cards read as a
      single combined element (name + one-liner + price); Lite's locked
      model rows announce "locked in Prompt Coach Lite."
- [ ] **Reduce Motion on.** The `TimelineView` glass background should
      freeze rather than animate; sharpen/model-switch transitions should
      not use spring animation.
- [ ] **Dark and light mode**, both schemes, both look intentional (not
      just system-default colors with no tint).
- [ ] **iPad portrait + landscape** — the layouts aren't iPad-primary but
      shouldn't clip or overflow.

## 7. Performance

- [ ] **Instruments — Core Animation / FPS.** The 30fps `TimelineView`
      background: confirm no dropped frames while scrolling Result or
      Settings, and confirm it actually pauses when the view is off-screen
      (backgrounded or navigated away from), not just when the app itself
      backgrounds.
- [ ] **Typing latency.** Type a long ramble (a few hundred words) and
      confirm "Coach It" doesn't visibly hitch — the `measure` XCTest
      covers this synthetically, but a real device is the honest check.
- [ ] **Cold launch time**, both schemes, real device if available (not
      just Simulator, which is unrepresentative of launch performance).

## 8. Device-only (Simulator can't cover these)

- [ ] **Haptics** — Simulator doesn't render them. Confirm `Haptics.tap()` /
      `.select()` calls feel appropriate on a real iPhone (model chip
      selection, Sharpen, mute toggle, reset).
- [ ] **Dictation input** on the Ramble screen via the system keyboard mic.
- [ ] **Smart-quote filler matching on a real keyboard.** Type (don't
      paste) a ramble containing "if you don't mind" and "for what it's
      worth" so iOS auto-substitutes curly apostrophes, then confirm both
      still match the filler list and get trimmed. This exact bug already
      bit the pack once — see `PROMPT_COACH_TEST_REPORT.md` §3.5.
- [ ] **Low Power Mode** doesn't visibly change behavior (no network calls
      to throttle, but confirm the background animation degrades
      gracefully rather than looking broken).

## 9. Upgrade / persistence path

- [ ] Install `PromptCoach`, create a few history entries, mute a
      technique, drive adaptive controls to at least one adjustment.
      Force-quit and relaunch — confirm everything survived.
- [ ] Simulate an "upgrade" by building from an older commit with the
      pre-`tokenReport`/pre-`sharpened` `CoachResult` shape (if one is
      available), installing it, creating history, then installing this
      branch's build over it. History must survive — this is exactly the
      class of bug documented in the test report (§3.1, §3.numbers).

## 10. Pre-submission (after everything above is green)

- [ ] Replace the placeholder app icon for `PromptCoach` with real branding.
- [ ] Give `PromptCoachLite` its **own** icon, distinct from the paid app's
      — right now it inherits the same placeholder.
- [ ] Point `AppTier.paidAppStoreURL` at the real paid-app App Store
      listing. This requires the paid app to be live first — Lite's upsell
      links are meaningless (or broken) until then.
- [ ] Confirm no IAP products exist in App Store Connect for **either**
      listing — both apps' code and legal copy claim no IAP, no
      subscriptions.
- [ ] Decide and set the paid app's price in App Store Connect.
- [ ] Write App Review notes for both listings: fully functional offline,
      no account, no API key required. For Lite specifically, note that
      the reduced feature set is intentional (a free tier of a paid app),
      not an incomplete submission — reviewers sometimes flag a
      deliberately bare free app as unfinished.

---

## If something fails

Fix it, then re-run **all** of `python3 ios/PromptCoach/Tests/validate_pack.py`
(550 checks) before continuing down this list — a fix on the Swift side can
silently break an invariant the Python contract tests were guarding (e.g.
renaming a symbol the test greps for). The contract tests run in seconds and
catch the mechanical class of regression; this checklist catches everything
they structurally can't see.
