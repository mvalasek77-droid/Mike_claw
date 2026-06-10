# ETERNAL COMBAT — Bug Log

Tracked issues from a senior static-review pass. **Important context:** there is
no Swift toolchain in this environment, so nothing here has been *compiled* — the
pure game logic is covered by headless XCTest suites, but the watchOS / SpriteKit
/ SwiftUI / GameKit layers are verified by reading only. Status legend:
**FIXED** · **MITIGATED** · **OPEN** · **NEEDS-BUILD** (only an Xcode build can
confirm).

## Critical / Blocker

| # | Status | Area | Issue | Resolution |
|---|--------|------|-------|------------|
| 1 | **FIXED** | GameKit | Real-time GameKit (`GKMatch`/`GKMatchmaker`) is **not available on watchOS** → `GameKitTransport.swift` would fail to compile. | Replaced with a compiling stub that reports "online versus coming via companion iPhone". Netcode core (`LockstepSession`, `VersusMatchup`, `LoopbackTransport`) stays and is unit-tested. |
| 2 | **FIXED** | UX | **Soft-lock in Training**: endless practice never reports a result, and there was no way back to the menu from any fight. | Added an always-on in-fight exit button (`FightView` → `GameFlow.exitFight()`). |

## High

| # | Status | Area | Issue | Resolution |
|---|--------|------|-------|------------|
| 3 | **OPEN (experimental)** | Netplay | Lockstep versus only submits input frames during the `.fighting` phase, so during `ROUND`/`K.O.` announcer phases the peer can stall waiting for inputs (wall-clock phase drift). Versus is already flagged experimental and blocked by #1 anyway. | Planned: submit empty frames every render frame in versus regardless of phase; consume only while fighting. Deferred until the iPhone-relay transport exists. |
| 4 | **FIXED** | Engine | `pendingDrift` (air horizontal velocity) was not cleared in `resetForRound`. | Reset added. |

## Medium

| # | Status | Area | Issue | Notes |
|---|--------|------|-------|-------|
| 5 | **OPEN** | Engine | No fighter-vs-fighter separation clamp while **airborne**, so a jumping fighter can drift through/over the opponent. Cosmetic in practice; no crash. | Add an air pushbox or clamp drift near the opponent. |
| 6 | **MITIGATED** | Audio | `AVAudioEngine` is (re)started on every `FightScene` (guarded by a `started` flag); music reschedules each fight. | Acceptable; consider lifting audio to app scope. |
| 7 | **NEEDS-BUILD** | SwiftUI | An overlay `Button` sits above a full-screen `DragGesture(minimumDistance:0)`. Hit-test priority *should* favor the top button, but only a build confirms taps aren't swallowed. | Verify on simulator; if needed, exclude the button's frame from the drag. |

## Verified OK (static review)

- **Determinism for netplay:** the simulation path has **no RNG** — `AIController`'s
  RNG is single-player only (no AI in versus). `LockstepSession` keeps two sims
  byte-identical (tested). `tickCount` is monotonic, so not resetting `grabTick`/
  `lastProjectileTick` per round is safe.
- **Hit-resolution precedence** in `applyHit` (throw → parry → armor → ritual-invuln
  → block → clean) is ordered so the invincible boss can't be thrown/chipped past
  the rite, and armor/parry interactions are exploit-free (covered by tests).
- **Exhaustive switches** over `FighterState` (incl. new `.dizzy`) are complete in
  `Animator`, `Fighter.advanceTimers`, and `FightScene.stateTag`.
- **Combo scaling, dizzy, throws, jumps, projectile cooldown, ritual** all covered
  by headless tests (`Tests/`).

## How this was found

A four-agent review swarm was launched (compile-risk, engine bugs, UX/a11y, tests)
but hit a usage limit before returning; findings above are from a manual
senior-level static pass. The single highest-value next action is a real Xcode
build pass — see `SHIP_CHECKLIST.md`.
