import CoreGraphics

/// A deterministic self-play "bot" that turns the current game state into the
/// next `GameInput`. It drives the attract/demo mode in `GameScreen` and the
/// storyboard capture in the test target — so the same logic that shows off the
/// game also walks it through every scene for screenshots (TEST_STRATEGY.md §8).
///
/// It is intentionally stateless and pure: the same state always yields the same
/// input, which keeps demo playback and test runs reproducible.
struct AutoPlayDriver {

    /// How the bot should behave this run.
    enum Style {
        /// Skilled pressure: close the gap, mix strikes, block real threats,
        /// throw at point-blank, and cash specials on a full meter.
        case aggressive
        /// Do nothing but hold position — used to measure how hard the AI hits
        /// back and to capture "under pressure" frames.
        case passive
    }

    var style: Style = .aggressive

    /// The striking pocket the bot tries to hold.
    private let pocket: CGFloat = 0.24

    func input(for state: WatchfighterState) -> GameInput {
        let player = state.player
        let opponent = state.opponent
        let rawTarget = opponent.x - pocket
        let target = min(max(rawTarget, 0.14), 0.52)

        if style == .passive {
            return GameInput(targetX: target)
        }

        let distance = abs(opponent.x - player.x)
        let inRange = distance < 0.30
        let pointBlank = distance < 0.20
        let opponentAttacking = opponent.action == .jab || opponent.action == .kick
            || opponent.action == .jumpKick || opponent.action == .special
            || opponent.action == .projectile
        let underThreat = distance < 0.27 && opponentAttacking

        // 1) Cash a full meter as soon as there's a target in range.
        if player.meter >= 1, distance < 0.52 {
            return GameInput(targetX: target, special: true)
        }
        // 2) Respect incoming pressure — block instead of trading blindly.
        if underThreat {
            return GameInput(targetX: target, blocking: true)
        }
        // 3) Mix in a flip kick on every few hits so the bot shows off the
        //    aerials, then a throw at point-blank, else a normal strike.
        if inRange {
            if state.combo > 0, state.combo % 4 == 0 {
                return GameInput(targetX: target, jump: true)
            }
            if pointBlank {
                return GameInput(targetX: target, throwing: true)
            }
            return GameInput(targetX: target, attacking: true)
        }
        // 4) Out of range — just close the distance.
        return GameInput(targetX: target)
    }
}
