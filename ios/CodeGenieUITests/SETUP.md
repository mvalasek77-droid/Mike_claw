# CodeGenie UI Test Suite — Setup

## Running

The UI test target is declared in `project.yml`, so generating the
project is all the setup there is:

```sh
cd ios
xcodegen generate
xcodebuild test -project CodeGenie.xcodeproj -scheme CodeGenie \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Launch arguments

Every launch passes `-UITests`. In a debug build that does two things,
both in `App/AppEnvironment.swift`:

- builds run on a local stand-in, so the suite needs no server, no API
  key and no network;
- `-resetDefaults` clears saved state before the app reads any of it.

Neither exists in a release build. `-hasFinishedOnboarding true` and
similar pairs are ordinary `UserDefaults` launch arguments and need no
app code.

## Logic tests

The rules behind the screens — submission steps, review states,
listing validation, the next-step engine, pairing codes — are tested
separately and much faster, without a simulator:

```sh
cd ios/CodeGenieLogic
swift test
```

## Run the suite

- **All tests:** Product → Test (Cmd-U) with scheme `CodeGenieUITests`
- **Single file:** Click the diamond next to any test class
- **Single test:** Click the diamond next to any test method

Pick any iPhone simulator (iPhone 15 Pro recommended) with iOS 17+.

## What gets tested

| File | Coverage |
|------|----------|
| T01 | Splash → 7 onboarding slides → Terms scroll gate → Pricing → Home |
| T02 | Home: hero, next-step card, ship readiness, tiles, sheets |
| T03 | Describe form, suggestions, DNA readout, build screen layout |
| T04 | Settings: auth mode, BYOK keys, power mode, all sub-screens |
| T05 | Apple Developer walkthrough |
| T11 | App Store Connect guide: 18 steps, listing validation, gates, review phase |
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
