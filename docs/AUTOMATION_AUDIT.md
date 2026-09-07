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
- Release readiness: backend audits Xcode archive state, IPA presence,
  Apple upload credentials, privacy manifest, privacy policy, terms/EULA,
  listing metadata, screenshots, GitHub readiness, and final Apple
  confirmation before TestFlight.
- Icon Forge: creates 1024x1024 app icons and strips alpha.
- Archive and export: the ship stage packages a signed `.ipa` before
  uploading, using the host's Xcode when the backend runs on macOS and
  the paired Mac companion when a transport is registered. Signing is
  automatic (`-allowProvisioningUpdates` with the ASC API key), so the
  user does not create certificates or profiles by hand. On a host with
  no Xcode and no paired Mac it refuses and says so, rather than
  reporting a missing IPA.
- TestFlight upload: backend validates and uploads via `xcrun altool`
  when an IPA and Apple credentials are present. Requires the Xcode
  command line tools on the backend host; without them the run reports
  the missing toolchain instead of failing obscurely.
- TestFlight processing: ASC API-key polling emits status events after
  upload.
- GitHub sync: backend can initialize/commit a generated workspace, push
  a named branch to a user-provided repository, and open a pull request
  when a GitHub token is provided. It excludes `.codegenie/`, session
  metadata, archives, and DerivedData.
- Decision memory: searchable decisions across builds.

## Mac-Assisted

- Pairing: iPhone can pair with the local Mac companion over the local
  network.
- Xcode/Safari: companion has commands to open Xcode projects and App
  Store Connect pages.
- App Store Connect fill: companion has a narrow
  `app_store_connect.fill` command, but production use still needs the
  iPhone flow to bind specific metadata fields to companion commands.
- Archive/export: automated (see above), but it still needs a Mac
  somewhere — either the backend host or a paired companion — signed
  into the user's Apple Developer account. The companion implements
  `xcodebuild.archive_export`; note that nothing currently registers a
  backend companion transport, so on a non-macOS backend that route is
  unavailable and packaging must happen on the host.
- Screenshots: companion can capture displays; scripted simulator
  walkthrough and App Store-size screenshot export are partially wired
  but still need production flow binding.

## User/Apple Required

- Apple Developer Program enrollment, team agreements, banking, tax, and
  certificates are user-owned.
- Apple ID sign-in and two-factor approval cannot be bypassed.
- Privacy nutrition labels can be drafted and checked, but the developer
  must confirm accuracy.
- Terms of use/EULA can be drafted, but the developer remains
  responsible for legal accuracy and choosing Apple's standard EULA vs.
  custom terms.
- Final App Review submission should remain an explicit human action.

## Current Risk

Do not describe the product as "everything automated" without the
qualifier "where Apple allows it." The accurate promise is:
"CodeGenie automates build, quality gates, icon preparation, release
readiness, GitHub branch/PR sync, TestFlight upload, and much of the
App Store package, while the user keeps control of Apple account, legal,
privacy, and final submission steps."
