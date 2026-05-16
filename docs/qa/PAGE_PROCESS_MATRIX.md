# Page Process Matrix

Baseline inventory for the iOS app as of the `replay-codegenie-ux-safety` build
on `d77dcc7` plus the cost-meter strip in this branch. Per `docs/AGENT_QA_PROTOCOL.md`
this matrix is the contract every release agent reads — rows without evidence
block the release gate.

`Status` legend: `not tested` (default), `pass`, `blocked`, `n/a`.
`Evidence` is either `screenshot:<path>` or `test:<xctest-symbol>`.

## Onboarding & legal

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ONB-001 | Splash | First launch | App opens | SplashView shows for ~1s then dissolves into Onboarding | UI Tester |  | not tested |
| ONB-002 | OnboardingView | First launch | Swipe through 7 slides | Each slide renders without truncation at Dynamic Type AX5 | UI Tester |  | not tested |
| ONB-003 | OnboardingView | Slide 7 final | Tap "Finish" | `hasFinishedOnboarding` flips, Terms gate appears | UI Tester |  | not tested |
| ONB-004 | TermsAndPrivacyView | Just arrived | Inspect content | Three cards present: Terms / Privacy / Costs | Reviewer |  | not tested |
| ONB-005 | TermsAndPrivacyView | Not scrolled to bottom | Tap agreement toggle | Toggle stays off, copy reads "Scroll to the bottom to enable" | UI Tester |  | not tested |
| ONB-006 | TermsAndPrivacyView | Scrolled, toggle off | Tap "Agree & continue" | Button is disabled | UI Tester |  | not tested |
| ONB-007 | TermsAndPrivacyView | Toggle on | Tap "Agree & continue" | `hasAcceptedTerms` flips, MainTabView appears, never re-prompted on relaunch | Reviewer |  | not tested |
| ONB-008 | TermsAndPrivacyView | Any | Tap "Read the full terms / privacy" links | Opens codegenie.app URL in Safari | Security Auditor |  | not tested |
| ONB-009 | OnboardingView | Reduce Motion on | Swipe slides | No parallax, transitions are simple opacity | Designer |  | not tested |

## Home

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HOME-001 | HomeView | Fresh install, 0 ship gates done | View | `shipReadinessCard` shows "0 of 4 done" with 4 tappable rows | UI Tester |  | not tested |
| HOME-002 | HomeView | 0 ship gates, prompt not seen | Tap "Start a new build" | `FirstBuildPromptView` sheet appears | UI Tester |  | not tested |
| HOME-003 | HomeView | 1+ ship gates done OR prompt already seen | Tap "Start a new build" | `DescribeAppView` opens directly | UI Tester |  | not tested |
| HOME-004 | HomeView | 4 of 4 ship gates done | View | `shipReadinessCard` hidden | UI Tester |  | not tested |
| HOME-005 | shipReadinessCard | Tap Xcode row | View | `XcodeReadinessView` sheet opens | UI Tester |  | not tested |
| HOME-006 | shipReadinessCard | Tap Pair Mac row | View | `PairMacView` sheet opens, `bridge.startBrowsing()` fires | UI Tester |  | not tested |
| HOME-007 | shipReadinessCard | Tap Apple Developer row | View | `AppleDevWalkthroughView` opens, jumps to step 3 if creds exist | UI Tester |  | not tested |
| HOME-008 | shipReadinessCard | Tap GitHub row | View | `GitHubSetupView` opens, jumps to step 2 if PAT exists | UI Tester |  | not tested |
| HOME-009 | XcodeReadinessView | On dismiss | Close | `xcode.readiness.acknowledged` flag flips, row goes green | UI Tester |  | not tested |
| HOME-010 | HomeView | Tap "Try a sample" | View | `SampleAppsView` opens | UI Tester |  | not tested |
| HOME-011 | HomeView | Tap "Watch the tour" | View | `TutorialView` in replay mode | UI Tester |  | not tested |
| HOME-012 | HomeView | Tap "Costs & keys" | View | `SettingsView` opens | UI Tester |  | not tested |
| HOME-013 | HomeView | recentJobs non-empty | View | Recent builds section renders job titles + stage | UI Tester |  | not tested |
| HOME-014 | FirstBuildPromptView | Tap "Start with Xcode" | View | XcodeReadinessView opens (not DescribeApp) | UI Tester |  | not tested |
| HOME-015 | FirstBuildPromptView | Tap "Just build something" | View | `firstBuild.prompt.shown` set, DescribeApp opens | UI Tester |  | not tested |
| HOME-016 | FirstBuildPromptView | Tap Cancel | View | Sheet dismisses, no state changed | UI Tester |  | not tested |

## Describe app

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BUILD-001 | DescribeAppView | BYOK + no API key | Tap "Build it" | Button is disabled, preflight banner reads "Add an Anthropic or OpenAI key" | UI Tester |  | not tested |
| BUILD-002 | DescribeAppView | BYOK + key present, prompt < 12 chars | Tap "Build it" | Button is disabled | UI Tester |  | not tested |
| BUILD-003 | DescribeAppView | BYOK + key + prompt ≥ 12 chars | Tap "Build it" | Cost confirmation sheet opens | UI Tester |  | not tested |
| BUILD-004 | DescribeAppView | Hosted, 0 free builds remaining | View | Preflight reads "0 of 3 free hosted builds left" with upgrade hint | Reviewer |  | not tested |
| BUILD-005 | DescribeAppView | Subscription mode | View | Preflight reads "Routed through your existing Claude/ChatGPT subscription" | UI Tester |  | not tested |
| BUILD-006 | Cost confirm sheet | Open | Inspect | Estimated cost, model name, and current cap shown | Reviewer |  | not tested |
| BUILD-007 | Cost confirm sheet | Tap "Confirm and build" | View | Sheet dismisses, build starts | UI Tester |  | not tested |
| BUILD-008 | Cost confirm sheet | Tap "Cancel" | View | Sheet dismisses, no build started | UI Tester |  | not tested |
| BUILD-009 | DescribeAppView | Tap a sample suggestion chip | View | Title + prompt populate, focus stays on prompt | UI Tester |  | not tested |

## Build screen

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BUILD-100 | BuildScreen | useRemote, mid-build | View | `costMeterStrip` visible under topBar with live $ + cap + bar | UI Tester |  | not tested |
| BUILD-101 | costMeterStrip | Spend < 50% of cap | View | Strip tint is success green | UI Tester |  | not tested |
| BUILD-102 | costMeterStrip | Spend 50-80% of cap | View | Strip tint is amber warning | UI Tester |  | not tested |
| BUILD-103 | costMeterStrip | Spend ≥ 80% of cap | View | Strip tint is red, `costApproachingCallout` banner appears below | UI Tester |  | not tested |
| BUILD-104 | costMeterStrip | No cap set | View | Strip reads "— no cap set", bar at 0%, success green tone | UI Tester |  | not tested |
| BUILD-105 | Pipeline card | Tap "What's this?" | View | Pipeline jargon sheet opens | UI Tester |  | not tested |
| BUILD-106 | BitDrop card | Tap "What's this?" | View | BitDrop jargon sheet opens | UI Tester |  | not tested |
| BUILD-107 | Perfection Mode CTA | Tap "What's Perfection Mode?" | View | Perfection jargon sheet opens | UI Tester |  | not tested |
| BUILD-108 | BuildScreen | Cap hit mid-build | Backend emits `cost.cap_hit` | `costCapCallout` shows "Lift cap × 2" button | UI Tester |  | not tested |
| BUILD-109 | costCapCallout | Tap "Lift cap × 2" | View | Cap doubled, `/resume` called, build continues | UI Tester |  | not tested |
| BUILD-110 | BuildScreen | Stage flips to `.failed` | View | `failureOverlay` covers screen with last 5 log lines + Try again + Resume + Close | UI Tester |  | not tested |
| BUILD-111 | failureOverlay | Tap "Try again" | View | `runBuild()` re-fires | UI Tester |  | not tested |
| BUILD-112 | failureOverlay | Tap "Resume from last checkpoint" | View | `swarm.resume(jobID:)` called | UI Tester |  | not tested |
| BUILD-113 | BuildScreen | Stage `.readyForTest` | View | `successOverlay` with Perfection Mode + simulator + Submit + GitHub backup + Download | UI Tester |  | not tested |
| BUILD-114 | successOverlay | Tap "Submit to App Store" with no Apple creds | View | `AppleDevWalkthroughView` opens | UI Tester |  | not tested |
| BUILD-115 | successOverlay | Tap "Submit" first time with creds | View | `ReleaseStageExplainer` sheet opens | UI Tester |  | not tested |
| BUILD-116 | ReleaseStageExplainer | Tap "Send to TestFlight" | View | Explainer dismisses, `submitToAppStore(skipExplainer:true)` runs | UI Tester |  | not tested |
| BUILD-117 | successOverlay | Tap "Back up to GitHub" with no GitHub creds | View | `GitHubSetupView` opens | UI Tester |  | not tested |
| BUILD-118 | successOverlay | Tap "Back up to GitHub" with creds | View | `swarm.syncGitHub(jobID:config:)` called, success banner | UI Tester |  | not tested |
| BUILD-119 | BuildScreen | Tap pause | View | `swarm.pause(jobID:)` called, pause badge appears | UI Tester |  | not tested |
| BUILD-120 | BuildScreen | Tap snapshots | View | SnapshotPickerView opens | UI Tester |  | not tested |
| BUILD-121 | BuildScreen | Tap dismiss | View | Build cancels, returns to Home | UI Tester |  | not tested |
| BUILD-122 | BuildScreen | Reduce Motion on | View | No orb animation; progress is fade-only | Designer |  | not tested |

## Settings

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SETTINGS-001 | SettingsView | Just Build mode | View | Cost cap / agent routing / custom agents / admin tiles are hidden | UI Tester |  | not tested |
| SETTINGS-002 | SettingsView | Power mode | View | All power tiles visible | UI Tester |  | not tested |
| SETTINGS-003 | authModePicker | Tap "API key" | View | `keyEntryBlock` renders for both Anthropic + OpenAI | UI Tester |  | not tested |
| SETTINGS-004 | keyEntryBlock | Tap "Save" | View | Key written to Keychain, "Saved to Keychain" toast shows for ~1.5s | Security Auditor |  | not tested |
| SETTINGS-005 | authModePicker | Tap "Subscription" | View | `subscriptionBlock` lists provider sign-in links | UI Tester |  | not tested |
| SETTINGS-006 | authModePicker | Tap "CodeGenie hosted" | View | `hostedBlock` shows Free / Pro / Studio pills + pricing breakdown | UI Tester |  | not tested |
| SETTINGS-007 | hostedBlock | StoreKit unavailable | View | Plan pills still render, no purchase button shown | Reviewer |  | not tested |
| SETTINGS-008 | modelComparison | Tap a model row | View | `preferredModelID` updates, estimator re-runs | UI Tester |  | not tested |
| SETTINGS-009 | estimatorBlock | View | Inspect | "$X.XXX per build · ≈ N builds for $10" matches model rate | Reviewer |  | not tested |
| SETTINGS-010 | costCapBlock | First launch | View | Toggle is ON, default $5 | Reviewer |  | not tested |
| SETTINGS-011 | costCapBlock | Tap toggle off | View | `costCapUSD` becomes nil | UI Tester |  | not tested |
| SETTINGS-012 | costCapBlock | Drag slider | View | New cap saved every step, live label updates | UI Tester |  | not tested |
| SETTINGS-013 | setupGuidesBlock | View | Inspect | Xcode, GitHub, Apple Dev walkthrough tiles all visible | UI Tester |  | not tested |
| SETTINGS-014 | telemetryBlock | Toggle on | View | `Telemetry.enabled` flips, stats appear when buildsStarted > 0 | UI Tester |  | not tested |
| SETTINGS-015 | aboutBlock | Tap "What's new" | View | `ChangelogView` opens | UI Tester |  | not tested |
| SETTINGS-016 | aboutBlock | Tap "Recent build failures" | View | `CrashLogView` opens | UI Tester |  | not tested |
| SETTINGS-017 | supportBlock | Tap "Report a bug" | View | `BugReportView` opens | UI Tester |  | not tested |

## Walkthroughs

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WALK-001 | AppleDevWalkthroughView | Step 0 | Tap "No — open the enrollment page" | Opens developer.apple.com in Safari | UI Tester |  | not tested |
| WALK-002 | AppleDevWalkthroughView | Step 0 | Tap "Yes — I'm enrolled" | Advances to step 1 | UI Tester |  | not tested |
| WALK-003 | AppleDevWalkthroughView | Step 1, Team ID < 6 chars | Tap Continue | Disabled | UI Tester |  | not tested |
| WALK-004 | AppleDevWalkthroughView | Step 3 | Tap Save | All three creds written to Keychain (Issuer ID, Key ID, .p8 PEM) | Security Auditor |  | not tested |
| WALK-005 | AppleDevWalkthroughView | Has creds on open | View | Jumps directly to step 3 | UI Tester |  | not tested |
| WALK-006 | GitHubSetupView | Step 0 | Tap "No — open github.com/signup" | Opens GitHub signup in Safari | UI Tester |  | not tested |
| WALK-007 | GitHubSetupView | Step 0 | Tap "Yes — I have an account" | Advances to step 1 | UI Tester |  | not tested |
| WALK-008 | GitHubSetupView | Step 1 | Tap "Open token page" | Opens github.com/settings/tokens/new with scopes preset | UI Tester |  | not tested |
| WALK-009 | GitHubSetupView | Step 2 | Tap Save | PAT written to Keychain, "Stored in iOS Keychain" toast | Security Auditor |  | not tested |
| WALK-010 | XcodeReadinessView | Tap "Open in Mac App Store" | View | macappstores:// URL opens | UI Tester |  | not tested |
| WALK-011 | XcodeReadinessView | No Mac paired | View | Status card shows "Pair a Mac first" warning | UI Tester |  | not tested |
| WALK-012 | ReleaseStageExplainer | Tap "Send to TestFlight" | View | onChoose(.testflight) fires, sheet dismisses | UI Tester |  | not tested |
| WALK-013 | ReleaseStageExplainer | Tap "Submit to the App Store" | View | onChoose(.appStore) fires | UI Tester |  | not tested |
| WALK-014 | ReleaseStageExplainer | Tap "Tell me more about App Review" | View | Opens developer.apple.com/distribute in Safari | UI Tester |  | not tested |
| WALK-015 | PairMacView | View | Inspect | `prereqBlock` lists Xcode + Companion with a Download button | UI Tester |  | not tested |
| WALK-016 | PairMacView | Bonjour service found | View | Discovered list shows entry with "Tap to pair" | UI Tester |  | not tested |
| WALK-017 | PairMacView | Manual paste valid URL | Tap Connect | `bridge.connect(pairingURL:)` fires, status flips to connecting | UI Tester |  | not tested |

## App Store Connect guide

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ASC-001 | AppStoreConnectGuideView | View | Inspect | `legendCard` defines Auto / Hybrid / You badges at the top | Reviewer |  | not tested |
| ASC-002 | ASCStepCard | Every step | Inspect | Each step shows correct Auto/Hybrid/You badge next to step number | UI Tester |  | not tested |
| ASC-003 | ASCStepCard | Current step | Tap action button | Action runs, step is marked complete on success | UI Tester |  | not tested |
| ASC-004 | metadataCard | View | Inspect | Drafted title, subtitle, keywords visible | Reviewer |  | not tested |
| ASC-005 | progressBar | Step 5 of 10 | View | Bar is 50% filled | UI Tester |  | not tested |
| ASC-006 | Step 10 ("Submit for review") | View | Inspect | Badge is "You" — manual confirmation only | Security Auditor |  | not tested |

## Release & failure paths

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| REL-001 | BuildScreen | Submit + Perfection not green | Tap Submit | shipBanner reads "Run Perfection Mode and clear blockers" | Reviewer |  | not tested |
| REL-002 | BuildScreen | Submit + no Apple creds | Tap Submit | `AppleDevWalkthroughView` opens, no upload starts | Security Auditor |  | not tested |
| REL-003 | BuildScreen | Submit + creds + explainer unseen | Tap Submit | `ReleaseStageExplainer` opens once, `release.explainer.seen` set on dismiss | UI Tester |  | not tested |
| REL-004 | BuildScreen | Submit + creds + explainer seen | Tap Submit | `swarm.runReleaseReadiness` runs, then `swarm.ship` | UI Tester |  | not tested |
| REL-005 | runReleaseReadiness | Not ready | Response | shipBanner reads first `nextActions` entry | Reviewer |  | not tested |
| REL-006 | BuildScreen | Network drop mid-build | Disconnect | SSE reconnect attempts; user sees "reconnecting" hint | UI Tester |  | not tested |
| REL-007 | BuildScreen | App backgrounded mid-build | Background then foreground | Stream resumes, no duplicate events | UI Tester |  | not tested |
| REL-008 | BuildScreen | Demo sample replay | View | All UI surfaces identical to a real build, no tokens spent | UI Tester |  | not tested |

## Coverage Summary

- **Total rows**: 99
- **Passed rows**: 0
- **Blocked rows**: 0
- **Untested rows**: 99
- **Light mode screenshots**: pending
- **Dark mode screenshots**: pending
- **AX5 Dynamic Type pass**: pending
- **Reduce Motion pass**: pending
- **VoiceOver pass**: pending
- **Final Reviewer model**: pending
- **Final Security model**: pending
- **Final gate**: **blocked** (no evidence)

## How to fill this in

1. UI Tester runs through each row on the simulator and a real device.
2. For each row that passes, replace `not tested` with `pass` and attach evidence in the form `screenshot:docs/qa/screens/<id>.png` or `test:CodeGenieTests.<file>.<symbol>`.
3. For rows that can't be tested (e.g. `BUILD-108` cap hit requires the backend to actually emit `cost.cap_hit`), mark `blocked` and note the prerequisite.
4. Reviewer + Security Auditor sign off by changing the bottom-line gate to `green` only when every row is `pass`, `n/a`, or `blocked` with a tracked workaround.
