# WatchFighter — Design Document

A Street Fighter / Mortal Kombat–inspired 1v1 fighting game **designed around**
the Apple Watch's hardware (Digital Crown, side button, touchscreen, Taptic
Engine) rather than ported to it.

> **Core thesis:** You cannot fit a 6-button arcade stick on a 1.5" screen. So
> the combat *grammar* is rebuilt around the one input no console has — an
> analog dial (the Crown) — turning charge/parry into a tactile skill.

---

## 1. Design pillars

1. **One thumb, full fights.** Everything is reachable without occluding the
   screen with multiple fingers. The Crown lives on the side; the screen shows
   the fight.
2. **Timing over execution.** No quarter-circle-forward + punch on a wrist.
   Depth comes from *when* you commit (parry windows, charge-and-release),
   not from frame-perfect motion inputs.
3. **Haptics are a sense, not a garnish.** The Taptic Engine telegraphs the
   opponent's wind-up so a skilled player can feel an incoming heavy and parry
   it without staring. This is the Watch's unfair advantage over phones.
4. **Burst sessions.** Rounds are 20–40s. A full best-of-3 match fits in the
   time you'd spend checking a notification.

---

## 2. Hardware → control mapping

| Hardware            | Combat role                                              |
|---------------------|---------------------------------------------------------|
| **Digital Crown** (rotate) | Charge the special meter; the *speed* of rotation sets charge rate. Snap-release fires the loaded special. |
| **Digital Crown** (press)  | **Parry** — a short, high-reward defensive window. |
| **Side button**            | Universal attack / confirm. |
| **Tap — top half**         | Light attack (fast, low damage, low recovery). |
| **Tap — bottom half**      | Heavy attack (slow, high damage, punishable). |
| **Swipe ← / →**            | Step back / step forward (spacing & whiff-punish). |
| **Swipe ↑**                | Jump / anti-air. |
| **Long-press (hold)**      | Block (chip damage only, drains stamina). |
| **Accelerometer**          | *Optional* "Fatality" finisher: a wrist-flick on a downed opponent. |

> **Platform reality check.** watchOS does **not** expose the physical side
> button or the Crown *press* to third-party apps — only Crown *rotation* and
> on-screen gestures are available. So the shipping control map substitutes:
> **Crown rotate → charge**, **tap top/bottom → light/heavy**, **swipe → step**,
> **long-press → block**, **swipe-down (or two-finger tap) → parry**. The table
> above is the *ideal* grammar; the prototype implements the available subset
> (see `InputController` / `GameScene`).

### Why the Crown carries the specials
Rotation is genuinely analog and proportional. We map *angular velocity* to a
charge curve, so a hard spin loads fast but overshoots into a recovery penalty,
while a controlled spin tops the meter cleanly. That risk/reward dial is the
mechanical heart of the game.

---

## 3. Combat model

State machine per fighter:

```
idle ──► startup ──► active ──► recovery ──► idle
  │                                  ▲
  ├──► blockStun ───────────────────┘
  ├──► hitStun  ────────────────────┘
  ├──► parrySuccess ► (punish window opens for the parrier)
  └──► knockdown ──► wakeup ─────────► idle
```

- **Frame data** is real but coarse (everything in 10ms steps so it's legible on
  a wrist). Light = 3f startup, Heavy = 9f startup, Special = on release.
- **Parry**: a 6-frame window on Crown-press. Success = attacker frozen in
  recovery + Taptic "clack" + the parrier gets a guaranteed punish.
- **Block**: hold to absorb; takes ~15% chip and drains a stamina bar. Empty
  stamina = guard break (stagger, fully punishable).
- **Special meter** (0–100): filled by Crown charge and by landing/taking hits.
  At 100, the next Heavy becomes an **EX** version (the "super").

### Damage & rounds
- Two health bars, best-of-3.
- Round timer 30s; on timeout, higher HP% wins.
- Chip damage can win a round (configurable, MK-style on).

---

## 4. Haptic language (Taptic Engine)

| Event                  | Haptic pattern                              |
|------------------------|---------------------------------------------|
| Opponent heavy wind-up | `.directionUp` soft double-tick (telegraph) |
| You land a hit         | `.success` sharp                            |
| You get hit            | `.failure` thud                             |
| Parry success          | `.click` crisp                              |
| Special fully charged  | `.notification` rising                      |
| Guard break            | `.retry` heavy buzz                         |
| Round won/KO           | `.success` long                             |

Telegraphs are the skill expression: experienced players parry on feel.

---

## 5. Roster (prototype: 2 characters)

| Character | Archetype | Signature special (Crown-release) |
|-----------|-----------|-----------------------------------|
| **Volt**  | Rushdown  | *Arc Dash* — closes distance + combo starter |
| **Bastion** | Grappler/zoner | *Quake Slam* — armored, beats pokes |

Full game target: 6 characters, each re-skinning the same state machine with
different frame data + one unique special.

---

## 6. Tech stack

- **watchOS native Swift** (Unity has no usable watchOS target).
- **SpriteKit** for rendering (built into watchOS, 2D, hardware-accelerated).
- **SwiftUI + `SpriteView`** to host the scene (watchOS 7+).
- **`WKInterfaceDevice.play(_:)`** for haptics.
- **`digitalCrownRotation`** SwiftUI modifier for Crown input.
- Game logic is **engine-agnostic and unit-testable** (pure Swift structs in
  `Engine/`), so combat can be tested without a simulator.

### Performance budget
- 60 fps target, ≤16ms/frame. Two skeletal sprites + bars + FX particles only.
- No physics engine; bespoke hitbox/hurtbox AABB overlap each frame.
- Texture atlas per character, ≤512×512 to respect Watch memory.

---

## 7. Roadmap

- **M0 ✅:** Engine core, 2 fighters, crown-charge special, parry/block, AI
  opponent, health/meter bars, haptics. *Single device, vs CPU.*
- **M1 ✅:** 6-char roster + boss, projectiles, combo cancels (light→heavy→
  special), best-of-3 match flow, procedural parallax stages, full presentation
  (ROUND/FIGHT!/K.O./win, combo counter, round pips), **story mode** with
  character select, original arcade ladder + dialogue, and ending screens.
  Original cast & narrative — see `STORY.md`.
- **M2 ✅:** Procedural **skeletal animation** driven by the pure `Animator`
  (pose-per-state, smoothed in the renderer); asset-free **synthesised SFX**
  (enveloped tone generator, swap for samples later); **training mode** (dummy
  behaviours, infinite health/meter, frame-data overlay); **local 2-Watch
  multiplayer** via deterministic input-delay **lockstep** netcode over a
  swappable `MatchTransport` (loopback for tests, GameKit for real play).
- **M3 (in progress):** **Firmed up to the classic 2D-fighter base** — a real
  vertical **jump/gravity** axis with **air normals** and **2D hitbox/hurtbox**
  overlap (jump-ins, anti-airs, whiff-under-jump), **throws + throw-techs**,
  **combo damage scaling** (juggle taper), and a **stun → dizzy** stagger, plus
  a **"FINISH!"** finisher beat and the boss's **ritual-invincibility**. These
  are genre conventions implemented from scratch — no game's code/assets used.
  *Remaining:* progression/unlocks, per-character movelists, balance pass,
  versus character-select sync, real audio samples + music.

### Firm-up: fundamentals modelled on the classic base
- **Vertical axis:** `Fighter.height/vSpeed/airborne`; gravity integrated each
  tick; `Move.loY/hiY` define a vertical hitbox so the aerial game works.
- **Throws:** `Move.isThrow` beats block, whiffs on airborne foes, techs when
  both grab within a window.
- **Scaling:** `CombatSystem.scaling[]` tapers successive combo hits.
- **Dizzy:** hits accrue `stun`; crossing the threshold causes a `.dizzy`
  free-punish stagger.
- All deterministic (no RNG in the sim), so it stays netplay-safe.

### Netplay architecture (M2)
The combat sim is deterministic (no RNG on the PvP path), so two Watches stay in
sync by exchanging only inputs:
- `InputFrame` (Codable) carries one tick's intents.
- `LockstepSession` buffers local + remote inputs with an `inputDelay`; a tick
  advances only when both sides' inputs for it have arrived. Inputs entered now
  apply `inputDelay` ticks later, hiding latency.
- `MatchTransport` abstracts the wire — `LoopbackTransport` (in-process, tested)
  and `GameKitTransport` (real-time GameKit). Side assignment is deterministic
  (sorted player IDs), so both devices agree which fighter is which.
- *Limitation:* no rollback, so it's input-delay lockstep — fine on a good local
  link, sensitive to spikes. Rollback is a future option.

> **Note on cloning the real games:** mechanics and presentation conventions are
> replicated; copyrighted characters/names/art are not. The roster, stages, and
> story are original so the project is both legally clean and shippable.

---

## 8. Open risks

- **Screen real estate** — fighters must be readable at ~40×60px. Bold
  silhouettes, high-contrast, generous hit FX.
- **Crown ergonomics** — sustained spinning can fatigue; cap charge time at ~1s.
- **Input collision** — long-press-block vs tap-attack disambiguation needs a
  ~120ms threshold (tuned in `InputController`).
- **Battery/thermals** — 60fps SpriteKit is feasible but cap match length and
  idle to 30fps in menus.
