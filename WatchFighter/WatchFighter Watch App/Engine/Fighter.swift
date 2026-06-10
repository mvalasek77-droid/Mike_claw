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

    /// Per-character normals. Default to the shared normals so most characters
    /// need no override. (Flavor `specialName` is computed in Roster.swift.)
    var light: Move = .light
    var heavy: Move = .heavy
    var airLight: Move = .airLight
    var airHeavy: Move = .airHeavy
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
    case dizzy        // stunned (free punish) after taking too much
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
    var comboScalingHits = 0          // hits used for combo damage scaling

    // Vertical axis (the aerial game).
    var height: CGFloat = 0           // feet height above the floor (points)
    var vSpeed: CGFloat = 0           // vertical velocity (points/tick)
    var airborne = false
    var airActionUsed = false         // one air normal per jump
    var stun: CGFloat = 0             // builds toward a dizzy

    init(spec: CharacterSpec, facingRight: Bool, position: CGFloat) {
        self.spec = spec
        self.facingRight = facingRight
        self.health = spec.maxHealth
        self.position = position
    }

    var isAlive: Bool { health > 0 }
    var healthFraction: CGFloat { CGFloat(health) / CGFloat(spec.maxHealth) }
    var meterFull: Bool { meter >= 100 }
    var standHeight: CGFloat { 58 }

    /// Hurtbox top in world Y (feet height + standing height).
    var hurtTop: CGFloat { height + standHeight }

    /// Grounded neutral can act; a connected cancelable move also opens a window.
    var canAct: Bool { state == .idle && !airborne }
    var canStartAttack: Bool {
        (state == .idle && !airborne) || (canCancel && (state == .active || state == .recovery))
    }
    /// One attack is allowed while airborne (the jump-in).
    var canAirAct: Bool { state == .idle && airborne && !airActionUsed }

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
        comboScalingHits = 0
        armorAvailable = false
        height = 0; vSpeed = 0; airborne = false; airActionUsed = false
        pendingDrift = 0
        stun = 0
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
        case .recovery, .blockStun, .hitStun, .parry, .wakeup, .launched, .dizzy:
            currentMove = nil
            canCancel = false
            comboCount = 0
            comboScalingHits = 0
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
        // Stun bleeds off slowly while not being hit.
        if state == .idle { stun = max(0, stun - CombatSystem.stunDecay) }
    }

    // MARK: - Aerial physics

    mutating func jump(_ velocity: CGFloat, drift: CGFloat) {
        guard !airborne, state == .idle else { return }
        airborne = true
        vSpeed = velocity
        airActionUsed = false
        pendingDrift = drift
    }
    var pendingDrift: CGFloat = 0

    /// Integrate gravity each tick. Returns true on the frame the fighter lands.
    mutating func applyGravity(gravity: CGFloat) -> Bool {
        guard airborne else { return false }
        vSpeed -= gravity
        height = max(0, height + vSpeed)
        position += pendingDrift
        if height <= 0 {
            height = 0; vSpeed = 0; airborne = false; pendingDrift = 0
            // Land out of an air normal into a brief, vulnerable recovery.
            if state == .active || state == .startup { enter(.recovery, ticks: 6) }
            return true
        }
        return false
    }
}
