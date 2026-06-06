import CoreGraphics

/// The categories of attack a fighter can throw.
/// Light/Heavy come from screen taps; Special/EX come from the Crown.
enum MoveKind: Equatable {
    case light
    case heavy
    case special
    case ex
}

/// Coarse, wrist-legible frame data. One "frame" == one fixed engine tick
/// (see `CombatSystem.tickRate`). Values are intentionally chunky so the
/// game stays readable on a 1.5" screen — this is timing, not 1-frame links.
struct Move: Equatable {
    let kind: MoveKind
    let startup: Int       // ticks before the hitbox goes active
    let active: Int        // ticks the hitbox is live
    let recovery: Int      // ticks of vulnerability after
    let damage: Int
    let chip: Int          // damage dealt even on block
    let hitstun: Int       // ticks the victim is stunned on hit
    let blockstun: Int     // ticks the victim is stunned on block
    let pushback: CGFloat  // points the victim slides
    let reach: CGFloat     // hitbox extension in front of the fighter (points)
    let meterGain: Int     // special meter gained on a clean hit

    var totalDuration: Int { startup + active + recovery }
}

extension Move {
    static let light = Move(
        kind: .light, startup: 3, active: 2, recovery: 6,
        damage: 6, chip: 1, hitstun: 12, blockstun: 8,
        pushback: 6, reach: 26, meterGain: 6
    )

    static let heavy = Move(
        kind: .heavy, startup: 9, active: 3, recovery: 16,
        damage: 14, chip: 3, hitstun: 20, blockstun: 12,
        pushback: 14, reach: 32, meterGain: 10
    )

    /// Base special — parameters get overridden per character.
    static func special(
        damage: Int, reach: CGFloat, pushback: CGFloat, startup: Int = 6
    ) -> Move {
        Move(
            kind: .special, startup: startup, active: 4, recovery: 18,
            damage: damage, chip: damage / 3, hitstun: 24, blockstun: 14,
            pushback: pushback, reach: reach, meterGain: 0
        )
    }

    /// EX (super) version, unlocked at full meter — armored startup, big reward.
    static func ex(from base: Move) -> Move {
        Move(
            kind: .ex, startup: base.startup, active: base.active + 2,
            recovery: base.recovery + 4,
            damage: base.damage * 2, chip: base.chip * 2,
            hitstun: base.hitstun + 8, blockstun: base.blockstun + 4,
            pushback: base.pushback * 1.5, reach: base.reach * 1.2,
            meterGain: 0
        )
    }
}
