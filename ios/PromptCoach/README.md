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

## Not verified here

Written and structurally checked in a Linux container with no Xcode — **not
compiled or run.** The JSON is validated against the Swift structs in CI-style
checks, but a real build/run/VoiceOver/Dynamic-Type pass on a Mac is still
required before submission (see `docs/DISTRIBUTION_READINESS.md`).

## Monetization & privacy

Paid up front, no in-app purchases, no accounts, no analytics, no tracking.
Nothing typed leaves the device. Legal pages: `docs/prompt-coach-privacy.html`,
`docs/prompt-coach-terms.html`.
