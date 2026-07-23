# CodeGenie UI Test Suite — Setup

## Add the test target to your Xcode project

1. Open `CodeGenie.xcodeproj` in Xcode
2. File → New → Target → **UI Testing Bundle**
3. Name it `CodeGenieUITests`, language Swift, target `CodeGenie`
4. Delete the auto-generated test file Xcode creates
5. Add all `.swift` files from this directory to the new target:
   - `CodeGenieTestBase.swift` (base class — add first)
   - `T01_OnboardingFlowTests.swift`
   - `T02_HomeScreenTests.swift`
   - `T03_DescribeAndBuildTests.swift`
   - `T04_SettingsTests.swift`
   - `T05_ASCGuideTests.swift`
   - `T06_TabNavigationTests.swift`
   - `T07_GameAndPlayTests.swift`
   - `T08_ProjectsGalleryTests.swift`
   - `T09_AccessibilityTests.swift`
   - `T10_EdgeCaseTests.swift`

## App launch arguments

The test base class passes `-UITests` on every launch. To support
the `-resetDefaults` and `-hasFinished*` flags, add this to
`CodeGenieApp.swift` in your `init()`:

```swift
#if DEBUG
if CommandLine.arguments.contains("-resetDefaults") {
    let domain = Bundle.main.bundleIdentifier!
    UserDefaults.standard.removePersistentDomain(forName: domain)
}
#endif
```

The `@AppStorage` flags (`hasFinishedOnboarding`, `hasAcceptedTerms`,
`hasChosenPricing`) are already set via launch arguments, which
`@AppStorage` reads automatically.

## Run the suite

- **All tests:** Product → Test (Cmd-U) with scheme `CodeGenieUITests`
- **Single file:** Click the diamond next to any test class
- **Single test:** Click the diamond next to any test method

Pick any iPhone simulator (iPhone 15 Pro recommended) with iOS 17+.

## What gets tested

| File | Coverage |
|------|----------|
| T01 | Splash → 7 onboarding slides → Terms scroll gate → Pricing → Home |
| T02 | Home: hero, CTA, ship readiness, quality checklist, tiles, sheets |
| T03 | Describe form, suggestions, DNA readout, build screen layout |
| T04 | Settings: auth mode, BYOK keys, power mode, all sub-screens |
| T05 | ASC 10-step guide structure and navigation |
| T06 | Tab bar, all 5 tabs, rapid switching, dismiss behavior |
| T07 | Play tab, BitDrop game, difficulty selectors |
| T08 | Projects gallery, empty state, job cards |
| T09 | Accessibility labels, Dynamic Type, VoiceOver traversal |
| T10 | State persistence, regressions, landscape, bg/fg, no subscription |

## Screenshots

Every test captures labeled screenshots at key moments. After a test
run, find them in the Xcode Test Report (Cmd-9 → select the run).
Screenshots are named `NN-description` matching the test number.

## Test ordering

Files are prefixed `T01`–`T10` so they run in logical order (funnel
first, then feature-by-feature, then edge cases). Within each file,
methods are numbered `test01`–`testNN`.

## Notes

- Tests that depend on backend connectivity (live build, SSE stream)
  use the demo/sample build path instead — no backend or API keys
  needed.
- Tests use `if guard.waitForExistence` patterns for optional UI
  elements so they skip gracefully on different configurations.
- The suite is designed for a fresh simulator. Reset the simulator
  (Device → Erase All Content and Settings) for the cleanest run.
