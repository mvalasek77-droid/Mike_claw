import SwiftUI

/// App-wide state: the loaded model pack, the coach engine, and on-device
/// history. Everything persists locally; nothing leaves the device.
@MainActor
final class AppState: ObservableObject {
    let pack: ModelPack
    let engine: CoachEngine
    @Published private(set) var history: [CoachResult] = []

    private let historyURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        let pack = ModelPack.loadBundled()
        self.pack = pack
        self.engine = CoachEngine(pack: pack)
        loadHistory()
    }

    func coach(_ ramble: String, overrideModelID: String? = nil) -> CoachResult {
        engine.coach(ramble: ramble, overrideModelID: overrideModelID)
    }

    /// Upsert: replace an existing entry with the same id (e.g. after a model
    /// override re-coaches the same session) rather than duplicating it.
    func save(_ result: CoachResult) {
        if let i = history.firstIndex(where: { $0.id == result.id }) {
            history[i] = result
        } else {
            history.insert(result, at: 0)
        }
        persist()
    }

    func delete(_ result: CoachResult) {
        history.removeAll { $0.id == result.id }
        persist()
    }

    func clearHistory() {
        history.removeAll()
        persist()
    }

    // MARK: Persistence (local JSON in Documents)

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let decoded = try? JSONDecoder().decode([CoachResult].self, from: data) else { return }
        history = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }
}
