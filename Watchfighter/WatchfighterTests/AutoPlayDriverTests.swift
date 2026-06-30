import XCTest
@testable import Watchfighter

/// Unit tests for the self-play bot that drives demo mode and the storyboard
/// walk. Behavior must be deterministic and sensible per game state.
final class AutoPlayDriverTests: XCTestCase {

    private func state(playerX: CGFloat, opponentX: CGFloat, fullMeter: Bool = false) -> WatchfighterState {
        var engine = WatchfighterEngine(seed: 1)
        engine.debugSetPlayer(x: playerX)
        engine.debugSetOpponent(x: opponentX)
        if fullMeter { engine.debugChargeSpecial() }
        return engine.state
    }

    func testPassiveStyleNeverAttacks() {
        let driver = AutoPlayDriver(style: .passive)
        let input = driver.input(for: state(playerX: 0.30, opponentX: 0.55))
        XCTAssertFalse(input.attacking)
        XCTAssertFalse(input.special)
        XCTAssertFalse(input.jump)
        XCTAssertFalse(input.throwing)
        XCTAssertFalse(input.blocking)
    }

    func testApproachesWhenOutOfRange() {
        let driver = AutoPlayDriver()
        let input = driver.input(for: state(playerX: 0.16, opponentX: 0.80))
        // No offense at long range — just close the gap toward the opponent.
        XCTAssertFalse(input.attacking)
        XCTAssertFalse(input.special)
        XCTAssertFalse(input.jump)
        XCTAssertFalse(input.throwing)
        XCTAssertGreaterThan(input.targetX, 0.16, "should move toward the opponent")
    }

    func testStrikesWhenInRange() {
        let driver = AutoPlayDriver()
        let input = driver.input(for: state(playerX: 0.30, opponentX: 0.55))
        let offensive = input.attacking || input.jump || input.throwing || input.special
        XCTAssertTrue(offensive, "an in-range bot should commit to an attack")
    }

    func testCashesSpecialOnFullMeter() {
        let driver = AutoPlayDriver()
        let input = driver.input(for: state(playerX: 0.40, opponentX: 0.55, fullMeter: true))
        XCTAssertTrue(input.special, "a full meter in range should fire the special")
    }

    func testIsDeterministic() {
        let driver = AutoPlayDriver()
        let s = state(playerX: 0.30, opponentX: 0.55)
        XCTAssertEqual(driver.input(for: s), driver.input(for: s))
    }
}
