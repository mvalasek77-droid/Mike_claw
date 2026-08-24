# Prompt Coach (iOS)

A ramble → clean, model-ready Claude prompt tool. Type a half-formed prompt; the
app detects the task, recommends the cheapest model that fits, rewrites the
prompt using Anthropic's prompt-engineering techniques, and **names each
technique it applied** so you learn the method. Everything runs on device.

Built from the spec in `docs/` — the coaching rules live in
`PromptCoach/Resources/model-pack.json` (a copy of `docs/model-pack.json`).

## Architecture

| Layer | File | Role |
|---|---|---|
| Data | `Models/ModelPack.swift` | Codable decode of the versioned model pack |
| Brain | `Engine/CoachEngine.swift` | On-device task detection, recommender, report card, deterministic rewrite, retired-pattern stripping |
| State | `Store/AppState.swift` | Loads the pack, holds the engine, persists history as local JSON |
| Theme | `Theme/Glass.swift` | Liquid Glass (matches the CodeGenie app), per-model tint, haptics |
| UI | `Views/*` | Ramble → Result (recommend + prompt + report card + techniques) → Learn / History |

The on-device engine is deterministic: it structures the ramble (role, context,
tagged data, cleaned ask, success criterion, self-check, per-model footer),
scores the original against the technique checklist, and strips retired patterns
(prefill / temperature / `budget_tokens` / CRITICAL-language). A model-graded
rewrite via the user's own Anthropic key ("Test It") is a future network path and
is intentionally **not** in the engine.

## Build

Requires a Mac with Xcode 16+ and [XcodeGen](https://github.com/yonyz/XcodeGen):

```sh
cd ios/PromptCoach
xcodegen generate      # creates PromptCoach.xcodeproj from project.yml
open PromptCoach.xcodeproj
```

Deployment target iOS 17. The iOS 26 `glassEffect` is availability-gated with an
`.ultraThinMaterial` fallback, so it builds and runs on 17–25 too.

## Assets

`Resources/Assets.xcassets` has a real `AccentColor` (matches `Glass.accent`,
identical light/dark pair to the CodeGenie app for family consistency) and
separate opaque 1024×1024 App Store icons for the paid and Lite targets. The
two icons share the sparkle-and-prompt-card language while remaining visually
distinct in App Store search results.

## Not verified here

Written and structurally checked in a Linux container with no Xcode — **not
compiled or run.** Verified instead by: (1) decode-compatibility checks between
`model-pack.json` and every Swift `Codable` struct, including that the report
card's checklist items exactly match what `CoachEngine` scores, and that every
`recommend`/`default` model ID resolves; (2) a manual read-through of every
Swift file for compile-risk patterns (unused bindings, Equatable/Hashable
synthesis, Codable key coverage, `@State`/`@Published` mutation safety,
`navigationDestination(item:)` / `sheet(item:)` Identifiable+Hashable
requirements); (3) mirroring `project.yml` and the asset catalog layout exactly
against the sibling CodeGenie app's already-working XcodeGen configuration
rather than guessing the shape.

A real build/run/VoiceOver/Dynamic-Type pass on a Mac is still required before
submission — no amount of static review substitutes for `xcodegen generate &&
xcodebuild`. See `docs/DISTRIBUTION_READINESS.md` for the full pre-submission
checklist (written for CodeGenie; the same categories apply here).

## Monetization & privacy

Paid up front, no in-app purchases, no accounts, no analytics, no tracking.
Nothing typed leaves the device. Legal pages: `docs/prompt-coach-privacy.html`,
`docs/prompt-coach-terms.html`.
