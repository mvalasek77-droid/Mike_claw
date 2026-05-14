# CodeGenie Automation Audit

Status: partially automated, with honest user confirmation where Apple
requires account ownership or review responsibility.

## Automated Now

- Xcode project generation: `ios/project.yml` regenerates
  `ios/CodeGenie.xcodeproj`.
- Release build gate: `xcodebuild` succeeds with the iOS 26.1 SDK when
  code signing is disabled for CI-style validation.
- Backend test gate: pytest suite covers swarm, memory, archive,
  TestFlight, and Perfection Mode.
- Perfection Mode: deterministic 10,000-probe release matrix blocks
  App Store handoff on critical/error findings and now includes
  App-of-Year DNA checks.
- Icon Forge: creates 1024x1024 app icons and strips alpha.
- TestFlight upload: backend validates and uploads via `xcrun altool`
  when an IPA and Apple credentials are present.
- TestFlight processing: ASC API-key polling emits status events after
  upload.
- Decision memory: searchable decisions across builds.

## Mac-Assisted

- Pairing: iPhone can pair with the local Mac companion over the local
  network.
- Xcode/Safari: companion has commands to open Xcode projects and App
  Store Connect pages.
- App Store Connect fill: companion has a narrow
  `app_store_connect.fill` command, but production use still needs the
  iPhone flow to bind specific metadata fields to companion commands.
- Screenshots: companion can capture displays; scripted simulator
  walkthrough and App Store-size screenshot export are still roadmap
  work.

## User/Apple Required

- Apple Developer Program enrollment, team agreements, banking, tax, and
  certificates are user-owned.
- Apple ID sign-in and two-factor approval cannot be bypassed.
- Privacy nutrition labels can be drafted and checked, but the developer
  must confirm accuracy.
- Final App Review submission should remain an explicit human action.

## Current Risk

Do not describe the product as "everything automated" yet. The accurate
promise is: "CodeGenie automates build, quality gates, icon preparation,
TestFlight upload, and much of the App Store package, while the user
keeps control of Apple account, legal, privacy, and final submission
steps."
