# CodeGenie Roadmap

## Shipped (this branch)

**iOS app**
- iOS 26 Liquid Glass theme (fluid glassmorphism, depth shadows,
  adaptive haptics) with iOS 17–25 `.ultraThinMaterial` fallback
- 7-step cartoon onboarding mirroring the YouTube tutorial — now
  re-watchable from Home + Settings via the shared `TutorialView`
- Home screen with hero, quick grid, recent jobs, Xcode-instructions
  card, quality checklist
- 9-step pocket Xcode reference + ⌘-shortcut cheat sheet
- Describe-your-app flow with chips, suggestions, category, style
- Build screen with progress orb, log, BitDrop mini-game, live
  transcript, and live cost meter
- BitDrop mini-game (Tetris-style with Swift glyphs) — standalone
  `GameHomeView` with high score, lines, difficulty picker, and a
  first-launch help overlay
- Remote Xcode preview / TestFlight handoff
- 10-step App Store Connect walkthrough
- Cursor-style DiffPreview wired to the swarm's `diff` SSE events
- Icon Forge (GPT-image-1 → App-Store-safe export)
- Splash, vector CodeGenie logo, MainTabView (Home / Build / Play /
  Apps / Settings)
- Settings: LLM cost table, BYOK keys, subscription pairing, hosted
  plans, cost estimator, Pair-your-Mac sheet
- **Accessibility & Reduce-Motion-correct everywhere** — Splash, the
  animated background orbs, the progress orb, every tab transition,
  the tutorial dots all honour `accessibilityReduceMotion`
- Resources: `PrivacyInfo.xcprivacy`, `Info.plist` with Bonjour /
  NSLocalNetwork strings, asset catalog scaffolding

**Backend (Genie Swarm)**
- ConversationRuntime tool-use loop (Claude Code style)
- Codex-style sandbox: fs boundary, network policy, RSS / timeout caps
- 8 agents in 2 layers (parallel build + parallel test)
- Tools: read/write/edit/list, sandboxed shell, grep, xcodebuild,
  swiftlint, simctl, Apple HIG retrieval, **memory (remember /
  recall / decisions), TestFlight upload (altool / ASC API key)**
- Async EventBus + SSE fan-out at `/api/coding/swarm/{job}/stream`
- Diff decision route + GET counterpart for the iOS round-trip
- Head-to-head model ranker (Cursor-style judge → JSON verdict)
- SQLite-backed project memory, paste-prepended into every agent prompt
- 48 pytest tests, all green; agent prompts in `prompts/*.md`

**Mac companion (`mac_companion/`)**
- Native Swift Package, macOS 14+, Network.framework server
- Bonjour `_codegenie-companion._tcp` advertisement, token auth
- Commands: ping, open_xcode_project, open_safari, xcodebuild (with
  streamed line events), screenshot, `app_store_connect.fill`
  (AppleScript + JS, mandatory per-call user confirmation)
- XCTest smoke suite for token persistence

## Next (the 30-day push)

- **Per-agent model routing** in Settings (Opus for Reviewer, Sonnet
  for Coder, Haiku for Linter) — uses `model_overrides` in BuildRequest
- **Build retry on test failures** — orchestrator loops Coder +
  Integrator on red unit tests, capped at 3 attempts
- **Native QR scanner** in `PairMacView` so pairing is one tap
- **Memory weight decay** — old facts gradually lose confidence
- **Wire `Memory.briefing()` at agent.started** — surface what the
  agent "remembers" as a transcript event
- **TestFlight status polling** — after upload, watch processing state
  and surface the build into the listing automatically

## Later (the killer-feature track)

- **CodeGenie Memory v2** — embeddings, FTS5 retrieval, decay curves
- **Live device tunnel** — stream a real iPhone screen back through the
  runner (not just simulator) using devicectl + WebRTC
- **Self-evaluating agents** — each agent's output graded by a separate
  judge; underperformers demoted in routing
- **Plugin marketplace** — third-party agents (RevenueCat wiring,
  Firebase setup) that drop into the swarm
- **WWDC theme presets** — each year's keynote-feel as one-tap themes
- **Native Mac menu bar app** for the companion (replaces the CLI)

## Forever

> "Apple is cracking down on vibe coding."

We don't ship without:
- the reviewer agent's findings = 0 critical
- the security agent's findings = 0 critical
- a green test layer
- a senior-engineer-grade diff preview the user can accept
- Reduce-Motion correctness on every animated surface
- accessibility labels on every interactive view
- Dynamic Type without truncation

That bar moves up each quarter, never down.
