import CoreGraphics
import Foundation

private enum FightRuleSet: Equatable {
    case tournament
    case versus
    case learn

    var playerWinsToEnd: Int {
        switch self {
        case .tournament:
            return StoryChapter.allCases.count
        case .versus:
            return 1
        case .learn:
            return 99
        }
    }

    var opponentWinsToEnd: Int {
        switch self {
        case .tournament:
            return 2
        case .versus:
            return 1
        case .learn:
            return 99
        }
    }

    var advancesLadder: Bool {
        self == .tournament
    }

    var roundTimer: TimeInterval {
        switch self {
        case .tournament:
            return 60
        case .versus:
            return 75
        case .learn:
            return 90
        }
    }

    var victoryText: String {
        switch self {
        case .versus:
            return "VS WIN"
        case .learn:
            return "TRAINED"
        case .tournament:
            return "VICTORY"
        }
    }

    var defeatText: String {
        switch self {
        case .versus:
            return "VS LOSS"
        case .learn:
            return "DRILL LOST"
        case .tournament:
            return "DEFEAT"
        }
    }
}

struct WatchfighterEngine {
    private(set) var state: WatchfighterState

    private var rng: SeededRandomNumberGenerator
    private var ruleSet: FightRuleSet
    private var nextID: Int
    private var playerAttackClock: TimeInterval
    private var opponentAttackClock: TimeInterval
    private var roundPauseClock: TimeInterval
    private var opponentDecisionClock: TimeInterval
    private var opponentComboClock: TimeInterval
    private var opponentPressure: CGFloat
    private var opponentComboPlan: [FighterAction]

    init(seed: UInt64 = 0x5EED_2026) {
        self.state = WatchfighterState()
        self.rng = SeededRandomNumberGenerator(seed: seed)
        self.ruleSet = .tournament
        self.nextID = 1
        self.playerAttackClock = 0
        self.opponentAttackClock = 0.55
        self.roundPauseClock = 0
        self.opponentDecisionClock = 0
        self.opponentComboClock = 0
        self.opponentPressure = 0.5
        self.opponentComboPlan = []
    }

    mutating func reset(seed: UInt64 = UInt64(Date().timeIntervalSinceReferenceDate)) {
        state = WatchfighterState()
        rng = SeededRandomNumberGenerator(seed: seed)
        ruleSet = .tournament
        nextID = 1
        playerAttackClock = 0
        opponentAttackClock = 0.55
        roundPauseClock = 0
        opponentDecisionClock = 0
        opponentComboClock = 0
        opponentPressure = 0.5
        opponentComboPlan.removeAll()
    }

    mutating func resetVersus(player: FighterArchetype = .kael, opponent: FighterArchetype, chapter: StoryChapter, seed: UInt64 = UInt64(Date().timeIntervalSinceReferenceDate)) {
        reset(seed: seed)
        ruleSet = .versus
        state.roundTimer = ruleSet.roundTimer
        state.chapter = chapter
        state.player = DuelFighter(archetype: player, x: 0.25, facing: 1)
        state.opponent = DuelFighter(archetype: opponent, x: 0.75, facing: -1)
        state.bannerText = "VS MATCH"
        state.bannerDetail = "\(player.displayName) vs \(opponent.displayName)"
        state.bannerTimer = 2.0
    }

    mutating func resetLearn(player: FighterArchetype = .kael, opponent: FighterArchetype = .rook, seed: UInt64 = UInt64(Date().timeIntervalSinceReferenceDate)) {
        reset(seed: seed)
        ruleSet = .learn
        state.roundTimer = ruleSet.roundTimer
        state.chapter = .cinderGate
        state.player = DuelFighter(archetype: player, x: 0.25, facing: 1)
        state.player.maxHealth = 150
        state.player.health = 150
        state.player.meter = 0.60
        state.opponent = DuelFighter(archetype: opponent, x: 0.75, facing: -1)
        state.opponent.meter = 0.12
        state.bannerText = "LEARN"
        state.bannerDetail = "Spacing, guard, strike, meter"
        state.bannerTimer = 2.0
    }

    mutating func tick(delta rawDelta: TimeInterval, input: GameInput) {
        guard state.phase == .running else { return }

        let delta = min(max(rawDelta, 0), 1.0 / 10.0)
        state.elapsed += delta
        state.bannerTimer = max(0, state.bannerTimer - delta)
        state.finisherTimer = max(0, state.finisherTimer - delta)
        state.comboClock = max(0, state.comboClock - delta)
        if state.comboClock == 0 {
            state.combo = 0
            state.player.combo = 0
        }
        opponentComboClock = max(0, opponentComboClock - delta)
        if opponentComboClock == 0, opponentComboPlan.isEmpty {
            state.opponent.combo = 0
        }

        advanceTimers(delta: delta)
        advanceStrikes(delta: delta)

        guard roundPauseClock == 0 else {
            roundPauseClock = max(0, roundPauseClock - delta)
            if roundPauseClock == 0, state.phase == .running {
                startNextRound()
            }
            return
        }

        state.roundTimer = max(0, state.roundTimer - delta)
        updatePlayer(input: input, delta: delta)
        updateOpponent(delta: delta)
        updateFacing()
        resolveRoundIfNeeded()
    }

    mutating func debugSetPlayer(x: CGFloat, health: Int? = nil, guardMeter: CGFloat = 1, archetype: FighterArchetype? = nil) {
        if let archetype {
            state.player = DuelFighter(archetype: archetype, x: x.clamped(to: 0.14...0.56), facing: 1)
        }
        state.player.x = x.clamped(to: 0.14...0.56)
        if let health {
            state.player.health = health.clamped(to: 0...state.player.maxHealth)
        }
        state.player.guardMeter = guardMeter.clamped(to: 0...1)
        updateFacing()
    }

    mutating func debugSetOpponent(x: CGFloat, health: Int? = nil, guardMeter: CGFloat = 1, archetype: FighterArchetype? = nil) {
        if let archetype {
            state.opponent = DuelFighter(archetype: archetype, x: x.clamped(to: 0.44...0.88), facing: -1)
        }
        state.opponent.x = x.clamped(to: 0.44...0.88)
        if let health {
            state.opponent.health = health.clamped(to: 0...state.opponent.maxHealth)
        }
        state.opponent.guardMeter = guardMeter.clamped(to: 0...1)
        updateFacing()
    }

    mutating func debugChargeSpecial() {
        state.player.meter = 1
    }

    mutating func debugPrimeMillionShotCombo() {
        state.player.combo = 8
        state.combo = 8
        state.comboClock = 1.35
        playerAttackClock = 0
    }

    /// Test hook: set the player's live combo to an exact value so the boss
    /// invincibility rule (needs combo >= 8) can be probed at every threshold.
    mutating func debugSetPlayerCombo(_ combo: Int) {
        let value = max(0, combo)
        state.player.combo = value
        state.combo = value
        state.comboClock = value > 0 ? 1.35 : 0
        playerAttackClock = 0
    }

    /// Difficulty ramp: rivals get tougher as you climb the tower. Floor 1 sits
    /// at 1.0 (so early fights and Learn mode stay fair) and the top floors
    /// reach ~1.6 — faster reactions, relentless pressure, and harder hits. The
    /// final boss is gated by its own Million-Shot rule, so this just makes its
    /// pressure brutal rather than its damage.
    var opponentDifficulty: CGFloat {
        let floor = CGFloat(state.chapter.rawValue)            // 1...15
        let top = CGFloat(StoryChapter.allCases.count)         // 15
        guard top > 1 else { return 1.0 }
        let t = ((floor - 1) / (top - 1)).clamped(to: 0...1)   // 0...1
        return 1.0 + t * 0.60
    }

    private mutating func updatePlayer(input: GameInput, delta: TimeInterval) {
        guard state.player.hitStun == 0 else { return }

        let target = input.targetX.clamped(to: 0.14...0.56)
        let response = min(1, CGFloat(delta) * 17.5 * state.player.archetype.quickness)
        let previousX = state.player.x
        state.player.x += (target - state.player.x) * response
        state.player.x = min(state.player.x, state.opponent.x - 0.18).clamped(to: 0.14...0.56)
        let style = state.player.archetype.combatStyle
        state.player.guardMeter = min(1, state.player.guardMeter + CGFloat(delta) * (input.blocking ? 0.42 : 0.22))
        state.player.meter = min(1, state.player.meter + CGFloat(delta) * 0.055 * style.meterBuildRate)

        if input.crouching, !input.attacking, !input.special, !input.dashStrike, !input.jump, !input.throwing {
            state.player.guardMeter = min(1, state.player.guardMeter + CGFloat(delta) * 0.24)
            setAction(.crouch, for: .player, duration: 0.18)
        } else if input.blocking, !input.attacking {
            setAction(.blocking, for: .player, duration: 0.16)
        } else if abs(state.player.x - previousX) > 0.0015, state.player.action == .idle {
            setAction(.walk, for: .player, duration: 0.14)
        }

        if input.special, state.player.meter >= 1, playerAttackClock == 0 {
            performAttack(state.opponent.archetype.isMillionBoss ? .special : .projectile, by: .player)
        } else if input.throwing, playerAttackClock == 0 {
            performAttack(.throwAttack, by: .player)
        } else if input.jump, playerAttackClock == 0 {
            performAttack(.jumpKick, by: .player)
        } else if input.dashStrike, playerAttackClock == 0 {
            performDashStrike()
        } else if input.attacking, playerAttackClock == 0 {
            performAttack(state.player.combo.isMultiple(of: 2) ? .jab : .kick, by: .player)
        }
    }

    private mutating func updateOpponent(delta: TimeInterval) {
        guard state.opponent.hitStun == 0 else { return }

        let difficulty = opponentDifficulty
        opponentDecisionClock = max(0, opponentDecisionClock - delta)
        if opponentDecisionClock == 0 {
            // Higher floors keep their guard up less and pick fights more often:
            // raise the aggression floor and shorten the reaction window.
            let pressureFloor = min(0.92, 0.48 + (difficulty - 1.0) * 0.55)
            opponentPressure = CGFloat(Double.random(in: Double(pressureFloor)...1.0, using: &rng))
            opponentDecisionClock = Double.random(in: 0.16...0.42, using: &rng) / Double(difficulty)
        }

        let distance = abs(state.opponent.x - state.player.x)
        let opponentStyle = state.opponent.archetype.combatStyle
        let cornered = opponentIsCornered(distance: distance)
        let desiredSpacing: CGFloat
        switch opponentStyle {
        case .zoner:
            desiredSpacing = 0.43
        case .rushdown:
            desiredSpacing = 0.23
        case .grappler:
            desiredSpacing = 0.22
        case .acrobat:
            desiredSpacing = 0.32
        case .bruiser, .titan:
            desiredSpacing = 0.27
        case .balanced:
            desiredSpacing = 0.29
        }

        if cornered, opponentAttackClock == 0, opponentComboPlan.isEmpty, state.opponent.meter >= 0.32 {
            queueOpponentCornerEscape(distance: distance)
        }

        if opponentAttackClock == 0, let plannedAttack = popOpponentPlannedAttack(distance: distance) {
            performAttack(plannedAttack, by: .opponent)
            return
        }

        if opponentAttackClock == 0, let attack = state.opponent.archetype.preferredAttack(distance: distance, pressure: opponentPressure, meter: state.opponent.meter) {
            if attack == .blocking {
                setAction(.blocking, for: .opponent, duration: 0.18)
                opponentAttackClock = 0.16
            } else {
                performAttack(attack, by: .opponent)
            }
            return
        }

        var target = state.player.x + desiredSpacing + (1 - opponentPressure) * 0.08
        if let plannedAttack = opponentComboPlan.first {
            target = state.player.x + opponentSpacing(for: plannedAttack, style: opponentStyle)
        }
        if cornered {
            target = min(target, state.player.x + max(0.20, desiredSpacing - 0.08))
        }
        if state.player.action == .special || state.player.action == .projectile || state.player.action == .kick || state.player.action == .jumpKick {
            target += opponentComboPlan.isEmpty ? 0.04 : -0.02
            state.opponent.guardMeter = min(1, state.opponent.guardMeter + CGFloat(delta) * 0.55)
            setAction(state.player.action == .jumpKick ? .crouch : .blocking, for: .opponent, duration: 0.16)
        }

        let response = min(1, CGFloat(delta) * (8.4 + opponentPressure * 5.6) * state.opponent.archetype.quickness * difficulty)
        let previousX = state.opponent.x
        state.opponent.x += (target.clamped(to: 0.44...0.88) - state.opponent.x) * response
        state.opponent.x = max(state.opponent.x, state.player.x + 0.18).clamped(to: 0.44...0.88)
        state.opponent.guardMeter = min(1, state.opponent.guardMeter + CGFloat(delta) * 0.25)
        state.opponent.meter = min(1, state.opponent.meter + CGFloat(delta) * 0.075 * opponentStyle.meterBuildRate)

        if abs(state.opponent.x - previousX) > 0.0015, state.opponent.action == .idle {
            setAction(.walk, for: .opponent, duration: 0.14)
        }
    }

    private mutating func performDashStrike() {
        let dashReach: CGFloat = 0.13
        let targetDistance: CGFloat = 0.22
        let distance = state.opponent.x - state.player.x
        let dash = min(dashReach, max(0, distance - targetDistance))
        state.player.x = min(state.player.x + dash, state.opponent.x - 0.18).clamped(to: 0.14...0.56)
        updateFacing()
        performAttack(.kick, by: .player)
    }

    private mutating func performAttack(_ action: FighterAction, by side: FighterSide) {
        let attacker = side == .player ? state.player : state.opponent
        let defender = side == .player ? state.opponent : state.player
        let style = attacker.archetype.combatStyle

        var range: CGFloat
        var baseDamage: Int
        let windup: TimeInterval
        switch action {
        case .jab:
            range = 0.225
            baseDamage = 7
            windup = 0.18
        case .kick:
            range = 0.285
            baseDamage = 11
            windup = 0.26
        case .jumpKick:
            range = 0.315
            baseDamage = 13
            windup = 0.34
        case .throwAttack:
            range = 0.195
            baseDamage = 16
            windup = 0.30
        case .projectile:
            range = 0.62
            baseDamage = 15
            windup = 0.40
        case .special:
            range = 0.42
            baseDamage = 20
            windup = 0.36
        default:
            return
        }
        range *= style.rangeMultiplier(for: action)
        baseDamage = max(1, Int((CGFloat(baseDamage) * style.damageMultiplier(for: action)).rounded()))

        setAction(action, for: side, duration: windup)
        if side == .player {
            playerAttackClock = playerCooldown(for: action) * style.cooldownMultiplier(for: action)
        } else {
            // Tougher floors recover faster between strikes, so the AI keeps the
            // pressure on instead of giving the player room to breathe.
            opponentAttackClock = opponentCooldown(for: action) * style.cooldownMultiplier(for: action) / opponentDifficulty
        }

        if action == .special || action == .projectile {
            if side == .player {
                state.player.meter = 0
            } else {
                state.opponent.meter = 0
            }
        }

        let connected = abs(attacker.x - defender.x) <= range
        let impactX = (attacker.x + defender.x) * 0.5
        guard connected else {
            addStrike(side: side, x: impactX, y: 0.56, kind: .blocked, lifetime: 0.18)
            return
        }

        let defenderGuarding = action != .throwAttack && (defender.action == .blocking || defender.action == .crouch) && defender.guardMeter > 0.22
        let millionCounter = side == .player && defender.archetype.isMillionBoss && action == .special && state.combo >= 8
        var rawDamage = Int((CGFloat(baseDamage) * attacker.archetype.power).rounded())
        if side == .opponent {
            // Rivals hit harder the higher you climb the tower.
            rawDamage = max(1, Int((CGFloat(rawDamage) * opponentDifficulty).rounded()))
        }
        if defender.archetype.isMillionBoss, side == .player {
            rawDamage = millionCounter ? max(rawDamage, defender.maxHealth) : max(1, Int((CGFloat(rawDamage) * 0.04).rounded()))
        }
        let damage = defenderGuarding ? max(2, Int(CGFloat(rawDamage) * 0.32)) : rawDamage
        let hitStun = defenderGuarding ? 0.08 : (action == .special ? 0.28 : 0.16)

        if side == .player {
            state.opponent.health = max(0, state.opponent.health - damage)
            state.opponent.hitStun = hitStun
            state.opponent.guardMeter = defenderGuarding ? max(0, state.opponent.guardMeter - 0.34 * style.guardPressure) : max(0, state.opponent.guardMeter - 0.18 * style.guardPressure)
            setAction(defenderGuarding ? .blocking : .hit, for: .opponent, duration: hitStun)
            awardPlayerHit(damage: damage, action: action, blocked: defenderGuarding)
            if state.opponent.health > 0 {
                state.opponent.meter = min(1, state.opponent.meter + CGFloat(damage) / (defenderGuarding ? 260 : 145))
                queueOpponentCounter(blocked: defenderGuarding, distance: abs(state.opponent.x - state.player.x))
            }
            if action == .throwAttack, !defenderGuarding {
                state.opponent.x = min(0.88, state.opponent.x + state.player.facing * style.throwPush)
            }
        } else {
            state.player.health = max(0, state.player.health - damage)
            state.player.hitStun = hitStun
            state.player.guardMeter = defenderGuarding ? max(0, state.player.guardMeter - 0.34 * style.guardPressure) : max(0, state.player.guardMeter - 0.18 * style.guardPressure)
            setAction(defenderGuarding ? .blocking : .hit, for: .player, duration: hitStun)
            state.opponent.combo += defenderGuarding ? 0 : 1
            if !defenderGuarding {
                opponentComboClock = 1.25
            }
            state.opponent.meter = min(1, state.opponent.meter + CGFloat(damage) / 120 * style.meterBuildRate)
            queueOpponentFollowUp(after: action, connected: !defenderGuarding, distance: abs(state.opponent.x - state.player.x))
            if action == .throwAttack, !defenderGuarding {
                state.player.x = max(0.14, state.player.x + state.opponent.facing * style.throwPush)
            }
        }

        let strikeKind: StrikeKind
        if action == .special {
            strikeKind = .special
        } else if action == .projectile {
            strikeKind = .projectile
        } else if action == .throwAttack {
            strikeKind = .throwImpact
        } else {
            strikeKind = defenderGuarding ? .blocked : .hit
        }
        let impactY: CGFloat = action == .kick || action == .jumpKick ? 0.62 : (action == .throwAttack ? 0.68 : 0.53)
        addStrike(side: side, x: impactX, y: impactY, kind: strikeKind, lifetime: action == .special || action == .projectile ? 0.38 : 0.25)
        if !defenderGuarding {
            addStrike(side: side, x: impactX + attacker.facing * 0.02, y: 0.50, kind: .blood, lifetime: 0.34)
        }
        if defender.archetype.isMillionBoss, side == .player, action == .special {
            showBanner(
                millionCounter ? "MILLION SHOT" : "TITUS SHRUGS",
                millionCounter ? "the impossible counter lands" : "8-hit chain plus full meter",
                duration: 1.0
            )
        } else if side == .opponent, (action == .special || action == .projectile) {
            showBanner(attacker.archetype.signatureMove, "counter pressure", duration: 0.92)
        }
    }

    private mutating func popOpponentPlannedAttack(distance: CGFloat) -> FighterAction? {
        guard let action = opponentComboPlan.first else { return nil }
        guard opponentCanReach(action, distance: distance) else { return nil }
        opponentComboPlan.removeFirst()
        return action
    }

    private func opponentCanReach(_ action: FighterAction, distance: CGFloat) -> Bool {
        let reach = opponentReach(for: action, style: state.opponent.archetype.combatStyle)
        return distance <= reach
    }

    private func opponentReach(for action: FighterAction, style: CombatStyle) -> CGFloat {
        let base: CGFloat
        switch action {
        case .jab:
            base = 0.225
        case .kick:
            base = 0.285
        case .jumpKick:
            base = 0.315
        case .throwAttack:
            base = 0.195
        case .projectile:
            base = 0.62
        case .special:
            base = 0.42
        default:
            base = 0
        }
        return base * style.rangeMultiplier(for: action)
    }

    private func opponentSpacing(for action: FighterAction, style: CombatStyle) -> CGFloat {
        switch action {
        case .throwAttack:
            return min(0.21, opponentReach(for: action, style: style) * 0.90)
        case .jab:
            return min(0.24, opponentReach(for: action, style: style) * 0.92)
        case .kick, .jumpKick:
            return min(0.30, opponentReach(for: action, style: style) * 0.90)
        case .special:
            return min(0.38, opponentReach(for: action, style: style) * 0.88)
        case .projectile:
            return min(0.48, opponentReach(for: action, style: style) * 0.86)
        default:
            return 0.29
        }
    }

    private func opponentIsCornered(distance: CGFloat) -> Bool {
        state.opponent.x >= 0.82 && distance <= 0.42
    }

    private mutating func queueOpponentCounter(blocked: Bool, distance: CGFloat) {
        guard state.phase == .running, state.opponent.health > 0 else { return }
        let cornered = opponentIsCornered(distance: distance)
        let sequence = cornered ? opponentCornerEscapeSequence(distance: distance) : opponentCounterSequence(blocked: blocked, distance: distance)
        guard !sequence.isEmpty else { return }
        opponentComboPlan = sequence + Array(opponentComboPlan.prefix(1))
        opponentPressure = max(opponentPressure, cornered ? 1.0 : (blocked ? 0.84 : 0.72))
        opponentDecisionClock = min(opponentDecisionClock, cornered ? 0.06 : 0.12)
        opponentAttackClock = min(opponentAttackClock, cornered ? 0.10 : 0.18)
        opponentComboClock = 1.35
    }

    private mutating func queueOpponentCornerEscape(distance: CGFloat) {
        let sequence = opponentCornerEscapeSequence(distance: distance)
        guard !sequence.isEmpty else { return }
        opponentComboPlan = sequence
        opponentPressure = 1
        opponentDecisionClock = 0.06
    }

    private func opponentCounterSequence(blocked: Bool, distance: CGFloat) -> [FighterAction] {
        switch state.opponent.archetype.combatStyle {
        case .rushdown:
            return blocked ? [.jab, .kick] : [.kick, .jab]
        case .grappler:
            return distance < 0.25 ? [.throwAttack, .kick] : [.kick, .throwAttack]
        case .zoner:
            return [.projectile, .kick]
        case .acrobat:
            return [.jumpKick, .jab]
        case .bruiser:
            return state.opponent.meter >= 0.75 ? [.special, .kick] : [.kick, .jab]
        case .titan:
            return state.opponent.meter >= 0.55 ? [.special, .jab] : [.jab, .kick]
        case .balanced:
            return blocked ? [.throwAttack, .jab] : [.jab, .kick]
        }
    }

    private func opponentCornerEscapeSequence(distance: CGFloat) -> [FighterAction] {
        switch state.opponent.archetype.combatStyle {
        case .zoner, .titan:
            return [.projectile, .kick]
        case .grappler:
            return distance < 0.24 ? [.throwAttack, .special] : [.special, .throwAttack]
        case .acrobat:
            return [.jumpKick, .special]
        case .rushdown:
            return [.special, .kick]
        case .bruiser:
            return [.special, .throwAttack]
        case .balanced:
            return [.special, .jab]
        }
    }

    private mutating func queueOpponentFollowUp(after action: FighterAction, connected: Bool, distance: CGFloat) {
        guard connected, state.player.health > 0, state.opponent.combo < 4, opponentComboPlan.isEmpty else { return }
        let sequence: [FighterAction]
        switch (state.opponent.archetype.combatStyle, action) {
        case (.rushdown, .jab):
            sequence = [.kick]
        case (.rushdown, .kick):
            sequence = [.jab]
        case (.grappler, .throwAttack):
            sequence = [.kick]
        case (.grappler, _):
            sequence = distance < 0.25 ? [.throwAttack] : [.kick]
        case (.zoner, .projectile):
            sequence = [.kick]
        case (.acrobat, .jumpKick):
            sequence = [.jab]
        case (.bruiser, .kick), (.titan, .jab):
            sequence = state.opponent.meter >= 0.55 ? [.special] : [.kick]
        case (.balanced, .jab):
            sequence = [.kick]
        default:
            sequence = state.opponent.combo < 2 ? [.jab] : []
        }
        opponentComboPlan.append(contentsOf: sequence)
        if !sequence.isEmpty {
            opponentAttackClock = min(opponentAttackClock, 0.15)
            opponentDecisionClock = min(opponentDecisionClock, 0.10)
            opponentPressure = max(opponentPressure, 0.76)
            opponentComboClock = 1.20
        }
    }

    private mutating func awardPlayerHit(damage: Int, action: FighterAction, blocked: Bool) {
        if !blocked {
            state.combo += 1
            state.player.combo += 1
            state.maxCombo = max(state.maxCombo, state.combo)
            state.comboClock = 1.35
        }

        let actionBonus: Int
        switch action {
        case .jab:
            actionBonus = 12
        case .kick:
            actionBonus = 22
        case .jumpKick:
            actionBonus = 30
        case .throwAttack:
            actionBonus = 40
        case .projectile:
            actionBonus = 48
        case .special:
            actionBonus = 65
        default:
            actionBonus = 0
        }

        let comboBonus = state.combo > 1 ? min(160, state.combo * 10) : 0
        let blockPenalty = blocked ? 8 : 0
        state.score += max(1, damage * 8 + actionBonus + comboBonus - blockPenalty)
        if action != .special && action != .projectile {
            state.player.meter = min(1, state.player.meter + CGFloat(damage) / (blocked ? 180 : 95) * state.player.archetype.combatStyle.meterBuildRate)
        }

        if action == .special || action == .projectile {
            showBanner(action == .projectile ? state.player.archetype.signatureMove : "BONEBREAK", "+\(actionBonus) power strike", duration: 0.95)
        } else if action == .throwAttack {
            showBanner("THROW", "+\(actionBonus) close control", duration: 0.72)
        } else if state.combo == 3 || state.combo == 5 || state.combo == 8 {
            showBanner("\(state.combo) HIT COMBO", "+\(comboBonus) fury", duration: 0.88)
        }
    }

    private func playerCooldown(for action: FighterAction) -> TimeInterval {
        switch action {
        case .jab:
            return 0.19
        case .kick:
            return 0.30
        case .jumpKick:
            return 0.42
        case .throwAttack:
            return 0.40
        case .projectile, .special:
            return 0.58
        default:
            return 0.30
        }
    }

    private func opponentCooldown(for action: FighterAction) -> TimeInterval {
        switch action {
        case .jab:
            return 0.34
        case .kick:
            return 0.54
        case .jumpKick:
            return 0.62
        case .throwAttack:
            return 0.58
        case .projectile, .special:
            return 0.82
        default:
            return 0.52
        }
    }

    private mutating func resolveRoundIfNeeded() {
        guard state.player.health <= 0 || state.opponent.health <= 0 || state.roundTimer == 0 else { return }

        let playerWon: Bool
        if state.player.health == state.opponent.health {
            playerWon = state.score >= 0
        } else {
            playerWon = state.player.health > state.opponent.health
        }

        let winner = playerWon ? state.player.archetype : state.opponent.archetype
        let loser = playerWon ? state.opponent : state.player

        if playerWon {
            state.playerWins += 1
            state.score += 500 + Int(state.roundTimer.rounded()) * 4
            state.player.action = .victory
            state.opponent.action = .defeated
            if state.opponent.archetype.isMillionBoss {
                showBanner("MILLION SHOT", "the impossible counter ends Titus", duration: 2.0)
            } else {
                showBanner(winner.finisherTitle, "\(winner.displayName) ends round \(state.round)", duration: 2.0)
            }
        } else {
            state.opponentWins += 1
            state.player.action = .defeated
            state.opponent.action = .victory
            showBanner(winner.finisherTitle, "\(state.opponent.archetype.displayName) takes round \(state.round)", duration: 2.0)
        }

        state.finisherText = winner.finisherTitle
        state.finisherTimer = 1.55
        addStrike(side: playerWon ? .player : .opponent, x: loser.x, y: 0.50, kind: winner.finisherKind, lifetime: 1.15)
        addStrike(side: playerWon ? .player : .opponent, x: 0.5, y: 0.48, kind: .finisher, lifetime: 0.80)
        roundPauseClock = 2.25

        if state.playerWins >= ruleSet.playerWinsToEnd || state.opponentWins >= ruleSet.opponentWinsToEnd {
            state.phase = .gameOver
            state.winnerText = state.playerWins >= ruleSet.playerWinsToEnd ? ruleSet.victoryText : ruleSet.defeatText
            state.bannerTimer = 0
        }
    }

    private mutating func startNextRound() {
        guard state.phase == .running else { return }
        let playerArchetype = state.player.archetype
        let previousOpponent = state.opponent.archetype

        state.round += 1
        if ruleSet.advancesLadder {
            state.chapter = StoryChapter.chapter(for: state.playerWins + 1)
        }
        state.roundTimer = ruleSet.roundTimer
        state.combo = 0
        state.comboClock = 0
        state.finisherText = ""
        state.finisherTimer = 0
        state.player = DuelFighter(archetype: playerArchetype, x: 0.25, facing: 1)
        state.opponent = DuelFighter(archetype: ruleSet.advancesLadder ? opponent(for: state.chapter) : previousOpponent, x: 0.75, facing: -1)
        if ruleSet == .learn {
            state.player.maxHealth = 150
            state.player.health = 150
            state.player.meter = 0.60
            state.opponent.meter = 0.12
        }
        state.strikes.removeAll()
        playerAttackClock = 0
        opponentAttackClock = 0.55
        opponentDecisionClock = 0
        opponentComboClock = 0
        opponentComboPlan.removeAll()
        let bannerText = ruleSet == .learn ? "DRILL \(state.round)" : "ROUND \(state.round)"
        showBanner(bannerText, "\(state.opponent.archetype.displayName): \(state.opponent.archetype.techniqueName)", duration: 1.8)
    }

    private func opponent(for chapter: StoryChapter) -> FighterArchetype {
        switch chapter {
        case .cinderGate:
            return .nyra
        case .neonRooftop:
            return .rook
        case .stormBridge:
            return .voss
        case .pirateCove:
            return .mara
        case .dragonAlley:
            return .lennox
        case .sunPier:
            return .sunny
        case .runwayTerminal:
            return .nova
        case .blackoutBase:
            return .specter
        case .launchFoundry:
            return .cosmo
        case .goldRally:
            return .brass
        case .icePalace:
            return .volkov
        case .redCarpet:
            return .zara
        case .cageNight:
            return .cage
        case .obsidianThrone:
            return .kairo
        case .millionRoom:
            return .titan
        }
    }

    private mutating func advanceTimers(delta: TimeInterval) {
        playerAttackClock = max(0, playerAttackClock - delta)
        opponentAttackClock = max(0, opponentAttackClock - delta)
        state.player.actionTimer = max(0, state.player.actionTimer - delta)
        state.opponent.actionTimer = max(0, state.opponent.actionTimer - delta)
        state.player.hitStun = max(0, state.player.hitStun - delta)
        state.opponent.hitStun = max(0, state.opponent.hitStun - delta)

        if state.player.actionTimer == 0, state.player.action != .victory, state.player.action != .defeated {
            state.player.action = .idle
        }
        if state.opponent.actionTimer == 0, state.opponent.action != .victory, state.opponent.action != .defeated {
            state.opponent.action = .idle
        }
    }

    private mutating func advanceStrikes(delta: TimeInterval) {
        for index in state.strikes.indices {
            state.strikes[index].age += delta
        }
        state.strikes.removeAll { $0.age >= $0.lifetime }
    }

    private mutating func updateFacing() {
        state.player.facing = state.player.x <= state.opponent.x ? 1 : -1
        state.opponent.facing = state.opponent.x <= state.player.x ? 1 : -1
    }

    private mutating func setAction(_ action: FighterAction, for side: FighterSide, duration: TimeInterval) {
        switch side {
        case .player:
            state.player.action = action
            let t = max(state.player.actionTimer, duration)
            state.player.actionTimer = t
            state.player.actionDuration = max(0.001, t)
        case .opponent:
            state.opponent.action = action
            let t = max(state.opponent.actionTimer, duration)
            state.opponent.actionTimer = t
            state.opponent.actionDuration = max(0.001, t)
        }
    }

    private mutating func addStrike(side: FighterSide, x: CGFloat, y: CGFloat, kind: StrikeKind, lifetime: TimeInterval) {
        state.strikes.append(FighterStrike(
            id: makeID(),
            side: side,
            x: x,
            y: y,
            age: 0,
            lifetime: lifetime,
            kind: kind
        ))
    }

    private mutating func showBanner(_ text: String, _ detail: String, duration: TimeInterval) {
        state.bannerText = text
        state.bannerDetail = detail
        state.bannerTimer = duration
    }

    private mutating func makeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xA11CE_5EED : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
