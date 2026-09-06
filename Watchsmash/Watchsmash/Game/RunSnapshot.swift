import Foundation

/// A resumable tournament run, checkpointed at floor boundaries.
///
/// Only ladder *progress* is stored — not mid-round combat state. A player who
/// backgrounds the app mid-punch comes back to the top of the floor they were
/// on, which is both fairer than restoring a half-finished exchange and far
/// less brittle than serializing every fighter/strike field.
struct RunSnapshot: Codable, Equatable, Sendable {
    var chapterRawValue: Int
    var round: Int
    var playerWins: Int
    var score: Int
    var maxCombo: Int
    var pitActive: Bool

    var chapter: StoryChapter {
        StoryChapter(rawValue: chapterRawValue) ?? .cinderGate
    }

    init(state: WatchsmashState) {
        self.chapterRawValue = state.chapter.rawValue
        self.round = state.round
        self.playerWins = state.playerWins
        self.score = state.score
        self.maxCombo = state.maxCombo
        self.pitActive = state.pitActive
    }
}

/// Persistence for the in-progress tournament. Backed by `UserDefaults` — the
/// payload is a handful of integers, so a separate file would be overkill.
enum RunStore {
    static let storageKey = "watchsmash.savedRun"

    static func save(_ snapshot: RunSnapshot, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> RunSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(RunSnapshot.self, from: data)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
