# CodeGenie Roadmap

## Now (this PR)

**iOS app**
- Liquid Glass theme (iOS 26 `.glassEffect`, fallback for iOS 17–25)
- Cartoon onboarding slideshow (7 steps, mirrors the YouTube tutorial)
- Home screen + Xcode pocket-guide
- Describe-your-app flow (chips, suggestions, category, style)
- Build screen with progress orb + log + BitDrop mini-game
- Remote Xcode preview (streamed simulator session, TestFlight handoff)
- App Store Connect step-by-step guide
- Adaptive haptics

**Backend**
- Genie Swarm: 8 agents in 2 layers (build + test)
- ConversationRuntime tool-use loop (Claude Code style)
- Sandbox (Codex-style) — fs boundary, network policy, RSS cap, timeout
- Tools: read/write/edit/list, sandboxed shell, grep, xcodebuild, swiftlint, simctl, apple_docs
- SSE streaming (`/api/coding/swarm/{job}/stream`)
- Checkpointing per agent for rollback

## Next (the 30-day push)

- **Diff preview UI**: render unified diffs in the iOS app, accept/reject per file
- **Mac companion**: lightweight desktop app that pairs with the phone, opens
  Xcode and Safari on demand (the "open Xcode remotely" hook)
- **Asset pipeline**: GPT-image-1 icon generation, screenshot rendering, alpha-strip
- **TestFlight automation**: `altool` upload from the runner, build status polling
- **Multi-model routing**: Claude for code, GPT for naming/copy, head-to-head
  ranking ("Cursor-style"), user picks the winner per turn
- **Cost meter**: real-time token / API spend per build, budget caps

## Later (the killer-feature track)

- **CodeGenie Memory**: long-running project memory across builds — the
  swarm remembers your preferences, naming, palette, prior tradeoffs
- **Live device tunnel**: stream a real iPhone screen back through the
  runner (not just simulator) using devicectl + WebRTC
- **App Store submission bot**: drives Safari on the user's Mac via a
  thin native helper, types the metadata, uploads screenshots
- **Plugin marketplace**: third-party agents (analytics setup, RevenueCat
  wiring, Firebase setup) that drop into the swarm
- **Self-evaluating agents**: each agent's output is graded by a separate
  judge model; underperformers are demoted in routing
- **WWDC theme presets**: ship every year's keynote-feel as one-tap themes

## Forever

- "Apple is cracking down on vibe coding." We don't ship without:
  - the reviewer agent's findings = 0 critical
  - the security agent's findings = 0 critical
  - a green test layer
  - a senior-engineer-grade diff preview the user can accept

That bar moves up each quarter, never down.
