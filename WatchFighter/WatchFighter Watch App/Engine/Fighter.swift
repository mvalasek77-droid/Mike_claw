import CoreGraphics

/// A playable character archetype. Re-skins the same state machine with
/// different frame data + one signature special.
struct CharacterSpec: Equatable {
    let name: String
    let maxHealth: Int
    let walkSpeed: CGFloat          // points per tick
    let special: Move
    let exSpecial: Move

    static let volt = CharacterSpec(
        name: "Volt",
        maxHealth: 100,
        walkSpeed: 2.4,
        special: { let s = Move.special(damage: 16, reach: 60, pushback: 18, startup: 5)
                    return s }(),
        exSpecial: Move.ex(from: Move.special(damage: 16, reach: 60, pushback: 18, startup: 5))
    )

    static let bastion = CharacterSpec(
        name: "Bastion",
        maxHealth: 120,
        walkSpeed: 1.6,
        special: { let s = Move.special(damage: 20, reach: 40, pushback: 26, startup: 8)
                    return s }(),
        exSpecial: Move.ex(from: Move.special(damage: 20, reach: 40, pushback: 26, startup: 8))
    )
}

/// The lifecycle of a fighter on any given tick. Drives what input is legal.
enum FighterState: Equatable {
    case idle
    case startup      // attack windup (move committed, not yet active)
    case active       // hitbox live
    case recovery     // post-attack vulnerability
    case blockStun
    case hitStun
    case parry        // brief Crown-press defensive window
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

    init(spec: CharacterSpec, facingRight: Bool, position: CGFloat) {
        self.spec = spec
        self.facingRight = facingRight
        self.health = spec.maxHealth
        self.position = position
    }

    var isAlive: Bool { health > 0 }
    var healthFraction: CGFloat { CGFloat(health) / CGFloat(spec.maxHealth) }
    var meterFull: Bool { meter >= 100 }

    /// Only neutral/idle fighters can start a new action.
    var canAct: Bool { state == .idle }

    /// The leading edge of this fighter's hitbox when an attack is active.
    func hitboxFront(reach: CGFloat) -> CGFloat {
        facingRight ? position + reach : position - reach
    }

    mutating func addMeter(_ amount: Int) {
        meter = min(100, meter + amount)
    }

    // MARK: - State transitions
    // These live on `Fighter` (not `CombatSystem`) so the system can call them
    // directly on its stored `player`/`opponent` properties — a single write
    // access — instead of borrowing `self` inout and tripping Swift's
    // exclusive-access checks.

    mutating func enter(_ newState: FighterState, ticks: Int) {
        state = newState
        stateTimer = ticks
    }

    mutating func startMove(_ move: Move) {
        currentMove = move
        hasConnectedThisMove = false
        isBlocking = false
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
        case .recovery, .blockStun, .hitStun, .parry, .wakeup:
            currentMove = nil
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
