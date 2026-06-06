import CoreGraphics

/// The pure simulation core. Holds two fighters, consumes `Intent`s, advances
/// the fight one fixed tick at a time, and emits `CombatEvent`s for the
/// presentation layer (rendering + haptics) to react to.
///
/// Deliberately free of SpriteKit / SwiftUI so it can be unit-tested headless.
struct CombatSystem {

    // MARK: Tunables
    static let tickRate: Double = 60          // fixed simulation Hz
    static let laneMin: CGFloat = 20
    static let laneMax: CGFloat = 380
    static let bodyHalfWidth: CGFloat = 18
    static let minSeparation: CGFloat = 30     // fighters can't overlap/pass through
    static let parryWindow = 6                  // ticks
    static let chargeToFire: Int = 50           // meter needed to throw a special
    static let chargeRate: CGFloat = 140        // meter per unit of Crown rotation
    static let blockChipScale: CGFloat = 1.0
    static let staminaPerBlock: CGFloat = 9
    static let staminaRegen: CGFloat = 0.4      // per idle tick

    // MARK: State
    private(set) var player: Fighter
    private(set) var opponent: Fighter
    private(set) var roundTimer: Int            // ticks remaining
    private(set) var isOver = false
    private(set) var winner: Side?

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec, roundSeconds: Int = 30) {
        player = Fighter(spec: playerSpec, facingRight: true, position: 120)
        opponent = Fighter(spec: opponentSpec, facingRight: false, position: 280)
        roundTimer = roundSeconds * Int(CombatSystem.tickRate)
    }

    func fighter(_ side: Side) -> Fighter { side == .player ? player : opponent }

    private var distance: CGFloat { abs(player.position - opponent.position) }

    // MARK: - Public API

    /// Apply one intent for a side. Operates on a local copy and commits, so we
    /// never hold an inout borrow of `self` while mutating — keeping Swift's
    /// exclusivity checker happy.
    mutating func apply(_ intent: Intent, from side: Side) -> [CombatEvent] {
        guard !isOver else { return [] }
        var events: [CombatEvent] = []
        var f = fighter(side)

        switch intent {
        case .charge(let delta):
            if f.canAct {
                let before = f.meterFull
                f.addMeter(Int(abs(delta) * CombatSystem.chargeRate))
                if f.meterFull && !before { events.append(.specialReady(side)) }
            }

        case .beginBlock:
            if f.canAct { f.isBlocking = true }

        case .endBlock:
            f.isBlocking = false

        case .parry:
            if f.canAct { f.isBlocking = false; f.enter(.parry, ticks: CombatSystem.parryWindow) }

        case .stepForward:
            if f.canAct {
                let target = f.position + (f.facingRight ? 1 : -1) * f.spec.walkSpeed * 4
                f.position = clampLane(clampSeparation(target, side: side))
            }

        case .stepBack:
            if f.canAct {
                f.position = clampLane(f.position - (f.facingRight ? 1 : -1) * f.spec.walkSpeed * 4)
            }

        case .jump:
            break // reserved for M1 (anti-air); no-op in prototype

        case .lightAttack:
            if f.canAct { f.startMove(.light) }

        case .heavyAttack:
            if f.canAct { f.startMove(.heavy); events.append(.heavyWindup(side)) }

        case .special:
            if f.canAct && f.meter >= CombatSystem.chargeToFire {
                let move = f.meterFull ? f.spec.exSpecial : f.spec.special
                f.meter = 0
                f.startMove(move)
            }
        }

        commit(side, f)
        return events
    }

    /// Advance the simulation one fixed tick. Returns everything that happened.
    mutating func tick() -> [CombatEvent] {
        guard !isOver else { return [] }
        var events: [CombatEvent] = []

        player.advanceTimers()
        opponent.advanceTimers()

        // Resolve attacks: an `active` fighter checks reach against the other.
        events += resolveAttack(attacker: .player)
        events += resolveAttack(attacker: .opponent)

        player.regenStamina()
        opponent.regenStamina()

        // Round end conditions.
        roundTimer -= 1
        if !player.isAlive || !opponent.isAlive || roundTimer <= 0 {
            isOver = true
            winner = decideWinner()
            events.append(.roundOver(winner: winner))
        }
        return events
    }

    // MARK: - Hit resolution

    private mutating func resolveAttack(attacker side: Side) -> [CombatEvent] {
        var events: [CombatEvent] = []
        let atkSide = side
        let defSide: Side = (side == .player) ? .opponent : .player

        var atk = fighter(atkSide)
        var def = fighter(defSide)

        guard atk.state == .active, let move = atk.currentMove, !atk.hasConnectedThisMove
        else { return [] }

        guard distance <= move.reach + CombatSystem.bodyHalfWidth else { return [] }

        atk.hasConnectedThisMove = true

        // Defender parried? (Crown press / swipe-down timed into the active frames.)
        if def.state == .parry {
            // Attacker frozen in a long recovery; parrier may punish.
            atk.enter(.recovery, ticks: move.recovery + 12)
            def.enter(.idle, ticks: 0)
            commit(atkSide, atk); commit(defSide, def)
            events.append(.parried(by: defSide))
            return events
        }

        // Defender blocking?
        if def.isBlocking {
            let chip = Int(CGFloat(move.chip) * CombatSystem.blockChipScale)
            def.health = max(0, def.health - chip)
            def.stamina -= CombatSystem.staminaPerBlock
            applyPushback(&def, move.pushback, from: atk)
            atk.addMeter(move.meterGain / 2)

            if def.stamina <= 0 {
                def.isBlocking = false
                def.enter(.knockdown, ticks: 24)
                events.append(.guardBroken(defSide))
                events.append(.knockdown(defSide))
            } else {
                def.enter(.blockStun, ticks: move.blockstun)
                events.append(.blocked(defender: defSide, chip: chip))
            }
            commit(atkSide, atk); commit(defSide, def)
            return events
        }

        // Clean hit.
        def.health = max(0, def.health - move.damage)
        def.addMeter(move.meterGain)            // taking damage builds a little meter
        atk.addMeter(move.meterGain)
        applyPushback(&def, move.pushback, from: atk)
        def.enter(.hitStun, ticks: move.hitstun)
        events.append(.hitLanded(attacker: atkSide, damage: move.damage))

        if def.health <= 0 {
            def.enter(.knockdown, ticks: 30)
            events.append(.knockdown(defSide))
        }

        commit(atkSide, atk); commit(defSide, def)
        return events
    }

    // MARK: - Helpers

    private func applyPushback(_ f: inout Fighter, _ amount: CGFloat, from atk: Fighter) {
        let dir: CGFloat = atk.position < f.position ? 1 : -1
        f.position = clampLane(f.position + dir * amount)
    }

    private func clampLane(_ x: CGFloat) -> CGFloat {
        min(CombatSystem.laneMax, max(CombatSystem.laneMin, x))
    }

    /// Stop a forward-walking fighter from passing through the other.
    private func clampSeparation(_ x: CGFloat, side: Side) -> CGFloat {
        let otherPos = (side == .player ? opponent : player).position
        if side == .player {                 // faces +x: stay left of opponent
            return min(x, otherPos - CombatSystem.minSeparation)
        } else {                             // faces -x: stay right of player
            return max(x, otherPos + CombatSystem.minSeparation)
        }
    }

    private func decideWinner() -> Side? {
        if player.health == opponent.health { return nil }
        return player.health > opponent.health ? .player : .opponent
    }

    private mutating func commit(_ side: Side, _ f: Fighter) {
        if side == .player { player = f } else { opponent = f }
    }
}
