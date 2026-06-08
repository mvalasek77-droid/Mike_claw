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
    // Aerial game
    static let gravity: CGFloat = 0.85
    static let jumpVelocity: CGFloat = 11
    static let jumpDrift: CGFloat = 1.6      // forward/back horizontal speed in air
    // Stun / dizzy
    static let stunThreshold: CGFloat = 100
    static let stunDecay: CGFloat = 0.5
    static let dizzyTicks = 70
    // Combo damage scaling — successive hits in a combo do less (classic juggle).
    static let scaling: [CGFloat] = [1.0, 1.0, 0.8, 0.65, 0.5, 0.4, 0.3]
    static let minScale: CGFloat = 0.25
    // Throws
    static let throwTechWindow = 4           // ticks both grabs count as a tech

    // MARK: State
    private(set) var player: Fighter
    private(set) var opponent: Fighter
    private(set) var projectiles: [Projectile] = []
    private(set) var roundTimer: Int
    private(set) var isOver = false
    private(set) var winner: Side?

    /// Set once the player completes the secret ritual; a ritual-guarded boss
    /// becomes mortal. Persists across rounds within the same match.
    private(set) var ritualBroken = false

    private(set) var tickCount = 0
    private var grabTick: [Side: Int] = [.player: -100, .opponent: -100]

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
            if f.canAct {
                let other = (side == .player ? opponent : player).position
                let dir: CGFloat = other > f.position ? 1 : -1
                f.jump(CombatSystem.jumpVelocity, drift: dir * CombatSystem.jumpDrift)
            }

        case .grab:
            if f.canAct {
                grabTick[side] = tickCount
                f.startMove(.throwMove)
            }

        case .lightAttack:
            if f.airborne {
                if f.canAirAct { f.startMove(.airLight); f.airActionUsed = true }
            } else if canPerform(.light, f) { f.startMove(.light) }

        case .heavyAttack:
            if f.airborne {
                if f.canAirAct { f.startMove(.airHeavy); f.airActionUsed = true }
            } else if canPerform(.heavy, f) { f.startMove(.heavy); events.append(.heavyWindup(side)) }

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
        tickCount += 1

        player.advanceTimers()
        opponent.advanceTimers()
        _ = player.applyGravity(gravity: CombatSystem.gravity)
        _ = opponent.applyGravity(gravity: CombatSystem.gravity)

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

        // 2D box check: the attacker's vertical hitbox must overlap the
        // defender's hurtbox. This is what makes jump-ins, anti-airs, and
        // whiffing-under-a-jump work (grounded normals span the full body, so
        // grounded-vs-grounded is unchanged).
        let atkLo = atk.height + move.loY, atkHi = atk.height + move.hiY
        guard atkLo <= def.hurtTop && atkHi >= def.height else { return [] }

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

        // Throws: beat block, can't grab an airborne or downed foe, ignore armor
        // and parry. Two simultaneous grabs tech out.
        if move.isThrow {
            if def.airborne || def.state == .knockdown || def.state == .wakeup
                || (def.spec.guardedByRitual && !ritualBroken) { return [] }
            if tickCount - (grabTick[defSide] ?? -100) <= CombatSystem.throwTechWindow {
                applyPushback(&def, 18, from: atk); applyPushback(&atk, 18, from: def)
                atk.enter(.recovery, ticks: 8); def.enter(.recovery, ticks: 8)
                events.append(.throwTeched)
                return events
            }
            def.isBlocking = false
            def.health = max(0, def.health - move.damage)
            atk.addMeter(move.meterGain)
            applyPushback(&def, move.pushback, from: atk)
            def.comboCount = 0; def.comboScalingHits = 0
            def.enter(.knockdown, ticks: 30)
            events.append(.thrown(defSide))
            if def.health <= 0 { events.append(.knockdown(defSide)) }
            return events
        }

        // Parry (melee only — projectiles ignore the parry window for clarity).
        if def.state == .parry && !move.isProjectile {
            atk.enter(.recovery, ticks: move.recovery + 12)
            def.enter(.idle, ticks: 0)
            events.append(.parried(by: defSide))
            return events
        }

        // Armor: a defender winding up an armored move powers through one hit —
        // takes reduced "chip" damage but no hitstun, and keeps attacking. This
        // is what makes the boss's haymaker terrifying; only a parry stops it.
        if def.state == .startup, def.armorAvailable, def.currentMove?.armor == true {
            def.armorAvailable = false
            def.health = max(0, def.health - move.chip)
            atk.addMeter(move.meterGain)
            events.append(.armorAbsorbed(defSide))
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

        // Ritual guard: an undefeated boss is INVINCIBLE until the secret
        // process is performed. Hits connect for feel but deal zero damage, so
        // the boss cannot be beaten on damage — run out the clock and he wins.
        if def.spec.guardedByRitual && !ritualBroken {
            def.comboCount = 0
            applyPushback(&def, move.pushback * 0.25, from: atk)
            def.enter(.hitStun, ticks: 4)
            atk.addMeter(move.meterGain)
            events.append(.invulnerable(defSide))
            return events
        }

        // Clean hit — apply combo damage scaling so long juggles taper off.
        let scaleIdx = min(def.comboScalingHits, CombatSystem.scaling.count - 1)
        let factor = move.scaling ? max(CombatSystem.minScale, CombatSystem.scaling[scaleIdx]) : 1
        let dealt = max(1, Int(CGFloat(move.damage) * factor))
        def.health = max(0, def.health - dealt)
        def.addMeter(move.meterGain)
        atk.addMeter(move.meterGain)
        applyPushback(&def, move.pushback, from: atk)
        def.comboCount += 1
        if move.scaling { def.comboScalingHits += 1 }
        if move.cancelable { atk.canCancel = true }   // open the combo window

        // Stun accrues toward a dizzy (a free-punish stagger).
        def.stun += CGFloat(move.damage) * 1.6
        let willDizzy = def.stun >= CombatSystem.stunThreshold && !move.launches

        if willDizzy {
            def.stun = 0
            def.enter(.dizzy, ticks: CombatSystem.dizzyTicks)
            events.append(.dizzy(defSide))
        } else if move.launches {
            def.enter(.launched, ticks: CombatSystem.launchHitstun)
        } else {
            def.enter(.hitStun, ticks: move.hitstun)
        }
        events.append(.hitLanded(attacker: atkSide, damage: dealt))
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

    /// Called when the player completes the secret ritual — the boss can now
    /// be damaged. Stays broken for the rest of the match.
    mutating func breakRitualGuard() { ritualBroken = true }

    // MARK: - Training hooks (do not use in normal matches)

    mutating func debugSetHealth(_ side: Side, _ value: Int) {
        var f = fighter(side); f.health = max(0, min(f.spec.maxHealth, value)); commit(side, f)
    }
    mutating func debugSetMeter(_ side: Side, _ value: Int) {
        var f = fighter(side); f.meter = max(0, min(100, value)); commit(side, f)
    }
}
