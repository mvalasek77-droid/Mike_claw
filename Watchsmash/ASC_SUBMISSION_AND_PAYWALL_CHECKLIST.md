# Watch Smash — App Store Connect Submission Checklist

Grounded in the actual state of this repo as of `31bfd1a`. ✅ = verified in the
codebase. Everything unchecked is ordered by what actually blocks a release.

**Nothing below can be done from CI.** Every remaining item needs either a Mac
with Xcode or the App Store Connect web UI. CI produces a *simulator-only*
unsigned build and cannot sign, archive, or upload.

---

## What's already done in code

| Item | Where |
|---|---|
| ✅ Bundle ID `com.valasek.watchsmash` | `project.yml` |
| ✅ Version 1.0, build 1, apple-generic versioning | `project.yml` |
| ✅ Export-compliance key (`ITSAppUsesNonExemptEncryption: NO`) | `project.yml` |
| ✅ Privacy manifest — no tracking, no collection, UserDefaults reason CA92.1 | `Resources/PrivacyInfo.xcprivacy` |
| ✅ App icon set, display name "Watch Smash" | `Assets.xcassets/AppIcon.appiconset` |
| ✅ Store copy drafted | `STORE_LISTING.md` |
| ✅ StoreKit 2 paywall, fully implemented | `Purchases/PurchaseManager.swift` |
| ✅ IAP product ID `com.valasek.watchsmash.fullroster` | `PurchaseManager.fullRosterProductID` |
| ✅ Local StoreKit config wired to the Run scheme | `Watchsmash.storekit`, `project.yml` |
| ✅ Restore Purchases button | `GameScreen.versusSelectOverlay` |
| ✅ `Transaction.updates` listener (Ask to Buy) | `PurchaseManager.listenForUpdates()` |
| ✅ VoiceOver labels, Reduce Motion, Always On Display | `GameScreen`, `WatchsmashCanvas` |
| ✅ CI green: build + 62 unit tests + copy audit | `.github/workflows/watchsmash.yml` |

---

## 1. Apple Developer Program
- [ ] Enrolled ($99/yr) — required before anything else.
- [ ] Team ID in `project.yml` (`UDM4W27W9V`) matches the enrolled team.

## 2. Create the App Store Connect record
- [ ] My Apps → **+** → New App, bundle ID `com.valasek.watchsmash`.
- [ ] Platform: **watchOS**. Category: Games → Action.
- [ ] SKU (internal, never shown to users) — e.g. `watchsmash001`.

## 3. Create the IAP product — do this BEFORE the first upload
The code already references this exact product ID. It must exist in ASC or the
paywall silently shows nothing (`fullRosterProduct` stays `nil`).

- [ ] Features → In-App Purchases → **+** → **Non-Consumable**.
- [ ] Product ID **exactly** `com.valasek.watchsmash.fullroster` — a typo here
      is unrecoverable; IDs can never be reused once created.
- [ ] Reference name: `Full Roster`. Display name + description (see
      `Watchsmash.storekit` for the copy already written).
- [ ] Price tier — the local config is set to **$2.99**; match it or update the
      `.storekit` file so local testing mirrors production.
- [ ] Upload the required IAP review screenshot (the VS screen showing
      "UNLOCK ALL $2.99" and "RESTORE").
- [ ] IAP review notes — see the wording in §9 below.

## 4. Signing & archive
- [ ] Generate the project: `cd Watchsmash && xcodegen generate`
- [ ] Open `Watchsmash.xcodeproj`, Signing & Capabilities → your team,
      automatic signing, **Release** config.
- [ ] Product → Archive (destination: **Any watchOS Device**, not a simulator).
- [ ] Organizer → Distribute App → App Store Connect → Upload.
- [ ] Bump `CURRENT_PROJECT_VERSION` in `project.yml` for **every** subsequent
      upload — ASC rejects duplicate build numbers.

## 5. On-device play-test (nothing below matters until this is clean)
Run from Xcode on a real watch, not the simulator.

Core paths:
- [ ] Full tournament win → Dracula unlocks in VS.
- [ ] Lose a floor → Pit → beat Abaddon → climb resumes.
- [ ] Lose in the Pit → run actually ends.
- [ ] Titus/Million Room: normal attacks can't kill him; the secret combo can.

Never tested on hardware (new, and only unit-tested underneath):
- [ ] **Resume**: start a run, reach floor 3+, background the app, relaunch →
      CONTINUE appears and lands on the right floor. Then NEW RUN → the saved
      run is discarded.
- [ ] **Always On Display**: wrist down mid-fight → the fight freezes and does
      not keep taking damage; wrist up → resumes without a time jump.
- [ ] **Paywall**: buy with a Sandbox tester → roster unlocks → force-quit →
      relaunch → still unlocked. Then delete + reinstall → Restore returns it.
- [ ] **VoiceOver on**: HUD, menus, and game-over screen all read sensibly.
- [ ] **Reduce Motion on**: blood spray, gore, and the red screen flash are
      suppressed; the game is still playable.
- [ ] Audio: a phone call or Siri interrupts → music resumes afterward.

## 6. Store listing
- [ ] Paste name / subtitle / promo / description / keywords from
      `STORE_LISTING.md`.
- [ ] **Support URL** — still a placeholder in `STORE_LISTING.md`. Apple
      requires a real, reachable page. A public GitHub repo or a one-page site
      is enough.
- [ ] Copyright line (e.g. "© 2026 <your name or entity>").

## 7. Screenshots
- [ ] Capture on each Apple Watch size ASC currently requires (check the list
      in ASC — it changes between releases).
- [ ] The CI artifact `watchsmash-demo-screenshots` gives usable simulator
      frames as a starting point.
- [ ] Suggested five: mid-combo with HUD, VS select (showing the paywall in
      context — doubles as the IAP screenshot), a story cutscene, the Million
      Room boss, and the Hell/Abaddon fight.

## 8. Age rating — answer honestly
This app has stylized blood, severed limbs and heads, a screen-wide blood
splash, and a vampire transformation.

- [ ] Declare **Blood and Gore** and **Horror/Fear Themes** in the
      questionnaire — not merely "Cartoon Violence." Under-declaring risks a
      rejection or a forced post-release rating change.
- [ ] Expect 12+ or 17+. The outcome is deterministic from your answers, so
      don't try to steer it.

## 9. Privacy label, export compliance, review notes
- [ ] Privacy nutrition label: **Data Not Collected** — matches the manifest.
      There is no analytics SDK and the crash monitor writes locally only. If
      you ever add a remote crash/analytics backend, this label AND
      `PrivacyInfo.xcprivacy` must change together.
- [ ] Export compliance: the `ITSAppUsesNonExemptEncryption: NO` key is already
      in the build, so ASC should not prompt. If it does, answer "No."
- [ ] **Review notes** — paste something like:

  > No account or login is required; the app has no backend.
  >
  > The entire 15-floor tournament, both training modes, and every fighter are
  > free and unlockable by playing. The single in-app purchase ("Full Roster",
  > $2.99, non-consumable) only unlocks the VS-mode roster immediately instead
  > of earning it through tournament progress. Nothing is permanently paywalled.
  > To test: main menu → VS → press right past the unlocked fighters to reach a
  > locked one; the UNLOCK ALL and RESTORE buttons appear there.
  >
  > Long-pressing the title on the main menu for ~1.2s toggles a hidden
  > developer TEST menu. It is a debug tool, not unfinished user-facing
  > content.

## 10. Submit
- [ ] TestFlight internal build first; play it on your own watch through
      TestFlight, not just via Xcode.
- [ ] Submit the app build **and** the IAP together — a new IAP is reviewed
      alongside the first version that references it, never on its own.
- [ ] Budget extra time for v1.0: a gore-heavy fighting game usually draws a
      manual first-pass review.

---

## Known gaps (deliberate, not oversights)
- **No archive/upload workflow in CI.** Signing credentials aren't available to
  the runner. Archiving is a local Xcode step.
- **All UI strings are hardcoded English.** Not an App Store blocker for an
  English-only release; localization is deferred post-1.0.
- **Paywall verified by compilation and unit tests only.** No purchase has
  actually been made against the `.storekit` config or the sandbox yet — this
  is the single highest-risk untested path, which is why it's in §5.
