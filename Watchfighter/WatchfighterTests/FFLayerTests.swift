import XCTest
@testable import Watchfighter

/// Tests for the additions layered onto the base game: the `actionDuration`
/// backbone for smooth motion, and the FF-style cutscene content/routing data.
final class FFLayerTests: XCTestCase {

    // MARK: - Smooth-motion backbone (actionDuration)

    func testFreshFighterHasNoActionDuration() {
        let engine = WatchfighterEngine(seed: 1)
        XCTAssertEqual(engine.state.player.action, .idle)
        XCTAssertEqual(engine.state.player.actionDuration, 0, accuracy: 0.0001)
    }

    func testAttackSetsActionDurationForMotionEnvelope() {
        var engine = WatchfighterEngine(seed: 7)
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))

        // The strike envelope needs a positive duration and timer<=duration so
        // progress (1 - timer/duration) stays in 0...1.
        XCTAssertGreaterThan(engine.state.player.actionDuration, 0)
        XCTAssertLessThanOrEqual(engine.state.player.actionTimer, engine.state.player.actionDuration)
        XCTAssertGreaterThan(engine.state.player.actionTimer, 0)
    }

    func testSpecialSetsActionDuration() {
        var engine = WatchfighterEngine(seed: 13)
        engine.debugSetPlayer(x: 0.25)
        engine.debugSetOpponent(x: 0.61)
        engine.debugChargeSpecial()

        engine.tick(delta: 0.01, input: GameInput(targetX: 0.25, special: true))

        XCTAssertEqual(engine.state.player.action, .projectile)
        XCTAssertGreaterThan(engine.state.player.actionDuration, 0)
    }

    // MARK: - FF cutscene content

    func testCoreCutscenesArePresentAndNonEmpty() {
        XCTAssertFalse(FFScript.intro.isEmpty)
        XCTAssertFalse(FFScript.beforeBoss.isEmpty)
        XCTAssertFalse(FFScript.pit.isEmpty)
        XCTAssertFalse(FFScript.midpoint.isEmpty)
        // Every panel must carry text.
        for panel in FFScript.intro + FFScript.beforeBoss + FFScript.pit {
            XCTAssertFalse(panel.text.isEmpty)
        }
    }

    func testPerFloorBeatsCoverMidFloorsButNotIntroOrBoss() {
        // Floor 1 is covered by the intro; the boss floor uses beforeBoss.
        XCTAssertNil(FFScript.chapter(.cinderGate))
        XCTAssertNil(FFScript.chapter(.millionRoom))

        // Every other floor has a one-shot beat with real text.
        for chapter in StoryChapter.allCases where chapter != .cinderGate && chapter != .millionRoom {
            let beat = FFScript.chapter(chapter)
            XCTAssertNotNil(beat, "Missing floor beat for \(chapter.title)")
            XCTAssertEqual(beat?.isEmpty, false)
            XCTAssertEqual(beat?.first?.text.isEmpty, false)
        }
    }

    // MARK: - The mechanic the Pit beat hooks onto

    func testFirstLossContinuesRunAndRefightsSameFloor() {
        var engine = WatchfighterEngine(seed: 5)   // tournament by default
        let chapterBefore = engine.state.chapter
        let roundBefore = engine.state.round

        // Force a clean opponent win, then let the round pause elapse.
        engine.debugSetPlayer(x: 0.36, health: 0, guardMeter: 0)
        engine.debugSetOpponent(x: 0.56)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.36))
        for _ in 0..<28 { engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30)) }

        XCTAssertEqual(engine.state.opponentWins, 1)
        XCTAssertEqual(engine.state.phase, .running, "one loss should not end the run")
        XCTAssertEqual(engine.state.chapter, chapterBefore, "refight the same floor")
        XCTAssertGreaterThan(engine.state.round, roundBefore)
    }
}
