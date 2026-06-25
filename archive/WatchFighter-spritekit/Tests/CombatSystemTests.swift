import XCTest
@testable import WatchFighter_Watch_App

/// Headless tests for the pure combat core — no simulator, no SpriteKit.
final class CombatSystemTests: XCTestCase {

    private func makeSystem() -> CombatSystem {
        CombatSystem(playerSpec: .volt, opponentSpec: .bastion, roundSeconds: 30)
    }

    func testLightAttackInRangeDealsDamage() {
        var sys = makeSystem()
        // Pull fighters together so a light reaches.
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        let startHP = sys.opponent.health
        _ = sys.apply(.lightAttack, from: .player)
        var landed = false
        for _ in 0..<Move.light.totalDuration + 2 {
            if sys.tick().contains(where: {
                if case .hitLanded = $0 { return true } else { return false }
            }) { landed = true }
        }
        XCTAssertTrue(landed, "light should connect in range")
        XCTAssertLessThan(sys.opponent.health, startHP)
    }

    func testOutOfRangeWhiffsHarmlessly() {
        var sys = makeSystem()  // fighters start far apart
        let startHP = sys.opponent.health
        _ = sys.apply(.lightAttack, from: .player)
        for _ in 0..<Move.light.totalDuration + 2 { _ = sys.tick() }
        XCTAssertEqual(sys.opponent.health, startHP)
    }

    func testChargeFillsMeterAndSpecialConsumesIt() {
        var sys = makeSystem()
        let ev = sys.apply(.charge(1.0), from: .player)   // big spin
        XCTAssertGreaterThanOrEqual(sys.player.meter, CombatSystem.chargeToFire)
        XCTAssertTrue(ev.contains(.specialReady(.player)) || sys.player.meterFull)
        let meterBefore = sys.player.meter
        _ = sys.apply(.special, from: .player)
        XCTAssertLessThan(sys.player.meter, meterBefore, "special should spend meter")
    }

    func testCannotActWhileAttacking() {
        var sys = makeSystem()
        _ = sys.apply(.heavyAttack, from: .player)
        XCTAssertFalse(sys.player.canAct)
        _ = sys.apply(.lightAttack, from: .player) // should be ignored
        XCTAssertEqual(sys.player.currentMove?.kind, .heavy)
    }

    func testBlockingTakesChipNotFullDamage() {
        var sys = makeSystem()
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        _ = sys.apply(.beginBlock, from: .opponent)
        let startHP = sys.opponent.health
        _ = sys.apply(.heavyAttack, from: .player)
        for _ in 0..<Move.heavy.totalDuration + 2 { _ = sys.tick() }
        let lost = startHP - sys.opponent.health
        XCTAssertGreaterThan(lost, 0)
        XCTAssertLessThan(lost, Move.heavy.damage, "block should reduce to chip")
    }

    func testRoundEndsWhenHealthDepleted() {
        var sys = makeSystem()
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        var over = false
        for _ in 0..<2000 where !over {
            _ = sys.apply(.heavyAttack, from: .player)
            for _ in 0..<Move.heavy.totalDuration + 1 {
                if sys.tick().contains(where: {
                    if case .roundOver = $0 { return true } else { return false }
                }) { over = true; break }
            }
        }
        XCTAssertTrue(sys.isOver)
    }
}
