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
        XCTAssertEqual(CharacterSpec.selectable.count, 10)
        for spec in CharacterSpec.selectable {
            XCTAssertGreaterThan(spec.maxHealth, 0)
            // Every character's home stage must resolve to a real stage.
            XCTAssertEqual(StageLibrary.stage(id: spec.homeStageID).id, spec.homeStageID)
        }
        XCTAssertEqual(CharacterSpec.byID("titus").id, "titus", "final boss resolvable")
        XCTAssertEqual(CharacterSpec.byID("onyx").id, "onyx")
        XCTAssertEqual(CharacterSpec.byID("nonsense").id, "tetsu", "unknown id falls back to default")
        XCTAssertEqual(CharacterSpec.arcadeLadder.last?.id, "titus", "ladder ends at the boss")
    }

    func testArmorPowersThroughAHit() {
        // TITUS's special is armored: a poke during its startup is absorbed,
        // he keeps his move, and only takes chip damage.
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .titus)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        _ = sys.apply(.charge(0.4), from: .opponent)        // enough meter for base special
        _ = sys.apply(.special, from: .opponent)            // boss starts armored haymaker
        XCTAssertEqual(sys.opponent.state, .startup)

        let bossHPBefore = sys.opponent.health
        _ = sys.apply(.lightAttack, from: .player)          // poke into the armor
        var absorbed = false
        for _ in 0..<8 {
            if sys.tick().contains(.armorAbsorbed(.opponent)) { absorbed = true; break }
        }
        XCTAssertTrue(absorbed, "armored startup should absorb the poke")
        XCTAssertNotEqual(sys.opponent.health, bossHPBefore, "armor still takes chip")
        // The boss was not put into hitstun by the poke.
        XCTAssertNotEqual(sys.opponent.state, .hitStun)
    }

    func testBossIsInvincibleUntilRitual() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .titus)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        let hp = sys.opponent.health
        var sawInvuln = false
        for _ in 0..<10 {
            _ = sys.apply(.lightAttack, from: .player)
            for _ in 0..<(Move.light.totalDuration + 1) {
                if sys.tick().contains(.invulnerable(.opponent)) { sawInvuln = true }
            }
        }
        XCTAssertTrue(sawInvuln, "hits on the guarded boss should report no effect")
        XCTAssertEqual(sys.opponent.health, hp, "boss takes ZERO damage before the ritual")
    }

    func testRitualMakesBossMortal() {
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .titus)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        sys.breakRitualGuard()
        let hp = sys.opponent.health
        _ = sys.apply(.lightAttack, from: .player)
        for _ in 0..<(Move.light.totalDuration + 1) { _ = sys.tick() }
        XCTAssertLessThan(sys.opponent.health, hp, "after the ritual the boss can be hurt")
    }

    func testBossRitualRequiresPerfectSequence() {
        var r = BossRitual()
        XCTAssertFalse(r.note(.parry))
        XCTAssertFalse(r.note(.parry))
        XCTAssertFalse(r.note(.lightAttack))
        XCTAssertFalse(r.note(.heavyAttack))
        XCTAssertTrue(r.note(.special), "correct full sequence completes the ritual")
        XCTAssertTrue(r.complete)
    }

    func testBossRitualResetsOnWrongKey() {
        var r = BossRitual()
        _ = r.note(.parry)                 // progress 1
        _ = r.note(.heavyAttack)           // wrong key -> reset
        XCTAssertEqual(r.progress, 0)
        XCTAssertFalse(r.complete)
    }

    func testBossRitualIgnoresIncidentalInputs() {
        var r = BossRitual()
        _ = r.note(.beginBlock)            // ignored
        _ = r.note(.charge(0.5))           // ignored
        _ = r.note(.stepForward)           // ignored
        _ = r.note(.parry)                 // counts
        XCTAssertEqual(r.progress, 1, "block/charge/step must not break the chain")
    }

    func testParryBeatsArmor() {
        // The intended answer to the armored haymaker: parry it.
        var sys = CombatSystem(playerSpec: .tetsu, opponentSpec: .titus)
        for _ in 0..<60 { _ = sys.apply(.stepForward, from: .player) }
        _ = sys.apply(.charge(0.4), from: .opponent)
        _ = sys.apply(.special, from: .opponent)
        // Boss special has 6f startup; parry (6f window) just before it goes active.
        for _ in 0..<4 { _ = sys.tick() }
        _ = sys.apply(.parry, from: .player)
        var parried = false
        for _ in 0..<10 {
            if sys.tick().contains(.parried(by: .player)) { parried = true; break }
        }
        XCTAssertTrue(parried, "a well-timed parry should stop even the armored boss")
    }
}
