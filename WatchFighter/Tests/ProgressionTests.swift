import XCTest
@testable import WatchFighter_Watch_App

/// Tests for the unlock/progression system.
final class ProgressionTests: XCTestCase {

    func testStartersUnlockedOthersLocked() {
        let p = Progression()
        for id in Progression.starters { XCTAssertTrue(p.isUnlocked(id)) }
        XCTAssertFalse(p.isUnlocked("corsair"))
        XCTAssertFalse(p.isUnlocked("onyx"))
    }

    func testWinsUnlockAtMilestone() {
        var p = Progression()
        var unlockedAt2: [String] = []
        for _ in 0..<2 { unlockedAt2 = p.recordWin() }
        XCTAssertTrue(p.isUnlocked("corsair"))
        XCTAssertEqual(unlockedAt2, ["corsair"], "the 2nd win unlocks corsair")
        XCTAssertFalse(p.isUnlocked("nova"))
    }

    func testAllWinUnlocksReached() {
        var p = Progression()
        for _ in 0..<8 { _ = p.recordWin() }
        for u in Progression.winUnlocks { XCTAssertTrue(p.isUnlocked(u.id)) }
    }

    func testStoryClearUnlocksOnyx() {
        var p = Progression()
        XCTAssertFalse(p.isUnlocked("onyx"))
        let unlocked = p.clearStory()
        XCTAssertTrue(p.isUnlocked("onyx"))
        XCTAssertEqual(unlocked, ["onyx"])
        XCTAssertEqual(p.clearStory(), [], "clearing again unlocks nothing new")
    }

    func testUnlockHint() {
        let p = Progression()
        XCTAssertNil(p.unlockHint("tetsu"))
        XCTAssertEqual(p.unlockHint("corsair"), "Win 2 (0/2)")
        XCTAssertEqual(p.unlockHint("onyx"), "Clear Story")
    }

    func testCodableRoundTrip() throws {
        var p = Progression()
        _ = p.recordWin(); _ = p.clearStory()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Progression.self, from: data)
        XCTAssertEqual(p, back)
    }

    func testPerCharacterNormalsApplied() {
        // Vesper's blade gives longer normals than the shared default.
        XCTAssertGreaterThan(CharacterSpec.vesper.heavy.reach, Move.heavy.reach)
        // Marina's light is faster than the default.
        XCTAssertLessThan(CharacterSpec.marina.light.startup, Move.light.startup)
        // Flavor names resolve.
        XCTAssertEqual(CharacterSpec.titus.specialName, "Haymaker")
    }
}
