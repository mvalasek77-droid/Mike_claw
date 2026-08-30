import XCTest
@testable import Watchfighter

final class WatchfighterEngineTests: XCTestCase {
    func testArcadeRoundsUseClassicLengthAndDurability() {
        let engine = WatchfighterEngine(seed: 5)

        XCTAssertEqual(engine.state.roundTimer, 99)
        XCTAssertEqual(engine.state.player.maxHealth, FighterArchetype.kael.arcadeHealth)
        XCTAssertGreaterThan(engine.state.player.maxHealth, FighterArchetype.kael.maxHealth)
    }

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
        XCTAssertTrue(FighterArchetype.titan.techniqueSummary.contains("hidden weakness"))
        XCTAssertFalse(FighterArchetype.titan.techniqueSummary.contains("8-hit"))
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
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        XCTAssertLessThan(engine.state.opponent.health, startingHealth)
        XCTAssertGreaterThan(engine.state.score, 0)
        XCTAssertEqual(engine.state.combo, 1)
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
            (.sunPier, .sunny),
            (.runwayTerminal, .nova),
            (.blackoutBase, .specter),
            (.launchFoundry, .cosmo),
            (.goldRally, .brass),
            (.icePalace, .volkov),
            (.redCarpet, .zara),
            (.cageNight, .cage),
            (.obsidianThrone, .kairo),
            (.millionRoom, .titan)
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

    func testDraculaBiteTurnsTheDefenderIntoAVampire() {
        // Dracula's bite is a throwAttack from an archetype that inflicts the
        // vampire bite. Pin both fighters at point-blank before every tick so
        // his float-away hover can't drift him out of bite range before his
        // attack clock expires (throws ignore guard, so the bite must land).
        var engine = WatchfighterEngine(seed: 61)
        engine.debugSetOpponent(x: 0.58, archetype: .dracula)
        XCTAssertFalse(engine.state.player.isVampire)

        for _ in 0..<40 where !engine.state.player.isVampire {
            engine.debugSetPlayer(x: 0.40)
            engine.debugSetOpponent(x: 0.56)
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.40))
        }

        XCTAssertTrue(engine.state.player.isVampire, "a landed Dracula bite must turn the defender")
        XCTAssertTrue(engine.state.strikes.contains { $0.kind == .vampireBite })
    }

    func testAbaddonIsABruiserNotTheMillionBoss() {
        // Abaddon (the Hell demon) must never accidentally trip the Titus-only
        // Million Shot invincibility rule — he's tough, but beatable normally.
        XCTAssertFalse(FighterArchetype.abaddon.isMillionBoss)
        XCTAssertEqual(FighterArchetype.abaddon.combatStyle, .bruiser)
        XCTAssertEqual(FighterArchetype.abaddon.preferredAttack(distance: 0.40, pressure: 0.8, meter: 0), .projectile)
        XCTAssertEqual(FighterArchetype.abaddon.preferredAttack(distance: 0.20, pressure: 0.2, meter: 0), .throwAttack)
    }

    func testFirstFallDropsPlayerIntoTheHellFightAgainstAbaddon() {
        var engine = WatchfighterEngine(seed: 37)

        finishRoundWithOpponentWin(&engine)
        XCTAssertTrue(engine.state.pitActive, "a ladder fall drops the player into the Pit")
        XCTAssertEqual(engine.state.opponentWins, 0, "the fall is a redirect to Hell, not a counted strike")

        advancePastRoundPause(&engine)
        XCTAssertEqual(engine.state.phase, .running)
        XCTAssertEqual(engine.state.chapter, .cinderGate)
        XCTAssertEqual(engine.state.opponent.archetype, .abaddon, "the Pit fight is against the Hell demon")
    }

    func testWinningTheHellFightReturnsToTheSameFloorsRival() {
        var engine = WatchfighterEngine(seed: 37)
        finishRoundWithOpponentWin(&engine)   // fall -> Hell
        advancePastRoundPause(&engine)
        XCTAssertEqual(engine.state.opponent.archetype, .abaddon)

        finishRoundWithPlayerWin(&engine)     // beat Abaddon
        XCTAssertFalse(engine.state.pitActive)
        XCTAssertEqual(engine.state.playerWins, 0, "beating Abaddon earns no ladder credit")

        advancePastRoundPause(&engine)
        XCTAssertEqual(engine.state.phase, .running)
        XCTAssertEqual(engine.state.chapter, .cinderGate, "back to the floor you fell on")
        XCTAssertEqual(engine.state.opponent.archetype, .nyra, "refighting the real floor 1 rival")
    }

    func testLosingTheHellFightEndsTheRun() {
        var engine = WatchfighterEngine(seed: 37)
        finishRoundWithOpponentWin(&engine)   // fall -> Hell
        advancePastRoundPause(&engine)
        XCTAssertEqual(engine.state.opponent.archetype, .abaddon)

        finishRoundWithOpponentWin(&engine)   // lose to the demon
        XCTAssertEqual(engine.state.opponentWins, 1)
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
        for _ in 0..<12 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.56))
            sawSecretCounter = sawSecretCounter || engine.state.strikes.contains {
                $0.side == .opponent && ($0.kind == .special || $0.kind == .projectile)
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
