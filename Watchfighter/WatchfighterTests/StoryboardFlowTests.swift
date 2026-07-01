import XCTest
@testable import Watchfighter

/// The autoplay "storyboard" walk (TEST_STRATEGY.md §5, §8): drive a full
/// tournament with the AutoPlayDriver + deterministic finishers, recording every
/// scene the player passes through — intro, each floor fight, the Pit/Hell
/// second-chance loop, the blurred-secret boss beat, and the ending.
///
/// It asserts the flow is complete and soft-lock-free (every floor visited, the
/// Pit fires, the boss is reached and cleared), and prints a Markdown storyboard
/// to stdout (captured in the CI log) for review without a device.
final class StoryboardFlowTests: XCTestCase {

    func testFullTournamentStoryboardHasEverySceneAndNoSoftLock() {
        var engine = WatchfighterEngine(seed: 0xC0FFEE)
        let bot = AutoPlayDriver()

        var lines: [String] = ["# Watchfighter — autoplay storyboard", ""]
        var sceneCount = 0
        func scene(_ title: String, _ detail: String) {
            sceneCount += 1
            lines.append("\(sceneCount). **\(title)** — \(detail)")
        }

        // Opening cinematic.
        scene("INTRO", "\(FFScript.intro.count) panels · \(firstLine(FFScript.intro))")

        var visited: Set<StoryChapter> = []
        var sawPit = false
        var sawBoss = false
        var sawCombat = false

        for floor in 0..<StoryChapter.allCases.count {
            let chapter = engine.state.chapter
            let rival = engine.state.opponent.archetype
            visited.insert(chapter)

            // Live combat: let the bot fight for a beat on a THROWAWAY COPY of
            // the engine (it's a value type) so the scene has real action without
            // a bot loss derailing the deterministic full-clear walk below.
            var sample = engine
            var landedStrike = false
            for _ in 0..<24 {
                let comboBefore = sample.state.combo
                sample.tick(delta: 1.0 / 12.0, input: bot.input(for: sample.state))
                if sample.state.combo > comboBefore || !sample.state.strikes.isEmpty {
                    landedStrike = true
                }
                if sample.state.phase != .running { break }
            }
            sawCombat = sawCombat || landedStrike
            scene("FLOOR \(chapter.rawValue): \(chapter.title)",
                  "vs \(rival.displayName) (\(rival.subtitle), \(rival.combatStyle)) · \(landedStrike ? "combat live" : "approach")")

            // On floor 3, take a dive to exercise the Pit / Hell second-chance:
            // fall -> fight Abaddon in Hell -> win -> back to the same floor.
            if chapter == .stormBridge, !sawPit {
                forceOpponentWin(&engine)
                advancePastRoundPause(&engine)
                sawPit = true
                XCTAssertTrue(engine.state.pitActive, "a fall must drop into the Pit")
                XCTAssertEqual(engine.state.opponent.archetype, .abaddon, "Hell is guarded by the demon")
                scene("THE PIT (HELL)", "lost the floor · vs \(engine.state.opponent.archetype.displayName) (\(engine.state.opponent.archetype.subtitle))")
                finishRoundWithPlayerWin(&engine)      // beat the demon
                advancePastRoundPause(&engine)         // back on the floor you fell from
                XCTAssertFalse(engine.state.pitActive)
                scene("ESCAPED HELL", "back on \(engine.state.chapter.title) vs \(engine.state.opponent.archetype.displayName)")
                // Fall through and win the refought floor for real.
            }

            if rival == .titan {
                sawBoss = true
                let secret = FFScript.beforeBoss.first { $0.blurredHint != nil }
                scene("BOSS BEAT: TITUS",
                      "secret defeat sequence shown BLURRED · hidden length \(secret?.blurredHint?.count ?? 0) chars")
                finishTitanWithMillionShot(&engine)
                scene("MILLION SHOT", "the one counter lands · banner: \(engine.state.bannerText)")
            } else {
                finishRoundWithPlayerWin(&engine)
            }

            if floor < StoryChapter.allCases.count - 1 {
                advancePastRoundPause(&engine)
            }
        }

        scene("ENDING", "\(engine.state.winnerText) · cleared \(engine.state.playerWins) floors")

        // ---- Flow assertions (the real gate) ----
        XCTAssertEqual(visited.count, StoryChapter.allCases.count, "every floor must be reached")
        for chapter in StoryChapter.allCases {
            XCTAssertTrue(visited.contains(chapter), "floor \(chapter.title) was skipped")
        }
        XCTAssertTrue(sawCombat, "no floor produced live combat — fights aren't playing")
        XCTAssertTrue(sawPit, "the Pit / Hell second-chance loop never fired")
        XCTAssertTrue(sawBoss, "never reached the boss")
        XCTAssertEqual(engine.state.phase, .gameOver)
        XCTAssertEqual(engine.state.winnerText, "VICTORY")

        // Emit the storyboard for the CI log / artifact.
        let markdown = lines.joined(separator: "\n")
        print("\n========== STORYBOARD START ==========\n\(markdown)\n========== STORYBOARD END ==========\n")
        writeArtifactIfRequested(markdown)
    }

    // MARK: - Helpers

    private func firstLine(_ panels: [CutscenePanel]) -> String {
        guard let text = panels.first?.text else { return "" }
        return String(text.prefix(60))
    }

    private func writeArtifactIfRequested(_ markdown: String) {
        guard let dir = ProcessInfo.processInfo.environment["WATCHFIGHTER_ARTIFACT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("storyboard.md")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    private func finishRoundWithPlayerWin(_ engine: inout WatchfighterEngine) {
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49, health: 4)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, attacking: true))
    }

    private func finishTitanWithMillionShot(_ engine: inout WatchfighterEngine) {
        engine.debugSetPlayer(x: 0.30)
        engine.debugSetOpponent(x: 0.49)
        engine.debugPrimeMillionShotCombo()
        engine.debugChargeSpecial()
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.30, special: true))
    }

    private func forceOpponentWin(_ engine: inout WatchfighterEngine) {
        engine.debugSetPlayer(x: 0.36, health: 0, guardMeter: 0)
        engine.debugSetOpponent(x: 0.56)
        engine.tick(delta: 0.01, input: GameInput(targetX: 0.36))
    }

    private func advancePastRoundPause(_ engine: inout WatchfighterEngine) {
        for _ in 0..<28 {
            engine.tick(delta: 1.0 / 12.0, input: GameInput(targetX: 0.30))
        }
    }
}
