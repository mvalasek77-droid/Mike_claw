import CoreGraphics

/// A travelling projectile (fireball archetype) spawned by a projectile special.
struct Projectile: Equatable {
    var position: CGFloat
    let velocity: CGFloat       // signed points per tick
    let owner: Side
    let damage: Int
    let chip: Int
    let hitstun: Int
    var alive = true
}

/// The pure simulation core. Holds two fighters + projectiles, consumes
/// `Intent`s, advances the fight one fixed tick at a time, and emits
/// `CombatEvent`s for the presentation layer (rendering + haptics).
///
/// Deliberately free of SpriteKit / SwiftUI so it can be unit-tested headless.
struct CombatSystem {

    // MARK: Tunables
    static let tickRate: Double = 60
    static let laneMin: CGFloat = 20
    static let laneMax: CGFloat = 380
    static let bodyHalfWidth: CGFloat = 18
    static let minSeparation: CGFloat = 30
    static let parryWindow = 6
    static let chargeToFire: Int = 50
    static let chargeRate: CGFloat = 140
    static let blockChipScale: CGFloat = 1.0
    static let staminaPerBlock: CGFloat = 9
    static let staminaRegen: CGFloat = 0.4
    static let launchHitstun = 34

    // MARK: State
    private(set) var player: Fighter
    private(set) var opponent: Fighter
    private(set) var projectiles: [Projectile] = []
    private(set) var roundTimer: Int
    private(set) var isOver = false
    private(set) var winner: Side?

    private let roundTicks: Int

    init(playerSpec: CharacterSpec, opponentSpec: CharacterSpec, roundSeconds: Int = 30) {
        player = Fighter(spec: playerSpec, facingRight: true, position: 120)
        opponent = Fighter(spec: opponentSpec, facingRight: false, position: 280)
        roundTicks = roundSeconds * Int(CombatSystem.tickRate)
        roundTimer = roundTicks
    }

    func fighter(_ side: Side) -> Fighter { side == .player ? player : opponent }

    private var distance: CGFloat { abs(player.position - opponent.position) }

    /// Reset both fighters + projectiles for a fresh round in the same match.
    mutating func resetForNewRound() {
        player.resetForRound(position: 120)
        opponent.resetForRound(position: 280)
        projectiles.removeAll()
        roundTimer = roundTicks
        isOver = false
        winner = nil
    }

    // MARK: - Move-chain ranking (combo cancels: light -> heavy -> special)

    private func rank(_ kind: MoveKind) -> Int {
        switch kind { case .light: return 0; case .heavy: return 1; case .special, .ex: return 2 }
    }

    /// May `side` start `move` right now — from neutral, or as a valid cancel?
    private func canPerform(_ move: Move, _ f: Fighter) -> Bool {
        if f.state == .idle { return true }
        guard f.canCancel, let cur = f.currentMove else { return false }
        return rank(move.kind) > rank(cur.kind)     // only cancel "upward"
    }

    // MARK: - Public API

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
            break

        case .lightAttack:
            if canPerform(.light, f) { f.startMove(.light) }

        case .heavyAttack:
            if canPerform(.heavy, f) { f.startMove(.heavy); events.append(.heavyWindup(side)) }

        case .special:
            if f.meter >= CombatSystem.chargeToFire {
                let move = f.meterFull ? f.spec.exSpecial : f.spec.special
                if canPerform(move, f) {
                    f.meter = 0
                    f.startMove(move)
                }
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

        events += resolveAttack(attacker: .player)
        events += resolveAttack(attacker: .opponent)
        events += updateProjectiles()

        player.regenStamina()
        opponent.regenStamina()

        roundTimer -= 1
        if !player.isAlive || !opponent.isAlive || roundTimer <= 0 {
            isOver = true
            winner = decideWinner()
            events.append(.roundOver(winner: winner))
        }
        return events
    }

    // MARK: - Melee resolution

    private mutating func resolveAttack(attacker side: Side) -> [CombatEvent] {
        var events: [CombatEvent] = []
        let atkSide = side
        let defSide: Side = (side == .player) ? .opponent : .player

        var atk = fighter(atkSide)
        var def = fighter(defSide)

        guard atk.state == .active, let move = atk.currentMove, !atk.hasConnectedThisMove
        else { return [] }

        // Projectile specials spawn a travelling hitbox instead of melee.
        if move.isProjectile {
            atk.hasConnectedThisMove = true
            let dir: CGFloat = atk.facingRight ? 1 : -1
            projectiles.append(Projectile(
                position: atk.position + dir * (CombatSystem.bodyHalfWidth + 6),
                velocity: dir * move.projectileSpeed,
                owner: atkSide, damage: move.damage, chip: move.chip,
                hitstun: move.hitstun))
            commit(atkSide, atk)
            return events
        }

        guard distance <= move.reach + CombatSystem.bodyHalfWidth else { return [] }
        atk.hasConnectedThisMove = true

        let outcome = applyHit(move: move, from: &atk, to: &def, atkSide: atkSide, defSide: defSide)
        events += outcome
        commit(atkSide, atk); commit(defSide, def)
        return events
    }

    /// Shared hit resolution for melee + projectiles. Mutates atk/def in place.
    private func applyHit(move: Move, from atk: inout Fighter, to def: inout Fighter,
                          atkSide: Side, defSide: Side) -> [CombatEvent] {
        var events: [CombatEvent] = []

        // Parry (melee only — projectiles ignore the parry window for clarity).
        if def.state == .parry && !move.isProjectile {
            atk.enter(.recovery, ticks: move.recovery + 12)
            def.enter(.idle, ticks: 0)
            events.append(.parried(by: defSide))
            return events
        }

        // Block.
        if def.isBlocking {
            let chip = Int(CGFloat(move.chip) * CombatSystem.blockChipScale)
            def.health = max(0, def.health - chip)
            def.stamina -= CombatSystem.staminaPerBlock
            applyPushback(&def, move.pushback, from: atk)
            atk.addMeter(move.meterGain / 2)
            def.comboCount = 0
            if def.stamina <= 0 {
                def.isBlocking = false
                def.enter(.knockdown, ticks: 24)
                events.append(.guardBroken(defSide)); events.append(.knockdown(defSide))
            } else {
                def.enter(.blockStun, ticks: move.blockstun)
                events.append(.blocked(defender: defSide, chip: chip))
            }
            return events
        }

        // Clean hit.
        def.health = max(0, def.health - move.damage)
        def.addMeter(move.meterGain)
        atk.addMeter(move.meterGain)
        applyPushback(&def, move.pushback, from: atk)
        def.comboCount += 1
        if move.cancelable { atk.canCancel = true }   // open the combo window

        if move.launches {
            def.enter(.launched, ticks: CombatSystem.launchHitstun)
        } else {
            def.enter(.hitStun, ticks: move.hitstun)
        }
        events.append(.hitLanded(attacker: atkSide, damage: move.damage))
        if def.comboCount >= 2 { events.append(.comboHit(by: atkSide, count: def.comboCount)) }

        if def.health <= 0 {
            def.enter(.knockdown, ticks: 30)
            events.append(.knockdown(defSide))
        }
        return events
    }

    // MARK: - Projectiles

    private mutating func updateProjectiles() -> [CombatEvent] {
        var events: [CombatEvent] = []
        guard !projectiles.isEmpty else { return [] }

        for i in projectiles.indices {
            guard projectiles[i].alive else { continue }
            projectiles[i].position += projectiles[i].velocity

            if projectiles[i].position < CombatSystem.laneMin
                || projectiles[i].position > CombatSystem.laneMax {
                projectiles[i].alive = false
                continue
            }

            let targetSide: Side = projectiles[i].owner == .player ? .opponent : .player
            var target = fighter(targetSide)
            if abs(projectiles[i].position - target.position) <= CombatSystem.bodyHalfWidth {
                // Reuse melee resolution via a synthetic projectile "move".
                let p = projectiles[i]
                var dummyAtk = fighter(p.owner)
                let move = Move(kind: .special, startup: 0, active: 1, recovery: 0,
                                damage: p.damage, chip: p.chip, hitstun: p.hitstun,
                                blockstun: 10, pushback: 10, reach: 0, meterGain: 0,
                                isProjectile: true)
                events += applyHit(move: move, from: &dummyAtk, to: &target,
                                   atkSide: p.owner, defSide: targetSide)
                commit(targetSide, target)
                projectiles[i].alive = false
            }
        }
        projectiles.removeAll { !$0.alive }
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

    private func clampSeparation(_ x: CGFloat, side: Side) -> CGFloat {
        let otherPos = (side == .player ? opponent : player).position
        return side == .player ? min(x, otherPos - CombatSystem.minSeparation)
                               : max(x, otherPos + CombatSystem.minSeparation)
    }

    private func decideWinner() -> Side? {
        if player.health == opponent.health { return nil }
        return player.health > opponent.health ? .player : .opponent
    }

    private mutating func commit(_ side: Side, _ f: Fighter) {
        if side == .player { player = f } else { opponent = f }
    }
}
