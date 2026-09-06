import CoreGraphics

/// How the practice dummy behaves. Mirrors the options in a typical fighting
/// game training room.
enum DummyBehavior: String, CaseIterable, Equatable {
    case stand          // does nothing
    case block          // holds block
    case crouchBlock    // holds block (low) — same effect here
    case jab            // throws periodic lights (test your defence)
    case cpu            // full AI
}

/// Training-room configuration.
struct TrainingOptions: Equatable {
    var dummyBehavior: DummyBehavior = .block
    var infinitePlayerMeter = true
    var infiniteHealth = true        // neither fighter dies; practice forever
    var showFrameData = true         // overlay current state + frame counts
}

/// Produces the dummy's intent each tick from its behaviour. Pure + cheap.
/// For `.cpu` it defers to the regular `AIController`.
struct TrainingDummy {
    var options: TrainingOptions
    private var ai = AIController(difficulty: .normal)
    private var jabTimer = 0

    init(options: TrainingOptions) { self.options = options }

    mutating func decide(dummy me: Fighter, player: Fighter) -> Intent? {
        switch options.dummyBehavior {
        case .stand:
            return nil
        case .block, .crouchBlock:
            return me.isBlocking ? nil : .beginBlock
        case .jab:
            jabTimer += 1
            if jabTimer >= 36 { jabTimer = 0; return .lightAttack }
            return nil
        case .cpu:
            return ai.decide(opponent: me, player: player)
        }
    }
}

/// Applies training conveniences (infinite health/meter) to a live combat
/// system each tick. Kept separate from `CombatSystem` so the core stays clean.
enum TrainingRules {
    static func apply(_ options: TrainingOptions, to combat: inout CombatSystem) {
        if options.infiniteHealth {
            combat.debugSetHealth(.player, combat.player.spec.maxHealth)
            combat.debugSetHealth(.opponent, combat.opponent.spec.maxHealth)
        }
        if options.infinitePlayerMeter {
            combat.debugSetMeter(.player, 100)
        }
    }
}
