import XCTest
@testable import WatchFighter_Watch_App

/// Tests for the "firm-up" fundamentals modelled on the classic 2D fighter base:
/// jumping/gravity, the aerial game, throws + techs, and stun/dizzy.
final class FundamentalsTests: XCTestCase {

    private func contains(_ events: [CombatEvent], _ m: (CombatEvent) -> Bool) -> Bool {
        events.contains(where: m)
    }
    private func close(_ sys: inout CombatSystem) {
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
    }

    func testJumpRisesUnderGravityAndLands() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        _ = sys.apply(.jump, from: .player)
        XCTAssertTrue(sys.player.airborne)
        var maxHeight: CGFloat = 0
        for _ in 0..<80 { _ = sys.tick(); maxHeight = max(maxHeight, sys.player.height) }
        XCTAssertGreaterThan(maxHeight, 20, "jump should gain real height")
        XCTAssertFalse(sys.player.airborne, "fighter should land")
        XCTAssertEqual(sys.player.height, 0, accuracy: 0.001)
    }

    func testAirAttackHitsGroundedOpponent() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        close(&sys)
        _ = sys.apply(.jump, from: .player)
        _ = sys.apply(.heavyAttack, from: .player)     // becomes an air heavy
        XCTAssertEqual(sys.player.currentMove, .airHeavy)
        var hit = false
        for _ in 0..<25 where !hit {
            hit = contains(sys.tick()) { if case .hitLanded = $0 { return true }; return false }
        }
        XCTAssertTrue(hit, "a jump-in air heavy should connect with a grounded foe")
    }

    func testThrowBeatsBlock() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        close(&sys)
        _ = sys.apply(.beginBlock, from: .opponent)
        let hp = sys.opponent.health
        _ = sys.apply(.grab, from: .player)
        var thrown = false
        for _ in 0..<10 where !thrown { thrown = sys.tick().contains(.thrown(.opponent)) }
        XCTAssertTrue(thrown, "a throw must beat block")
        XCTAssertLessThan(sys.opponent.health, hp)
    }

    func testThrowWhiffsOnAirborneFoe() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        close(&sys)
        _ = sys.apply(.jump, from: .opponent)          // jump out of the grab
        let hp = sys.opponent.health
        _ = sys.apply(.grab, from: .player)
        var thrown = false
        for _ in 0..<8 { if sys.tick().contains(.thrown(.opponent)) { thrown = true } }
        XCTAssertFalse(thrown, "throws can't grab an airborne opponent")
        XCTAssertEqual(sys.opponent.health, hp)
    }

    func testSimultaneousGrabsTech() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        close(&sys)
        _ = sys.apply(.grab, from: .player)
        _ = sys.apply(.grab, from: .opponent)
        var teched = false
        for _ in 0..<10 where !teched { teched = sys.tick().contains(.throwTeched) }
        XCTAssertTrue(teched, "two grabs at once should tech")
    }

    func testStunBuildsToDizzy() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        var dizzied = false
        for _ in 0..<50 where !dizzied {
            for _ in 0..<3 { _ = sys.apply(.stepForward, from: .player) }  // stay in range
            _ = sys.apply(.lightAttack, from: .player)
            for _ in 0..<(Move.light.totalDuration + 1) where !dizzied {
                dizzied = sys.tick().contains(.dizzy(.opponent))
            }
        }
        XCTAssertTrue(dizzied, "accumulated stun should eventually cause a dizzy")
    }

    func testProjectileCooldownBlocksSpam() {
        var sys = CombatSystem(playerSpec: .ember, opponentSpec: .bastion)
        _ = sys.apply(.charge(1.0), from: .player)
        _ = sys.apply(.special, from: .player)          // first fireball (tick 0)
        XCTAssertEqual(sys.player.state, .startup)
        for _ in 0..<40 { _ = sys.tick() }              // let the move fully recover
        XCTAssertEqual(sys.player.state, .idle)

        _ = sys.apply(.charge(1.0), from: .player)      // refill meter
        _ = sys.apply(.special, from: .player)          // still within cooldown
        XCTAssertEqual(sys.player.state, .idle, "second fireball on cooldown is blocked")

        for _ in 0..<10 { _ = sys.tick() }              // wait out the cooldown
        _ = sys.apply(.charge(1.0), from: .player)
        _ = sys.apply(.special, from: .player)
        XCTAssertEqual(sys.player.state, .startup, "fireball fires again after cooldown")
    }

    func testPerCharacterAerials() {
        XCTAssertGreaterThan(CharacterSpec.marina.airHeavy.reach, Move.airHeavy.reach)
        XCTAssertEqual(CharacterSpec.tetsu.airHeavy, Move.airHeavy, "default aerials unchanged")
    }

    func testGroundedHitDetectionUnchanged() {
        // Regression: the 2D box check must not break grounded-vs-grounded.
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        close(&sys)
        let hp = sys.opponent.health
        _ = sys.apply(.lightAttack, from: .player)
        for _ in 0..<(Move.light.totalDuration + 1) { _ = sys.tick() }
        XCTAssertLessThan(sys.opponent.health, hp)
    }
}
