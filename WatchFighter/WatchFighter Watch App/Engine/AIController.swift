import CoreGraphics

/// A lightweight, deterministic-ish CPU opponent. Reads the public combat
/// state each tick and returns at most one `Intent`. Difficulty scales
/// reaction probability and how often it charges/parries.
struct AIController {
    enum Difficulty { case easy, normal, hard, boss
        var aggression: Double {
            switch self { case .boss: return 0.7; case .hard: return 0.55
                          case .normal: return 0.4; case .easy: return 0.25 }
        }
        var parryChance: Double {
            switch self { case .boss: return 0.6; case .hard: return 0.45
                          case .normal: return 0.2; case .easy: return 0.05 }
        }
        var reaction: Int { // ticks
            switch self { case .boss: return 4; case .hard: return 6
                          case .normal: return 12; case .easy: return 20 }
        }
        var label: String {
            switch self { case .boss: return "Boss"; case .hard: return "Hard"
                          case .normal: return "Normal"; case .easy: return "Easy" }
        }
        /// Player-selectable difficulties (boss tier is reserved for the boss).
        static let selectable: [Difficulty] = [.easy, .normal, .hard]
        var nextSelectable: Difficulty {
            let i = Difficulty.selectable.firstIndex(of: self) ?? 0
            return Difficulty.selectable[(i + 1) % Difficulty.selectable.count]
        }
    }

    let difficulty: Difficulty
    private var cooldown = 0
    private var rng = SystemRandomNumberGenerator()

    init(difficulty: Difficulty = .normal) { self.difficulty = difficulty }

    /// `self` here is the opponent; `player` is the human.
    mutating func decide(opponent me: Fighter, player: Fighter) -> Intent? {
        if cooldown > 0 { cooldown -= 1; return nil }

        // Air normal on the way down from a jump-in (allowed while airborne).
        if me.canAirAct, me.vSpeed < 0, roll(0.6) {
            return roll(0.4) ? .heavyAttack : .lightAttack
        }
        guard me.canAct else { return nil }

        let dist = abs(me.position - player.position)
        let inLightRange = dist <= Move.light.reach + CombatSystem.bodyHalfWidth + 6
        let inSpecialRange = dist <= me.spec.special.reach + CombatSystem.bodyHalfWidth

        // React to an incoming heavy with a parry attempt.
        if player.state == .startup, player.currentMove?.kind == .heavy,
           roll(difficulty.parryChance) {
            cooldown = difficulty.reaction
            return .parry
        }

        // Throw a loaded special when in range.
        if me.meter >= CombatSystem.chargeToFire, inSpecialRange, roll(0.5) {
            cooldown = difficulty.reaction
            return .special
        }

        // Throw a turtling opponent that's holding block up close.
        if inLightRange, player.isBlocking, roll(difficulty.aggression) {
            cooldown = difficulty.reaction
            return .grab
        }

        // Poke when close.
        if inLightRange, roll(difficulty.aggression) {
            cooldown = difficulty.reaction / 2
            return roll(0.3) ? .heavyAttack : .lightAttack
        }

        // Otherwise close the gap (sometimes with a jump-in), or charge at range.
        if dist > me.spec.special.reach {
            if me.meter < 100, roll(0.4) {
                return .charge(0.12)            // top up the dial from neutral
            }
            if roll(0.18) { cooldown = difficulty.reaction; return .jump }   // approach
            return .stepForward
        }

        // In poke range but not committing: occasionally back off / block.
        if roll(0.15) { return .beginBlock }
        return nil
    }

    private mutating func roll(_ p: Double) -> Bool {
        Double.random(in: 0...1, using: &rng) < p
    }
}
