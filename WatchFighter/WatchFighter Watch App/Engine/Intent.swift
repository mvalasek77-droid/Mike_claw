import CoreGraphics

/// Normalised player/AI commands. The raw hardware layer (`InputController`)
/// and the `AIController` both emit these, so the combat core never knows or
/// cares whether a move came from the Crown, a tap, or the CPU.
enum Intent: Equatable, Codable {
    case lightAttack
    case heavyAttack
    case special           // Crown snap-release of a charged meter
    case parry             // Crown press
    case stepForward
    case stepBack
    case jump
    case grab              // throw / command grab (beats block)
    case beginBlock
    case endBlock
    case charge(CGFloat)   // Crown rotation delta -> meter charge
}

/// Discrete feedback the presentation layer (haptics + FX) should fire.
/// The combat core returns these; it never calls UIKit/SpriteKit directly,
/// keeping the engine pure and testable.
enum CombatEvent: Equatable {
    case hitLanded(attacker: Side, damage: Int)
    case comboHit(by: Side, count: Int)
    case blocked(defender: Side, chip: Int)
    case parried(by: Side)
    case armorAbsorbed(Side)   // armored attacker powered through a hit
    case invulnerable(Side)    // ritual-guarded boss: hit did NOTHING
    case ritualBroken          // the secret process completed — boss now mortal
    case guardBroken(Side)
    case heavyWindup(Side)     // telegraph -> haptic the opponent can feel
    case specialReady(Side)
    case knockdown(Side)
    case thrown(Side)          // a throw connected on this side
    case throwTeched           // both grabbed at once — teched, no damage
    case dizzy(Side)           // stun maxed out — free punish state
    case finisher(by: Side)    // cinematic KO in the final round
    case roundOver(winner: Side?)
}

enum Side: Equatable, Hashable {
    case player
    case opponent
}
