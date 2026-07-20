import XCTest
@testable import Watchfighter

final class WatchfighterEngineTests: XCTestCase {
    func testVoiceResourcesAreBundledForArcadeCallouts() {
        for fileName in ["fight", "combo", "finish", "ko", "million", "titan"] {
            let url = Bundle.main.url(forResource: fileName, withExtension: "aiff", subdirectory: "Voice")
                ?? Bundle.main.url(forResource: fileName, withExtension: "aiff")
            XCTAssertNotNil(url, "Missing voice resource: \(fileName).aiff")
        }
    }

    func testFightersExposeDistinctTechniqueProfiles() {
        XCTAssertEqual(FighterArchetype.rook.preferredAttack(distance: 0.55, pressure: 0.4, meter: 0), .projectile)
        XCTAssertEqual(FighterArchetype.cage.preferredAttack(distance: 0.20, pressure: 0.7, meter: 0), .throwAttack)
        XCTAssertEqual(FighterArchetype.nova.preferredAttack(distance: 0.32, pressure: 0.7, meter: 0), .jumpKick)
        XCTAssertEqual(FighterArchetype.titan.displayName, "TITUS")
        XCTAssertTrue(FighterArchetype.titan.techniqueSummary.contains("8-hit"))
    }

    func testVersusRosterFollowsTournamentUnlockOrder() {
        XCTAssertEqual(FighterArchetype.versusRoster.first, .nyra)
        XCTAssertEqual(FighterArchetype.versusRoster[1], .rook)
        XCTAssertEqual(FighterArchetype.versusRoster.last, .titan)
    }

    func testPlayerAttackDamagesOpponentAndScores() {
        var engine = WatchfighterEngine(seed: 7)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)

        let startingHealth = engine.state.opponent.health
        let startingX = engine.state.opponent.x
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertGreaterThan(engine.state.opponent.x, startingX)
        XCTAssertGreaterThan(engine.state.score, 0)
        XCTAssertEqual(engine.state.combo, 1)
        XCTAssertGreaterThan(engine.state.hitStop, 0)
        XCTAssertGreaterThan(engine.state.cameraShake, 0)
        XCTAssertEqual(engine.state.impactKind, .hit)
    }

    func testMissCreatesWhiffFeedbackInsteadOfFakeBlock() {
        var engine = WatchfighterEngine(seed: 8)
        engine.debugSetPlayer(x: 0.20)
        engine.debugSetOpponent(x: 0.72)

        let startingHealth = engine.state.opponent.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.20, attacking: true))

        XCTAssertEqual(engine.state.opponent.health, startingHealth)
        XCTAssertEqual(engine.state.impactKind, .whiff)
        XCTAssertEqual(engine.state.cameraShake, 0)
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .whiff })
        XCTAssertFalse(engine.state.strikes.contains { $0.kind == .blocked })
    }

    func testCounterHitGetsExtraStunAndArcadeCallout() {
        var engine = WatchfighterEngine(seed: 9)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)
        engine.debugSetOpponentAction(.jab)

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertEqual(engine.state.impactKind, .counter)
        XCTAssertEqual(engine.state.combatCallout, "COUNTER")
        XCTAssertGreaterThan(engine.state.opponent.hitStun, 0.20)
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .counter })
    }

    func testLowGuardBreaksIntoLongStun() {
        var engine = WatchfighterEngine(seed: 10)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, guardMeter: 0.23)
        engine.debugSetOpponentAction(.blocking)

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertEqual(engine.state.impactKind, .guardBreak)
        XCTAssertEqual(engine.state.combatCallout, "GUARD BREAK")
        XCTAssertEqual(engine.state.opponent.guardMeter, 0)
        XCTAssertGreaterThanOrEqual(engine.state.opponent.hitStun, 0.36)
        XCTAssertEqual(engine.state.opponent.action, .hit)
    }

    func testComboChainsBeforeTimerExpires() {
        var engine = WatchfighterEngine(seed: 11)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
        coolPlayerAttack(&engine)
        engine.debugSetOpponent(x: 0.49)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertEqual(engine.state.combo, 2)
        XCTAssertEqual(engine.state.maxCombo, 2)
    }

    func testSpecialConsumesMeterAndLaunchesProjectileFromLongerRange() {
        var engine = WatchfighterEngine(seed: 13)
        engine.debugSetPlayer(x: 0.25)
        engine.debugSetOpponent(x: 0.61)
        engine.debugChargeSpecial()

        let startingHealth = engine.state.opponent.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.25, special: true))

        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertLessThanOrEqual(engine.state.player.meter, 0.05)
        XCTAssertEqual(engine.state.player.action, .projectile)
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .projectile })
    }

    func testDashStrikeClosesGapWithoutFullMeter() {
        var engine = WatchfighterEngine(seed: 61)
        engine.debugSetPlayer(x: 0.25)
        engine.debugSetOpponent(x: 0.61)

        let startingHealth = engine.state.opponent.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.25, dashStrike: true))

        XCTAssertGreaterThan(engine.state.player.x, 0.25)
        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertEqual(engine.state.player.action, .kick)
        XCTAssertGreaterThan(engine.state.player.meter, 0.20)
    }

    func testJumpKickHitsOverLongerArc() {
        var engine = WatchfighterEngine(seed: 67)
        engine.debugSetPlayer(x: 0.28)
        engine.debugSetOpponent(x: 0.58)

        let startingHealth = engine.state.opponent.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.28, jump: true))

        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertEqual(engine.state.player.action, .jumpKick)
    }

    func testThrowDamagesAndRepositionsAtPointBlank() {
        var engine = WatchfighterEngine(seed: 71)
        engine.debugSetPlayer(x: 0.36)
        engine.debugSetOpponent(x: 0.54)

        let startingHealth = engine.state.opponent.health
        let startingX = engine.state.opponent.x
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.36, throwing: true))

        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertGreaterThan(engine.state.opponent.x, startingX)
        XCTAssertEqual(engine.state.player.action, .throwAttack)
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .throwImpact })
    }

    func testCrouchSetsLowGuardStance() {
        var engine = WatchfighterEngine(seed: 73)
        engine.debugSetPlayer(x: 0.30, guardMeter: 0.4)
        engine.debugSetOpponent(x: 0.56)

        engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30, crouching: true))

        XCTAssertEqual(engine.state.player.action, .crouch)
        XCTAssertGreaterThan(engine.state.player.guardMeter, 0.4)
    }

    func testZonerProjectileReachesPastGrapplerProjectile() {
        var zoner = WatchfighterEngine(seed: 79)
        zoner.debugSetPlayer(x: 0.25, archetype: .cosmo)
        zoner.debugSetOpponent(x: 0.88)
        zoner.debugChargeSpecial()
        let zonerStartingHealth = zoner.state.opponent.health
        zoner.tick(delta: 0.01, input: GameInput(targetX: 0.25, special: true))

        var grappler = WatchfighterEngine(seed: 79)
        grappler.debugSetPlayer(x: 0.25, archetype: .cage)
        grappler.debugSetOpponent(x: 0.88)
        grappler.debugChargeSpecial()
        let grapplerStartingHealth = grappler.state.opponent.health
        grappler.tick(delta: 0.01, input: GameInput(targetX: 0.25, special: true))

        XCTAssertLessThan(zoner.state.opponent.health, zonerStartingHealth)
        XCTAssertEqual(grappler.state.opponent.health, grapplerStartingHealth)
    }

    func testGrapplerThrowHitsHarderAndPushesFartherThanAcrobatThrow() {
        var grappler = WatchfighterEngine(seed: 83)
        grappler.debugSetPlayer(x: 0.36, archetype: .cage)
        grappler.debugSetOpponent(x: 0.54)
        let grapplerStartingHealth = grappler.state.opponent.health
        let grapplerStartingX = grappler.state.opponent.x
        grappler.tick(delta: 0.01, input: GameInput(targetX: 0.36, throwing: true))

        var acrobat = WatchfighterEngine(seed: 83)
        acrobat.debugSetPlayer(x: 0.36, archetype: .nova)
        acrobat.debugSetOpponent(x: 0.54)
        let acrobatStartingHealth = acrobat.state.opponent.health
        let acrobatStartingX = acrobat.state.opponent.x
        acrobat.tick(delta: 0.01, input: GameInput(targetX: 0.36, throwing: true))

        let grapplerDamage = grapplerStartingHealth - grappler.state.opponent.health
        let acrobatDamage = acrobatStartingHealth - acrobat.state.opponent.health
        XCTAssertGreaterThan(grapplerDamage, acrobatDamage)
        XCTAssertGreaterThan(grappler.state.opponent.x - grapplerStartingX, acrobat.state.opponent.x - acrobatStartingX)
    }

    func testPlayerMovementStaysOnLeftSideOfDuelSpace() {
        var engine = WatchfighterEngine(seed: 17)

        for _ in 0..<20 {
            engine.tick(delta: 1.0 / 30.0, input: GameInput(targetX: -2))
        }
        XCTAssertGreaterThanOrEqual(engine.state.player.x, 0.14)

        for _ in 0..<40 {
            engine.tick(delta: 1.0 / 30.0, input: GameInput(targetX: 3))
        }
        XCTAssertLessThanOrEqual(engine.state.player.x, 0.56)
        XCTAssertLessThan(engine.state.player.x, engine.state.opponent.x)
    }

    func testRoundWinFreezesIntoVictoryState() {
        var engine = WatchfighterEngine(seed: 23)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertEqual(engine.state.playerWins, 1)
        XCTAssertEqual(engine.state.player.action, .victory)
        XCTAssertEqual(engine.state.opponent.action, .defeated)
        XCTAssertEqual(engine.state.bannerText, "ARM RIP")
        XCTAssertEqual(engine.state.finisherText, "ARM RIP")
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .armDrop })
    }

    func testChapterProgressionUsesEachRival() {
        var engine = WatchfighterEngine(seed: 29)

        let expected: [(StoryChapter, FighterArchetype)] = [
            (.neonRooftop, .rook),
            (.stormBridge, .voss),
            (.pirateCove, .mara),
            (.dragonAlley, .lennox),
            (.sunPier, .sunny)
        ]

        for (chapter, archetype) in expected {
            finishRoundWithPlayerWin(&engine)
            advancePastRoundPause(&engine)
            XCTAssertEqual(engine.state.chapter, chapter)
            XCTAssertEqual(engine.state.opponent.archetype, archetype)
        }
    }

    func testFullLadderEndsAfterFinalBoss() {
        var engine = WatchfighterEngine(seed: 29)

        for index in 0..<StoryChapter.allCases.count {
            finishRoundWithPlayerWin(&engine)
            if index < StoryChapter.allCases.count - 1 {
                advancePastRoundPause(&engine)
            }
        }

        XCTAssertEqual(engine.state.playerWins, StoryChapter.allCases.count)
        XCTAssertEqual(engine.state.phase, .gameOver)
        XCTAssertEqual(engine.state.winnerText, "VICTORY")
    }

    func testVersusModeEndsAfterOneRoundWin() {
        var engine = WatchfighterEngine(seed: 101)
        engine.resetVersus(opponent: .rook, chapter: .neonRooftop, seed: 101)

        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertEqual(engine.state.playerWins, 1)
        XCTAssertEqual(engine.state.phase, .gameOver)
        XCTAssertEqual(engine.state.winnerText, "VS WIN")
    }

    func testLearnModeRepeatsSameOpponentAfterRoundWin() {
        var engine = WatchfighterEngine(seed: 103)
        engine.resetLearn(opponent: .rook, seed: 103)

        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
        advancePastRoundPause(&engine)

        XCTAssertEqual(engine.state.phase, .running)
        XCTAssertEqual(engine.state.playerWins, 1)
        XCTAssertEqual(engine.state.opponent.archetype, .rook)
        XCTAssertEqual(engine.state.chapter, .cinderGate)
    }

    func testTitanRequiresComboSpecialForMillionShotDamage() {
        var engine = WatchfighterEngine(seed: 41)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, archetype: .titan)
        engine.debugChargeSpecial()

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
        XCTAssertGreaterThan(engine.state.opponent.health, 240)

        engine = WatchfighterEngine(seed: 43)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, archetype: .titan)
        engine.debugPrimeMillionShotCombo()
        engine.debugChargeSpecial()
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))

        XCTAssertLessThan(engine.state.opponent.health, 60)
        XCTAssertEqual(engine.state.bannerText, "MILLION SHOT")
    }

    func testLossRetriesCurrentChapterAndSecondLossEndsRun() {
        var engine = WatchfighterEngine(seed: 37)

        finishRoundWithOpponentWin(&engine)
        XCTAssertEqual(engine.state.opponentWins, 1)

        advancePastRoundPause(&engine)
        XCTAssertEqual(engine.state.phase, .running)
        XCTAssertEqual(engine.state.chapter, .cinderGate)
        XCTAssertEqual(engine.state.opponent.archetype, .nyra)

        finishRoundWithOpponentWin(&engine)
        XCTAssertEqual(engine.state.opponentWins, 2)
        XCTAssertEqual(engine.state.phase, .gameOver)
        XCTAssertEqual(engine.state.winnerText, "DEFEAT")
    }

    func testOpponentPressureCanDamagePlayer() {
        var engine = WatchfighterEngine(seed: 31)
        engine.debugSetPlayer(x: 0.36)
        engine.debugSetOpponent(x: 0.56)

        let startingHealth = engine.state.player.health
        for _ in 0..<14 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.36))
        }

        XCTAssertLessThan(engine.state.player.health, startingHealth)
    }

    func testBlockingReducesIncomingDamageAndConsumesGuard() {
        var openEngine = WatchfighterEngine(seed: 53)
        openEngine.debugSetPlayer(x: 0.36, guardMeter: 1)
        openEngine.debugSetOpponent(x: 0.56)
        let openDamage = advanceUntilPlayerTakesDamage(&openEngine, blocking: false)

        var blockEngine = WatchfighterEngine(seed: 53)
        blockEngine.debugSetPlayer(x: 0.36, guardMeter: 1)
        blockEngine.debugSetOpponent(x: 0.56)
        let blockedDamage = advanceUntilPlayerTakesDamage(&blockEngine, blocking: true)

        XCTAssertGreaterThan(openDamage, 0)
        XCTAssertGreaterThan(blockedDamage, 0)
        XCTAssertLessThan(blockedDamage, openDamage)
        XCTAssertLessThan(blockEngine.state.player.guardMeter, openEngine.state.player.guardMeter)
        XCTAssertEqual(blockEngine.state.player.action, .blocking)
    }

    func testOpponentCountersAfterPlayerConnects() {
        var engine = WatchfighterEngine(seed: 83)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)

        let startingPlayerHealth = engine.state.player.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
        XCTAssertLessThan(engine.state.opponent.health, engine.state.opponent.maxHealth)

        for _ in 0..<12 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }

        XCTAssertLessThan(engine.state.player.health, startingPlayerHealth)
        XCTAssertGreaterThanOrEqual(engine.state.opponent.combo, 1)
    }

    func testOpponentChainsReturnComboAfterLandingHit() {
        var engine = WatchfighterEngine(seed: 89)
        engine.debugSetPlayer(x: 0.36)
        engine.debugSetOpponent(x: 0.56, archetype: .lennox)

        let startingHealth = engine.state.player.health
        for _ in 0..<28 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.36))
        }

        XCTAssertGreaterThanOrEqual(engine.state.opponent.combo, 2)
        XCTAssertLessThan(engine.state.player.health, startingHealth - 10)
    }

    func testCorneredOpponentUsesSecretCounterAfterTakingHit() {
        var engine = WatchfighterEngine(seed: 97)
        engine.debugSetPlayer(x: 0.56)
        engine.debugSetOpponent(x: 0.86, archetype: .brass)
        engine.debugChargeSpecial()

        let startingPlayerHealth = engine.state.player.health
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.56, special: true))
        XCTAssertLessThan(engine.state.opponent.health, engine.state.opponent.maxHealth)

        var sawSecretCounter = false
        for _ in 0..<18 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.56))
            sawSecretCounter = sawSecretCounter || engine.state.strikes.contains {
                $0.side == .opponent && ($0.kind == .special || $0.kind == .projectile || $0.kind == .counter)
            }
        }

        XCTAssertTrue(sawSecretCounter)
        XCTAssertLessThan(engine.state.player.health, startingPlayerHealth)
        XCTAssertEqual(engine.state.bannerText, FighterArchetype.brass.signatureMove)
    }

    private func finishRoundWithPlayerWin(_ engine: inout WatchfighterEngine) {
        if engine.state.opponent.archetype == .titan {
            finishTitanRoundWithMillionShot(&engine)
            return
        }
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
    }

    private func finishTitanRoundWithMillionShot(_ engine: inout WatchfighterEngine) {
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)
        engine.debugPrimeMillionShotCombo()
        engine.debugChargeSpecial()
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
    }

    private func finishRoundWithOpponentWin(_ engine: inout WatchfighterEngine) {
        engine.debugSetPlayer(x: 0.36, health: 0, guardMeter: 0)
        engine.debugSetOpponent(x: 0.56)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.36))
    }

    private func coolPlayerAttack(_ engine: inout WatchfighterEngine) {
        for _ in 0..<6 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }
    }

    private func advancePastRoundPause(_ engine: inout WatchfighterEngine) {
        for _ in 0..<28 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }
    }

    private func advanceUntilPlayerTakesDamage(_ engine: inout WatchfighterEngine, blocking: Bool) -> Int {
        let startingHealth = engine.state.player.health
        for _ in 0..<20 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.36, blocking: blocking))
            let damage = startingHealth - engine.state.player.health
            if damage > 0 {
                return damage
            }
        }

        XCTFail("Expected opponent to damage player")
        return 0
    }
}
