# WatchFighter 🥊⌚

A Street Fighter / Mortal Kombat–inspired **1v1 fighting game built for the
Apple Watch** — designed around the Digital Crown, touchscreen, and Taptic
Engine instead of a 6-button arcade stick.

> **Is this even possible on a Watch?** Yes — not as a 1:1 arcade port, but as a
> fighter whose combat *grammar* is rebuilt around the Crown (an analog dial no
> console controller has) plus timing and haptics. See **[DESIGN.md](DESIGN.md)**
> for the full rationale.

## What's here (M0 prototype)

A working architecture for vs-CPU combat on a single Watch:

```
WatchFighter/
├── DESIGN.md                       # Full design doc: pillars, controls, combat model
├── project.yml                     # XcodeGen spec -> generates the Xcode project
├── WatchFighter Watch App/
│   ├── WatchFighterApp.swift       # SwiftUI @main entry
│   ├── GameView.swift              # SpriteView host + Digital Crown wiring
│   ├── GameScene.swift             # SpriteKit render + fixed-timestep loop + touch input
│   └── Engine/                     # PURE, testable combat core (no UI deps)
│       ├── Move.swift              #   frame data for light/heavy/special/EX
│       ├── Fighter.swift           #   character specs + per-round state machine
│       ├── Intent.swift            #   normalised commands + emitted events
│       ├── CombatSystem.swift      #   the simulation: ticks, hits, blocks, parries
│       ├── InputController.swift   #   gestures + Crown -> Intents
│       ├── AIController.swift      #   CPU opponent
│       └── Haptics.swift           #   CombatEvent -> Taptic Engine
└── Tests/
    └── CombatSystemTests.swift     # headless unit tests for the combat core
```

### Controls (prototype, using inputs watchOS exposes to apps)

| Input | Action |
|-------|--------|
| **Rotate Crown** | Charge the special meter (analog — spin speed = charge rate) |
| **Tap top half** | Light attack |
| **Tap bottom half** | Heavy attack |
| **Tap far-right (meter ≥ 50)** | Fire special / EX |
| **Swipe ← / →** | Step back / forward |
| **Swipe down** | Parry (6-frame window → punish) |
| **Hold** | Block (chip + stamina drain; empty = guard break) |

## Build & run

```bash
brew install xcodegen          # one-time
cd WatchFighter
xcodegen generate              # creates WatchFighter.xcodeproj
open WatchFighter.xcodeproj    # run on a watchOS Simulator or device
```

The `Engine/` layer has no SpriteKit/SwiftUI dependencies (haptics are stubbed
off-device), so the combat core and its tests compile headless for CI.

## Status

- [x] M0 — engine core, 2 fighters, crown-charge special, parry/block, AI, HUD, haptics
- [ ] M1 — sprite atlases + animation, sound, full round/match flow
- [ ] M2 — local multiplayer (GameKit, two Watches), training mode
- [ ] M3 — 6-char roster, fatalities, progression

See **[DESIGN.md](DESIGN.md)** for the roadmap and open risks.
