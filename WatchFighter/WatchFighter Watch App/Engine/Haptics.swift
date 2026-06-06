#if os(watchOS)
import WatchKit

/// Maps `CombatEvent`s to the Taptic Engine. The haptic *telegraph* on an
/// opponent's heavy wind-up is the game's core skill expression — players
/// learn to parry on feel without staring at the tiny screen.
enum Haptics {
    static func play(for event: CombatEvent, viewer: Side) {
        let device = WKInterfaceDevice.current()
        switch event {
        case .heavyWindup(let s) where s != viewer:
            device.play(.directionUp)          // "incoming heavy" — feel & parry
        case .hitLanded(let attacker, _):
            device.play(attacker == viewer ? .success : .failure)
        case .blocked(let defender, _):
            if defender == viewer { device.play(.click) }
        case .parried(let by):
            if by == viewer { device.play(.click) }
        case .guardBroken(let s) where s == viewer:
            device.play(.retry)
        case .specialReady(let s) where s == viewer:
            device.play(.notification)
        case .knockdown(let s) where s == viewer:
            device.play(.failure)
        case .roundOver(let winner):
            device.play(winner == viewer ? .success : .failure)
        default:
            break
        }
    }
}
#else
/// Headless stub so the engine + tests build on macOS/Linux CI.
enum Haptics {
    static func play(for event: CombatEvent, viewer: Side) {}
}
#endif
