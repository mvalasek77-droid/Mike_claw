import SwiftUI

/// App-wide state: the loaded model pack, the coach engine, the on-device
/// learning store, and history. Everything persists locally; nothing leaves
/// the device.
///
/// Every mutation of the learning store goes through this object. That is
/// deliberate: nested `ObservableObject`s don't propagate their changes, and
/// funnelling writes here keeps the engine's learned snapshot and the UI in
/// step without a Combine bridge.
@MainActor
final class AppState: ObservableObject {
    let pack: ModelPack
    let learning: LearningStore
    @Published private(set) var history: [CoachResult] = []
    private(set) var engine: CoachEngine

    private let historyURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        let pack = ModelPack.loadBundled()
        let learning = LearningStore(pack: pack)
        self.pack = pack
        self.learning = learning
        self.engine = CoachEngine(pack: pack, learning: learning.snapshot)
        loadHistory()
    }

    // MARK: Coaching

    /// A new session. The only place the session counter and score trend
    /// advance — re-coaching the same ramble against another model must not
    /// inflate them.
    func startSession(_ ramble: String) -> CoachResult {
        let result = engine.coach(ramble: ramble)
        write { $0.recordCoach(task: result.taskType, score: result.reportCard.score) }
        return result
    }

    /// Re-coach an existing session against a different model, keeping its
    /// identity so history updates in place rather than duplicating.
    ///
    /// A disagreement with the recommendation is the model-preference signal;
    /// re-picking the recommended model teaches nothing and is ignored.
    func recoach(_ result: CoachResult, modelID: String) -> CoachResult {
        var updated = engine.coach(ramble: result.ramble, overrideModelID: modelID)
        updated.id = result.id
        updated.date = result.date
        // Re-apply Sharpen so switching models doesn't silently throw away the
        // structure the user asked for.
        if result.isSharpened { updated = engine.sharpen(updated) }
        write { $0.recordOverride(task: result.taskType,
                                  modelID: modelID,
                                  recommendedID: result.recommendedModelID) }
        return updated
    }

    func sharpen(_ result: CoachResult) -> CoachResult {
        let out = engine.sharpen(result)
        write { $0.recordSharpen(task: result.taskType) }
        return out
    }

    /// Copying or sharing is the strongest available evidence the coached
    /// prompt was actually useful.
    func noteAccepted(_ result: CoachResult) {
        write { $0.recordAccept(task: result.taskType) }
    }

    // MARK: Learning controls

    func setLearningEnabled(_ on: Bool) { write { $0.setEnabled(on) } }
    func setMuted(_ techniqueID: String, _ muted: Bool) { write { $0.setMuted(techniqueID, muted) } }
    func resetLearning() { write { $0.reset() } }

    /// Applies a learning-store mutation, then re-reads the snapshot into the
    /// engine so the very next coaching call reflects it.
    private func write(_ change: (LearningStore) -> Void) {
        objectWillChange.send()
        change(learning)
        engine.learning = learning.snapshot
    }

    // MARK: History

    /// The number of sessions Lite keeps. Not a marketing number — small
    /// enough that "your history is limited" is felt within a normal
    /// session, which is the point of a stripped-down free tier.
    static let liteHistoryLimit = 3

    /// Upsert: replace an existing entry with the same id (e.g. after a model
    /// override re-coaches the same session) rather than duplicating it.
    func save(_ result: CoachResult) {
        if let i = history.firstIndex(where: { $0.id == result.id }) {
            history[i] = result
        } else {
            history.insert(result, at: 0)
        }
        if AppTier.isLite, history.count > Self.liteHistoryLimit {
            history.removeLast(history.count - Self.liteHistoryLimit)
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
