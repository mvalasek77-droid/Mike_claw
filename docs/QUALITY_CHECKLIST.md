# CodeGenie Quality Checklist

Apple is cracking down on "vibe coded" apps. Every release CodeGenie ships
— and every app *built by* CodeGenie — must clear this list.

A `✓` next to a row means the current branch passes it. A `□` means it's
still pending sign-off from a real Mac/device run.

## 1. Functionality

- [✓] All shipped features work end-to-end against the simulated builder
- [✓] No half-finished flows; every button leads somewhere meaningful
- [✓] No demo data shipping in production builds
- [✓] No commented-out code, no `// TODO`s, no `print` debugging
- [✓] Force-unwraps audited (only Keychain SecItem dictionary literals)

## 2. Tested rigorously

- [✓] **48 backend pytest tests, all green**
  (sandbox, tools, runtime, streaming, memory, ranker, testflight, e2e)
- [✓] Swift brace + import audit on every file
- [□] iPhone 16 / SE / 16 Pro Max flows on real hardware
- [□] Cold start, warm start, background → foreground
- [□] Offline path, slow network (Network Link Conditioner: 3G)
- [□] Memory profile clean (Instruments → Leaks)
- [□] Cold-start time < 1.5s on iPhone SE
- [□] MetricKit clean over 10-min soak

## 3. Polish

- [✓] Every animation eases — no linear interpolation on UI
  (central `Theme/Motion.swift`)
- [✓] **All transitions respect `accessibilityReduceMotion`**
  (Splash, LiquidGlassBackground orbs, ProgressOrb, TabBar swap,
   TutorialView dots, OnboardingIllustrations, CodeGenieLogo)
- [✓] Adaptive haptics: Core Haptics for transient, UIKit fallback
- [✓] Empty states designed (ProjectsGalleryView, BitDrop game over)
- [✓] Pressed-state feedback on every primary button

## 4. Accessibility

- [✓] Every interactive view has an `accessibilityLabel` /
  `accessibilityHint`
- [✓] Decorative views are `.accessibilityHidden(true)`
- [✓] ScoreTile / StatPill / Diff cards combine into single VoiceOver
  elements with sensible labels
- [✓] Tab bar items declare `.isSelected` trait when active
- [□] Dynamic Type tested up to AX5 on real device
- [□] 4.5:1 contrast confirmed on real device (we use system white on
  dark glass — should pass, needs measurement)

## 5. Dark mode

- [✓] Designed dark-first; semantic colors throughout
- [✓] AccentColor asset has light + dark appearance pair
- [✓] Glass surfaces preserve legibility against dark backdrops
- [□] Light mode visited on every screen

## 6. Liquid Glass / iOS 26

- [✓] Glass surfaces use `.glassEffect(.regular)` on iOS 26+
- [✓] Graceful fallback to `.ultraThinMaterial` on iOS 17–25
- [✓] Adaptive haptics (Core Haptics where available)
- [✓] Depth effects: parallax-aware shadows, no flat drops
- [✓] Subtle 0.5–1pt white edge stroke on every glass surface

## 7. Senior-engineer code review

- [✓] No retain cycles (`[weak self]` in every long-lived Task)
- [✓] `@MainActor` discipline on UI-mutating types (AppSession,
  Credentials, BitDropGame, CompanionBridge, SwarmClient, IconForge,
  CostTracker, DiffStream)
- [✓] Error paths handled — every async throw has a UI consumer
- [✓] No premature abstractions; one canonical type per concept
- [✓] Dependencies pinned in `requirements.txt` / `pyproject.toml`

## 8. App Store readiness

- [✓] `PrivacyInfo.xcprivacy` declares NSPrivacyAccessedAPI reasons
  (UserDefaults CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1)
- [✓] `Info.plist` ships `NSLocalNetworkUsageDescription`, Bonjour
  service list, camera + photo strings, `ITSAppUsesNonExemptEncryption`
- [✓] Asset catalog scaffolded with AccentColor + AppIcon slot
- [□] 1024×1024 PNG icon (no alpha, no rounded corners) dropped in
  `Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
  (use Icon Forge to generate)
- [□] Screenshots for 6.7" + 6.1"
- [□] Marketing copy ≤ 4000 chars, keywords ≤ 100 chars
- [□] Support URL responds 200

## 9. CodeGenie-specific gates

- [✓] Genie Swarm Reviewer can raise findings (`severity: critical`
  blocks release)
- [✓] Genie Swarm Security Auditor wired with read-only tool set
- [✓] Build green on the simulator before user is asked to test
- [✓] Diff visibly previewed (DiffPreviewView) before any file write is
  promoted by the user
- [✓] BitDrop loads in < 200ms (single SwiftUI state, no asset I/O)
- [✓] Tutorial re-watchable from Home + Settings (no first-launch trap)
