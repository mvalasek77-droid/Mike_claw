import XCTest
@testable import WatchFighter_Watch_App

/// Tests for the M1 mechanics: projectiles, combo cancels, match flow, story.
final class MechanicsTests: XCTestCase {

    private func contains(_ events: [CombatEvent], _ match: (CombatEvent) -> Bool) -> Bool {
        events.contains(where: match)
    }

    func testProjectileTravelsAndHits() {
        var sys = CombatSystem(playerSpec: .ember, opponentSpec: .bastion)
        _ = sys.apply(.charge(1.0), from: .player)     // fill meter
        _ = sys.apply(.special, from: .player)         // fire projectile
        let startHP = sys.opponent.health

        var hit = false
        for _ in 0..<300 where !hit && !sys.isOver {
            hit = contains(sys.tick()) { if case .hitLanded = $0 { return true }; return false }
        }
        XCTAssertTrue(hit, "projectile should travel across the lane and connect")
        XCTAssertLessThan(sys.opponent.health, startHP)
    }

    func testProjectileSpawnsTravellingNode() {
        var sys = CombatSystem(playerSpec: .frost, opponentSpec: .bastion)
        _ = sys.apply(.charge(1.0), from: .player)
        _ = sys.apply(.special, from: .player)
        var sawProjectile = false
        for _ in 0..<40 where !sawProjectile {
            _ = sys.tick()
            if !sys.projectiles.isEmpty { sawProjectile = true }
        }
        XCTAssertTrue(sawProjectile, "a projectile entity should exist mid-flight")
    }

    func testComboCancelProducesMultiHit() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }

        var maxCombo = 0
        _ = sys.apply(.lightAttack, from: .player)
        for _ in 0..<40 {
            for e in sys.tick() {
                if case let .comboHit(_, count) = e { maxCombo = max(maxCombo, count) }
                if case .hitLanded = e { _ = sys.apply(.heavyAttack, from: .player) } // cancel up
            }
        }
        XCTAssertGreaterThanOrEqual(maxCombo, 2, "light should cancel into heavy for a 2+ combo")
    }

    func testCannotCancelDownward() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .bastion)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        // Land a heavy, then attempt to cancel into a light (lower rank): rejected.
        _ = sys.apply(.heavyAttack, from: .player)
        var canceledLight = false
        for _ in 0..<30 {
            for e in sys.tick() {
                guard case .hitLanded = e else { continue }
                _ = sys.apply(.lightAttack, from: .player)
                if sys.player.currentMove?.kind == .light { canceledLight = true }
            }
        }
        XCTAssertFalse(canceledLight, "heavy must not cancel into a lower-rank light")
    }

    func testMatchBestOfThree() {
        var flow = MatchFlow(playerSpec: .tetsu, opponentSpec: .bastion)
        flow.recordRoundResult(.player)
        XCTAssertFalse(flow.isMatchOver)
        XCTAssertEqual(flow.playerRoundsWon, 1)
        flow.startNextRound()
        XCTAssertEqual(flow.currentRound, 2)
        flow.recordRoundResult(.player)
        XCTAssertTrue(flow.isMatchOver)
        XCTAssertEqual(flow.matchWinner, .player)
    }

    func testRoundResetRestoresHealth() {
        var flow = MatchFlow(playerSpec: .tetsu, opponentSpec: .bastion)
        for _ in 0..<60 { _ = flow.apply(.stepForward, from: .player) }
        _ = flow.apply(.heavyAttack, from: .player)
        for _ in 0..<Move.heavy.totalDuration + 1 { _ = flow.tick() }
        XCTAssertLessThan(flow.combat.opponent.health, flow.opponentSpec.maxHealth)
        flow.recordRoundResult(.player)
        flow.startNextRound()
        XCTAssertEqual(flow.combat.opponent.health, flow.opponentSpec.maxHealth)
        XCTAssertEqual(flow.combat.player.health, flow.playerSpec.maxHealth)
    }

    func testStoryLadderAdvancesToCompletion() {
        var s = StoryMode(playerID: "tetsu")
        XCTAssertEqual(s.currentOpponent.id, "volt")
        var fights = 1
        while s.advance() { fights += 1 }
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(fights, StoryScript.ladder.count)
        XCTAssertEqual(s.currentOpponent.id, "onyx", "ladder ends at the boss")
    }

    func testRosterIntegrity() {
        XCTAssertEqual(CharacterSpec.selectable.count, 6)
        for spec in CharacterSpec.selectable {
            XCTAssertGreaterThan(spec.maxHealth, 0)
            XCTAssertFalse(StageLibrary.stage(id: spec.homeStageID).id.isEmpty)
        }
        XCTAssertEqual(CharacterSpec.byID("onyx").id, "onyx")
        XCTAssertEqual(CharacterSpec.byID("nonsense").id, "tetsu", "unknown id falls back to default")
    }
}
