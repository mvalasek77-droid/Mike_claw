import XCTest
@testable import Watchfighter

/// Covers the resumable-run feature: snapshotting a tournament, round-tripping
/// it through storage, and restoring the engine at the top of the saved floor.
final class RunPersistenceTests: XCTestCase {

    /// An isolated defaults suite so these tests never touch real player data.
    private var defaults: UserDefaults!
    private let suiteName = "watchfighter.tests.runstore"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Snapshot round trip

    func testSnapshotCapturesLadderProgressFromState() {
        var engine = WatchfighterEngine(seed: 3)
        engine.resumeTournament(chapter: .icePalace, round: 11, playerWins: 10,
                                score: 8400, maxCombo: 9, pitActive: false)

        let snapshot = RunSnapshot(state: engine.state)

        XCTAssertEqual(snapshot.chapter, .icePalace)
        XCTAssertEqual(snapshot.round, 11)
        XCTAssertEqual(snapshot.playerWins, 10)
        XCTAssertEqual(snapshot.score, 8400)
        XCTAssertEqual(snapshot.maxCombo, 9)
        XCTAssertFalse(snapshot.pitActive)
    }

    func testSaveLoadClearRoundTrip() {
        var engine = WatchfighterEngine(seed: 3)
        engine.resumeTournament(chapter: .cageNight, round: 13, playerWins: 12,
                                score: 12_000, maxCombo: 14, pitActive: true)
        let snapshot = RunSnapshot(state: engine.state)

        XCTAssertNil(RunStore.load(from: defaults), "storage starts empty")

        RunStore.save(snapshot, to: defaults)
        XCTAssertEqual(RunStore.load(from: defaults), snapshot)

        RunStore.clear(in: defaults)
        XCTAssertNil(RunStore.load(from: defaults), "clear must remove the run")
    }

    func testCorruptStoredDataDecodesToNilRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: RunStore.storageKey)
        XCTAssertNil(RunStore.load(from: defaults))
    }

    func testChapterFallsBackWhenRawValueIsOutOfRange() {
        var engine = WatchfighterEngine(seed: 3)
        engine.resumeTournament(chapter: .cinderGate, round: 1, playerWins: 0,
                                score: 0, maxCombo: 0, pitActive: false)
        var snapshot = RunSnapshot(state: engine.state)
        snapshot.chapterRawValue = 999

        XCTAssertEqual(snapshot.chapter, .cinderGate, "an unknown floor must not crash the resume")
    }

    // MARK: - Engine resume

    func testResumeRestoresTheFloorAndItsRightfulOpponent() {
        var engine = WatchfighterEngine(seed: 9)
        engine.resumeTournament(chapter: .goldRally, round: 10, playerWins: 9,
                                score: 7200, maxCombo: 6, pitActive: false)

        XCTAssertEqual(engine.state.chapter, .goldRally)
        XCTAssertEqual(engine.state.opponent.archetype, .brass, "floor 10 belongs to Brass")
        XCTAssertEqual(engine.state.player.archetype, .kael)
        XCTAssertEqual(engine.state.playerWins, 9)
        XCTAssertEqual(engine.state.score, 7200)
        XCTAssertEqual(engine.state.phase, .running)
        XCTAssertFalse(engine.state.pitActive)
    }

    func testResumeIntoThePitFacesAbaddon() {
        var engine = WatchfighterEngine(seed: 9)
        engine.resumeTournament(chapter: .stormBridge, round: 4, playerWins: 2,
                                score: 1500, maxCombo: 4, pitActive: true)

        XCTAssertTrue(engine.state.pitActive)
        XCTAssertEqual(engine.state.opponent.archetype, .abaddon)
        XCTAssertEqual(engine.state.chapter, .stormBridge, "the Pit keeps the floor you fell from")
    }

    func testResumeGivesBothFightersFullHealthAndAFreshTimer() {
        var engine = WatchfighterEngine(seed: 9)
        engine.resumeTournament(chapter: .dragonAlley, round: 5, playerWins: 4,
                                score: 3000, maxCombo: 5, pitActive: false)

        XCTAssertEqual(engine.state.player.health, engine.state.player.maxHealth)
        XCTAssertEqual(engine.state.opponent.health, engine.state.opponent.maxHealth)
        XCTAssertGreaterThan(engine.state.roundTimer, 0)
    }

    func testResumeClampsHostileValues() {
        var engine = WatchfighterEngine(seed: 9)
        engine.resumeTournament(chapter: .cinderGate, round: -5, playerWins: 999,
                                score: -100, maxCombo: -3, pitActive: false)

        XCTAssertGreaterThanOrEqual(engine.state.round, 1)
        XCTAssertLessThanOrEqual(engine.state.playerWins, StoryChapter.allCases.count)
        XCTAssertGreaterThanOrEqual(engine.state.score, 0)
        XCTAssertGreaterThanOrEqual(engine.state.maxCombo, 0)
    }

    func testResumedRunKeepsPlayingNormally() {
        var engine = WatchfighterEngine(seed: 9)
        engine.resumeTournament(chapter: .sunPier, round: 6, playerWins: 5,
                                score: 4000, maxCombo: 5, pitActive: false)

        for _ in 0..<30 {
            engine.tick(delta: 1.0 / 30.0, input: GameInput(targetX: 0.30, attacking: true))
        }

        XCTAssertEqual(engine.state.phase, .running, "a resumed run must keep ticking")
        XCTAssertLessThan(engine.state.roundTimer, 99, "the clock must actually run")
    }
}
