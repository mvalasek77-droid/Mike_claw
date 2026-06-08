import CoreGraphics

/// A playable character archetype. Re-skins the same state machine with
/// different frame data, a signature special, and presentation metadata.
/// Concrete characters live in `Roster.swift`.
struct CharacterSpec: Equatable {
    let id: String
    let name: String
    let title: String              // fighting-game-style epithet
    let bio: String
    let maxHealth: Int
    let walkSpeed: CGFloat         // points per tick
    let special: Move
    let exSpecial: Move
    let homeStageID: String

    // Presentation: RGB silhouette + accent (0...1).
    let bodyColor: RGBA
    let accentColor: RGBA

    /// If true, this fighter is INVINCIBLE (takes no damage) until the player
    /// performs the secret ritual perfectly. The final boss, Titus, uses this.
    var guardedByRitual: Bool = false
}

/// Tiny color value so the engine stays free of SpriteKit/UIKit.
struct RGBA: Equatable {
    let r, g, b, a: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// The lifecycle of a fighter on any given tick. Drives what input is legal.
enum FighterState: Equatable {
    case idle
    case startup      // attack windup (move committed, not yet active)
    case active       // hitbox live
    case recovery     // post-attack vulnerability
    case blockStun
    case hitStun
    case launched     // juggle state after a launcher
    case parry        // brief defensive window
    case knockdown
    case wakeup
}

/// Mutable per-round state for one combatant.
struct Fighter {
    let spec: CharacterSpec
    let facingRight: Bool        // player faces +x, AI faces -x

    var health: Int
    var meter: Int = 0           // 0...100
    var stamina: CGFloat = 100   // block budget
    var position: CGFloat        // x along the lane

    var state: FighterState = .idle
    var stateTimer: Int = 0      // ticks remaining in current state
    var currentMove: Move?
    var isBlocking: Bool = false
    var hasConnectedThisMove = false  // prevents one move hitting twice
    var canCancel = false             // a connected cancelable move opened a window
    var comboCount = 0                // hits in the current combo (for the HUD)
    var armorAvailable = false        // armored move can still absorb a hit

    init(spec: CharacterSpec, facingRight: Bool, position: CGFloat) {
        self.spec = spec
        self.facingRight = facingRight
        self.health = spec.maxHealth
        self.position = position
    }

    var isAlive: Bool { health > 0 }
    var healthFraction: CGFloat { CGFloat(health) / CGFloat(spec.maxHealth) }
    var meterFull: Bool { meter >= 100 }

    /// Neutral fighters can act; a connected cancelable move also opens a window.
    var canAct: Bool { state == .idle }
    var canStartAttack: Bool {
        state == .idle || (canCancel && (state == .active || state == .recovery))
    }

    mutating func addMeter(_ amount: Int) {
        meter = min(100, meter + amount)
    }

    /// Reset everything that should not carry across rounds.
    mutating func resetForRound(position: CGFloat) {
        health = spec.maxHealth
        meter = 0
        stamina = 100
        self.position = position
        state = .idle
        stateTimer = 0
        currentMove = nil
        isBlocking = false
        hasConnectedThisMove = false
        canCancel = false
        comboCount = 0
        armorAvailable = false
    }

    // MARK: - State transitions
    // These live on `Fighter` so `CombatSystem` can call them directly on its
    // stored `player`/`opponent` properties — a single write access — instead
    // of borrowing `self` inout and tripping Swift's exclusivity checks.

    mutating func enter(_ newState: FighterState, ticks: Int) {
        state = newState
        stateTimer = ticks
    }

    mutating func startMove(_ move: Move) {
        currentMove = move
        hasConnectedThisMove = false
        canCancel = false
        isBlocking = false
        armorAvailable = move.armor
        enter(.startup, ticks: move.startup)
    }

    /// Tick the active state's timer and perform any transition that falls due.
    mutating func advanceTimers() {
        guard state != .idle else { return }
        stateTimer -= 1
        guard stateTimer <= 0 else { return }

        switch state {
        case .startup:
            if let m = currentMove { enter(.active, ticks: m.active) } else { state = .idle }
        case .active:
            if let m = currentMove { enter(.recovery, ticks: m.recovery) } else { state = .idle }
        case .recovery, .blockStun, .hitStun, .parry, .wakeup, .launched:
            currentMove = nil
            canCancel = false
            comboCount = 0
            state = .idle
        case .knockdown:
            enter(.wakeup, ticks: 12)
        case .idle:
            break
        }
    }

    mutating func regenStamina() {
        if state == .idle && !isBlocking {
            stamina = min(100, stamina + CombatSystem.staminaRegen)
        }
    }
}
