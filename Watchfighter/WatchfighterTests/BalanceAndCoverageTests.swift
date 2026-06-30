import XCTest
@testable import Watchfighter

/// Deterministic engine tests that operationalize TEST_STRATEGY.md §3, §4, §5, §7:
/// character uniqueness, the boxer's invincibility, a full tournament clear, and
/// the per-floor difficulty ramp (AI gets tougher and hits back harder as you
/// climb). Everything runs headless on a seeded engine — no device required.
final class BalanceAndCoverageTests: XCTestCase {

    /// Every fighter in the game (the 15-strong ladder roster plus the hero).
    private let allArchetypes: [FighterArchetype] = FighterArchetype.versusRoster + [.kael]

    // MARK: - §3 Character uniqueness

    func testEveryFighterHasAUniqueBehavioralFingerprint() {
        var fingerprints: [String: FighterArchetype] = [:]
        for archetype in allArchetypes {
            let print = behavioralFingerprint(archetype)
            if let clash = fingerprints[print] {
                XCTFail("\(archetype.displayName) plays identically to \(clash.displayName)")
            }
            fingerprints[print] = archetype
        }
        XCTAssertEqual(fingerprints.count, allArchetypes.count)
    }

    func testEveryCombatStyleIsRepresentedInTheRoster() {
        let used = Set(allArchetypes.map { $0.combatStyle })
        for style in [CombatStyle.balanced, .rushdown, .grappler, .zoner, .acrobat, .bruiser, .titan] {
            XCTAssertTrue(used.contains(style), "no fighter uses the \(style) style")
        }
    }

    // MARK: - §4 The boxer cannot be defeated except by the Million Shot

    func testBossSurvivesEveryNonMillionAssault() {
        // A SPECIAL on any combo below 8 only chips the boss.
        for combo in 0...7 {
            var engine = WatchfighterEngine(seed: 5)
            engine.debugSetPlayer(x: 0.30)
            engine.debugSetOpponent(x: 0.49, archetype: .titan)
            engine.debugChargeSpecial()
            engine.debugSetPlayerCombo(combo)
            engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
            XCTAssertGreaterThan(engine.state.opponent.health, engine.state.opponent.maxHealth - 5,
                                 "combo \(combo) + special must not drop the boss")
        }

        // A full 8-hit combo without a SPECIAL also only chips him.
        var jabEngine = WatchfighterEngine(seed: 5)
        jabEngine.debugSetPlayer(x: 0.30)
        jabEngine.debugSetOpponent(x: 0.49, archetype: .titan)
        jabEngine.debugSetPlayerCombo(8)
        jabEngine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
        XCTAssertGreaterThan(jabEngine.state.opponent.health, jabEngine.state.opponent.maxHealth - 10,
                             "an 8-combo jab is not the secret — it must not drop the boss")

        // The ONE way through: SPECIAL on an 8+ combo lands the Million Shot.
        var killEngine = WatchfighterEngine(seed: 5)
        killEngine.debugSetPlayer(x: 0.30)
        killEngine.debugSetOpponent(x: 0.49, archetype: .titan)
        killEngine.debugChargeSpecial()
        killEngine.debugSetPlayerCombo(8)
        killEngine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
        XCTAssertEqual(killEngine.state.opponent.health, 0, "the Million Shot must finish the boss")
        XCTAssertEqual(killEngine.state.bannerText, "MILLION SHOT")
    }

    func testOnlyTheMillionBossIsDamageImmune() {
        // The same combo+special on a non-boss does normal (large) damage —
        // proves the immunity is gated on the boss flag, not the move.
        var engine = WatchfighterEngine(seed: 5)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, archetype: .kairo)
        engine.debugChargeSpecial()
        engine.debugSetPlayerCombo(8)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
        XCTAssertLessThan(engine.state.opponent.health, engine.state.opponent.maxHealth - 10)
    }

    // MARK: - §5 Full tournament run, reaching and clearing the boss

    func testTournamentFullRunReachesAndClearsBoss() {
        var engine = WatchfighterEngine(seed: 71)

        for index in 0..<StoryChapter.allCases.count {
            let isFinalFloor = index == StoryChapter.allCases.count - 1
            if isFinalFloor {
                XCTAssertEqual(engine.state.chapter, .millionRoom)
                XCTAssertEqual(engine.state.opponent.archetype, .titan)
            }

            if engine.state.opponent.archetype == .titan {
                // The boss only falls to the Million Shot.
                engine.debugSetPlayer(x: 0.30)
                engine.debugSetOpponent(x: 0.49)
                engine.debugPrimeMillionShotCombo()
                engine.debugChargeSpecial()
                engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
            } else {
                engine.debugSetPlayer(x: 0.30)
                engine.debugSetOpponent(x: 0.49, health: 4)
                engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
            }

            if !isFinalFloor {
                advancePastRoundPause(&engine)
            }
        }

        XCTAssertEqual(engine.state.playerWins, StoryChapter.allCases.count)
        XCTAssertEqual(engine.state.phase, .gameOver)
        XCTAssertEqual(engine.state.winnerText, "VICTORY")
    }

    func testLosingAMidFloorDropsToThePitAndRefightsTheSameFloor() {
        var engine = WatchfighterEngine(seed: 61)

        // Clear floor 1 to reach floor 2 (neonRooftop vs ROOK).
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
        advancePastRoundPause(&engine)
        let lostChapter = engine.state.chapter
        XCTAssertEqual(lostChapter, .neonRooftop)

        // Lose it — the run should continue (the Pit / second-chance loop) and
        // refight the SAME floor, not end and not skip ahead.
        engine.debugSetPlayer(x: 0.36, health: 0, guardMeter: 0)
        engine.debugSetOpponent(x: 0.56)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.36))
        advancePastRoundPause(&engine)

        XCTAssertEqual(engine.state.opponentWins, 1)
        XCTAssertEqual(engine.state.phase, .running, "one loss must not end the run")
        XCTAssertEqual(engine.state.chapter, lostChapter, "refight the floor you lost")
    }

    // MARK: - §7 The AI is tough, hits back hard, and scales per floor

    func testDifficultyRampIsNeutralOnFloorOneAndRisesToTheTop() {
        var floorOne = WatchfighterEngine(seed: 1)
        floorOne.resetVersus(player: .kael, opponent: .nyra, chapter: .cinderGate, seed: 1)
        XCTAssertEqual(floorOne.opponentDifficulty, 1.0, accuracy: 0.0001,
                       "floor 1 (and Learn mode) must stay fair")

        var top = WatchfighterEngine(seed: 1)
        top.resetVersus(player: .kael, opponent: .titan, chapter: .millionRoom, seed: 1)
        XCTAssertGreaterThan(top.opponentDifficulty, 1.4, "the top of the tower must be brutal")
    }

    func testHigherFloorsHitAPassivePlayerHarder() {
        // Same fighter, different floors — isolates the difficulty ramp from
        // archetype noise.
        let low = damageOutput(at: .cinderGate, opponent: .nyra, ticks: 120)
        let high = damageOutput(at: .obsidianThrone, opponent: .nyra, ticks: 120)
        XCTAssertGreaterThan(low, 0, "even floor 1 must punish a passive player")
        XCTAssertGreaterThan(high, low, "climbing the tower must raise the heat")
    }

    func testTheAIPunishesAPassivePlayerHardUpTheTower() {
        var engine = WatchfighterEngine(seed: 17)
        engine.resetVersus(player: .kael, opponent: .kairo, chapter: .obsidianThrone, seed: 17)
        let start = engine.state.player.health
        for _ in 0..<96 {   // 8 seconds of doing nothing
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }
        XCTAssertLessThan(engine.state.player.health, start - 30,
                          "a passive player should get punished hard, not ignored")
    }

    func testEachFighterCarriesItsOwnDifficulty() {
        // versusRoster is in ladder order and lines up 1:1 with the chapters.
        let pairs = Array(zip(StoryChapter.allCases, FighterArchetype.versusRoster))
        let outputs = pairs.map { damageOutput(at: $0.0, opponent: $0.1, ticks: 96) }

        let lowest = outputs.min() ?? 0
        let highest = outputs.max() ?? 0
        XCTAssertGreaterThan(highest, lowest + 30, "the roster must span easy-to-brutal")
        XCTAssertGreaterThan(Set(outputs).count, 6, "difficulty must not be flat across fighters")
    }

    // MARK: - Helpers

    /// Total damage a (passive) player absorbs, measuring the AI's output rate
    /// rather than a capped kill: the dummy is topped back up before it dies.
    private func damageOutput(at chapter: StoryChapter,
                              opponent: FighterArchetype,
                              ticks: Int,
                              seed: UInt64 = 11) -> Int {
        var engine = WatchfighterEngine(seed: seed)
        engine.resetVersus(player: .kael, opponent: opponent, chapter: chapter, seed: seed)
        var total = 0
        for _ in 0..<ticks {
            // Top up BEFORE the tick, above the largest possible single hit, so
            // the dummy can never die mid-fight and freeze the round (which would
            // cap output and corrupt the comparison).
            if engine.state.player.health < 80 {
                engine.debugSetPlayer(x: engine.state.player.x, health: engine.state.player.maxHealth)
            }
            let before = engine.state.player.health
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
            let dealt = before - engine.state.player.health
            if dealt > 0 { total += dealt }
        }
        return total
    }

    /// A behavioral signature built only from how a fighter *plays* (style,
    /// stats, and its move table on a distance/meter/pressure grid) — not its
    /// name — so two fighters that feel the same would collide.
    private func behavioralFingerprint(_ archetype: FighterArchetype) -> String {
        let style = archetype.combatStyle
        var parts: [String] = [
            "style=\(style)",
            "power=\(archetype.power)",
            "quick=\(archetype.quickness)",
            "hp=\(archetype.maxHealth)",
            "meter=\(style.meterBuildRate)",
            "guard=\(style.guardPressure)",
            "throw=\(style.throwPush)"
        ]
        for distance in stride(from: CGFloat(0.18), through: 0.66, by: 0.12) {
            for meter in [CGFloat(0), 0.5, 1.0] {
                for pressure in [CGFloat(0.3), 0.7] {
                    let move = archetype.preferredAttack(distance: distance, pressure: pressure, meter: meter)
                    parts.append(String(describing: move))
                }
            }
        }
        return parts.joined(separator: "|")
    }

    private func advancePastRoundPause(_ engine: inout WatchfighterEngine) {
        for _ in 0..<28 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }
    }
}
