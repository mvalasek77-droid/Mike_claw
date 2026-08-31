# ETERNAL COMBAT: Ascendant 🥊⌚

*(working codename `WatchFighter` — name "Eternal Combat" chosen deliberately to
avoid the "Kombat" trademark; do a clearance search before any release)*

A fighting game **built for the Apple Watch** — Digital Crown, touchscreen, and
Taptic Engine instead of a 6-button arcade stick. It clones the *mechanics and
presentation conventions* of the classic 2D fighter genre (super/EX meter,
projectiles, combo cancels, best-of-3 rounds, KO + announcer, parallax stages)
with a **100% original cast, story, and art**.

> **Is this even possible on a Watch?** Yes — not as a 1:1 arcade port, but as a
> fighter whose combat *grammar* is rebuilt around the Crown (an analog dial no
> console controller has) plus timing and haptics. See **[DESIGN.md](DESIGN.md)**.
>
> **On "cloning the real games":** game *mechanics* aren't copyrightable, so the
> feel can be faithful. Specific characters, names, and artwork from Street
> Fighter / Mortal Kombat are protected IP and are **not** reproduced here — the
> roster and story are original (see **[STORY.md](STORY.md)**), which also means
> this is something you could actually ship.

## What's here (M0 + M1)

A playable single-player arcade campaign vs CPU on a single Watch:

```
WatchFighter/
├── DESIGN.md                       # Design doc: pillars, controls, combat model
├── STORY.md                        # Original story, roster bios, arcade ladder
├── project.yml                     # XcodeGen spec -> generates the Xcode project
├── WatchFighter Watch App/
│   ├── WatchFighterApp.swift       # @main -> RootView
│   ├── GameFlow.swift              # Screen state machine (title→select→story→fight→end)
│   ├── Views.swift                 # Title / Character Select / Story card / Ending (SwiftUI)
│   ├── GameView.swift              # FightView: SpriteView host + Crown + gestures
│   ├── GameScene.swift             # FightScene: match-flow presentation + render loop
│   ├── StageBuilder.swift          # Procedural parallax stage rendering (SpriteKit)
│   └── Engine/                     # PURE, testable core (no UI deps)
│       ├── Move.swift              #   frame data: light/heavy/special/EX, projectiles
│       ├── Fighter.swift           #   per-round state machine + combo state + RGBA
│       ├── Roster.swift            #   6 original fighters + boss
│       ├── Stage.swift             #   7 stage specs (colors + motif)
│       ├── Intent.swift            #   normalised commands + emitted events
│       ├── CombatSystem.swift      #   simulation: hits, blocks, parries, combos, projectiles
│       ├── MatchFlow.swift         #   best-of-3 scoreline + round resets
│       ├── StoryMode.swift         #   arcade ladder + original dialogue
│       ├── InputController.swift   #   gestures + Crown -> Intents
│       ├── AIController.swift      #   CPU opponent
│       └── Haptics.swift           #   CombatEvent -> Taptic Engine
└── Tests/
    ├── CombatSystemTests.swift     # core combat
    └── MechanicsTests.swift        # projectiles, combos, match flow, story
```

### The cast (all original)

| Fighter | Archetype | Signature special |
|---------|-----------|-------------------|
| **Tetsu** | All-rounder (default) | Rising launcher palm |
| **Volt** | Electric rushdown | Arc dash |
| **Ember** | Fire zoner | Cinder projectile |
| **Frost** | Ice zoner | Slow freezing projectile |
| **Mirage** | Teleport rushdown | Long phase strike |
| **Bastion** | Armored grappler | Quake slam (launcher) |
| **Corsair** | Swashbuckler duelist | Long cutlass lunge |
| **Nova** | Bounty-hunter zoner | Fast plasma shot |
| **Vesper** | Swordmaster | Longest-reach drawing cut (launcher) |
| **Marina** | Acrobatic athlete | Fast rushdown, strong aerials |
| **Feng** *(secret, 12 wins)* | B-movie kung-fu legend | Lightning kicks; shouts his own SFX |
| **Onyx** *(boss)* | The Ascendant | Overtuned launcher |
| **Titus** *(FINAL BOSS)* | Undefeated boxer | **INVINCIBLE** (zero damage) until the 8-step rite — armored haymaker |

> **On real-world / pop-culture characters:** requested likenesses (a
> Mike-Tyson-style boxer, a Johnny-Depp-style pirate, a Pam-Anderson/Baywatch
> athlete, a Uma-Thurman/Kill-Bill swordswoman, etc.) are real people and
> copyrighted characters — those can't ship, and "the same thing renamed" is
> still infringement. Instead the cast draws on those *archetypes* with
> **original** designs: Titus (undefeated boxer), Corsair (sea-rogue), Nova
> (bounty hunter), Vesper (swordmaster), Marina (rescue-swimmer athlete). All
> designed as capable, non-objectified fighters.

### Controls (using inputs watchOS exposes to apps)

| Input | Action |
|-------|--------|
| **Rotate Crown** | Charge the special meter (analog — spin speed = charge rate) |
| **Tap top / bottom** | Light / Heavy attack (light→heavy→special cancels into combos) |
| **Tap far-left** | Throw (beats block; whiffs on airborne foes) |
| **Tap far-right (meter ≥ 50)** | Fire special; at full meter it's the EX super |
| **Swipe up** | Jump (jump-in with an air light/heavy) |
| **Swipe ← / →** | Step back / forward |
| **Swipe down** | Parry (6-frame window → punish) |
| **Hold** | Block (chip + stamina drain; empty = guard break) |

**Firmed-up fundamentals (classic-fighter base):** a real **vertical jump** with
gravity + air normals and 2D hitbox/hurtbox overlap (jump-ins, anti-airs,
whiff-under-jump), **throws + throw-techs**, **combo damage scaling** (long
juggles taper off), and a **stun → dizzy** stagger. Mechanics are genre
conventions, implemented from scratch — no game's code or assets are used.

## Build & run

```bash
brew install xcodegen          # one-time
cd WatchFighter
xcodegen generate              # creates WatchFighter.xcodeproj
open WatchFighter.xcodeproj    # run on a watchOS Simulator or device
```

The `Engine/` layer has no SpriteKit/SwiftUI dependencies (haptics stubbed
off-device), so the combat core, match flow, and story compile/test headless.

## Modes

- **Story** — pick a fighter, climb the six-floor ladder with dialogue (M1).
- **Training** — practice room: dummy behaviours (stand/block/jab/CPU), infinite
  health & meter toggles, live frame-data overlay (`TrainingMode.swift`).
- **Versus** *(experimental)* — two Watches over Game Center using deterministic
  input-delay **lockstep** netcode (`Netcode.swift`, `GameKitTransport.swift`).
  The netcode is unit-tested via a loopback; the GameKit transport is wired to
  the API but untested on-device and degrades gracefully if matchmaking fails.

## Status

- [x] **M0** — engine core, 2 fighters, crown-charge special, parry/block, AI, HUD, haptics
- [x] **M1** — 6-char roster + boss, projectiles, combo cancels, best-of-3 match flow,
      parallax stages, full presentation, **story mode** + character select + endings
- [x] **M2** — **skeletal animation** (`Skeleton.swift` + `SkeletonRenderer.swift`),
      asset-free **synthesised SFX** (`SoundEngine.swift`), **training mode**, and
      **local 2-Watch multiplayer** via lockstep netcode + GameKit transport
- [x] **Game feel** — hitstop on impact, camera shake, hit-spark bursts, combo
      praise ("NICE!/BRUTAL!/SAVAGE!"), and an **armor** mechanic powering the
      undefeated final boss **Titus** (invincible until the secret rite)
- [x] **Firm-up (classic base)** — jump/gravity + air normals + 2D boxes, throws +
      techs, combo damage scaling, stun→dizzy; plus a "FINISH!" finisher beat
- [x] **Progression** — win-milestone + story-clear **unlocks** (persisted),
      locked character-select with hints, per-character **normals/movelists**,
      and a **How To Play** screen
- [x] **Versus sync** — both Watches pick fighters; a deterministic
      `NetMessage` handshake (`VersusMatchup`) builds an identical world on both
- [x] **Music** — asset-free looping lo-fi track (synth), toggle in the menu;
      first-pass **balance** with guardrail tests (see `BALANCE.md`)
- [x] **Polish** — per-character aerials (Marina dive kick, Vesper air slash),
      projectile **cooldown** (anti-spam), and a CPU **difficulty selector**
- [x] **Hardening** — fixed a Training **soft-lock** (in-fight exit button),
      fixed the watchOS GameKit **compile blocker** (online versus stubbed),
      added **humor** (win quotes + taunts) and an optional **BLOOD** toggle.
      See `BUGLOG.md` (known issues) and `SHIP_CHECKLIST.md` (honest ship gate).
- [ ] **Ship gate** — an Xcode build pass + device test (no Swift toolchain
      here), real app icon, content rating, and the iPhone-relay for online play
      balance pass, character-select sync for versus, real audio samples & music

> **M2 caveat:** still not compiled here (no Swift toolchain on Linux). Pure
> layers — animation math, lockstep netcode, training — are covered by headless
> tests; the watchOS rendering/audio/GameKit layers are written against the APIs
> but need an Xcode build pass. Versus needs two signed devices to truly verify.

See **[DESIGN.md](DESIGN.md)** for roadmap and risks, **[STORY.md](STORY.md)** for the campaign.
