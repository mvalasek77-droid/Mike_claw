import Foundation
import Combine

/// The read-only view of learned preferences that the coach consults.
///
/// A plain value type on purpose: `CoachEngine` stays a deterministic struct,
/// so a test can hand it an exact snapshot instead of driving an
/// `ObservableObject` through a sequence of taps.
struct LearningSnapshot: Hashable {
    /// task raw value -> model id this user actually prefers for it.
    var preferredModelByTask: [String: String] = [:]
    /// Tasks where the tagged-section structure is offered up front.
    var autoSharpenTasks: Set<String> = []
    /// Techniques the user muted. Muting only ever *removes* a technique.
    var mutedTechniques: Set<String> = []

    static let none = LearningSnapshot()

    var isActive: Bool {
        !preferredModelByTask.isEmpty || !autoSharpenTasks.isEmpty || !mutedTechniques.isEmpty
    }
}

/// The prompt controls that adjust over time.
///
/// This is **not** a trained model and nothing is shared. It counts a handful
/// of signals from this user's own sessions, on device, and shifts a default
/// only once the pack's threshold for that signal is met. Everything it has
/// learned is listed in Settings and cleared with one tap.
///
/// The four guardrails from the pack are enforced here, not just documented:
/// learning can never emit a parameter a model rejects (it only ever removes
/// techniques), can never override a per-model suppression (suppression is
/// applied after muting in the engine), can never point at a model the pack
/// no longer ships, and never beats an explicit choice made in the moment.
@MainActor
final class LearningStore: ObservableObject {

    /// One learned adjustment, in the user's language, for the Settings list.
    struct Adaptation: Identifiable, Hashable {
        let id: String
        let title: String
        let detail: String
    }

    /// Persisted counters. Decoded field-by-field with `decodeIfPresent` so a
    /// future field can be added without wiping what this user has taught the
    /// app — the same lesson the `sharpened` history bug taught us.
    struct Record: Codable {
        var enabled: Bool = true
        var coached: [String: Int] = [:]              // task -> sessions
        var overrides: [String: [String: Int]] = [:]  // task -> model -> picks
        var sharpened: [String: Int] = [:]            // task -> sharpen taps
        var accepted: [String: Int] = [:]             // task -> copied/shared
        var scores: [Int] = []                        // raw-ramble scores, oldest first
        var muted: [String] = []                      // technique ids

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            coached   = try c.decodeIfPresent([String: Int].self, forKey: .coached) ?? [:]
            overrides = try c.decodeIfPresent([String: [String: Int]].self, forKey: .overrides) ?? [:]
            sharpened = try c.decodeIfPresent([String: Int].self, forKey: .sharpened) ?? [:]
            accepted  = try c.decodeIfPresent([String: Int].self, forKey: .accepted) ?? [:]
            scores    = try c.decodeIfPresent([Int].self, forKey: .scores) ?? []
            muted     = try c.decodeIfPresent([String].self, forKey: .muted) ?? []
        }
    }

    /// Keeps the trend window bounded so the file can't grow without limit.
    private static let maxScores = 100

    @Published private(set) var record = Record()

    private let pack: ModelPack
    private let url: URL

    init(pack: ModelPack,
         url: URL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("learning.json")) {
        self.pack = pack
        self.url = url
        load()
    }

    private var spec: SelfLearning? { pack.selfLearning }

    var isSupported: Bool { spec != nil }

    var isEnabled: Bool { record.enabled }

    func setEnabled(_ on: Bool) {
        record.enabled = on
        persist()
    }

    // MARK: Signals in

    func recordCoach(task: String, score: Int) {
        record.coached[task, default: 0] += 1
        record.scores.append(min(100, max(0, score)))
        if record.scores.count > Self.maxScores {
            record.scores.removeFirst(record.scores.count - Self.maxScores)
        }
        persist()
    }

    /// Only a *disagreement* is a signal — picking the model that was already
    /// recommended teaches nothing.
    func recordOverride(task: String, modelID: String, recommendedID: String) {
        guard modelID != recommendedID else { return }
        record.overrides[task, default: [:]][modelID, default: 0] += 1
        persist()
    }

    func recordSharpen(task: String) {
        record.sharpened[task, default: 0] += 1
        persist()
    }

    /// Copying or sharing the coached prompt is the strongest available
    /// evidence that it was actually useful.
    func recordAccept(task: String) {
        record.accepted[task, default: 0] += 1
        persist()
    }

    // MARK: Muting

    func isMuted(_ techniqueID: String) -> Bool { record.muted.contains(techniqueID) }

    func setMuted(_ techniqueID: String, _ muted: Bool) {
        if muted {
            guard !record.muted.contains(techniqueID) else { return }
            record.muted.append(techniqueID)
        } else {
            record.muted.removeAll { $0 == techniqueID }
        }
        persist()
    }

    // MARK: Learned state out

    var snapshot: LearningSnapshot {
        guard record.enabled, let spec else { return .none }
        var snap = LearningSnapshot()

        // model_override — a task's default shifts to the model this user
        // keeps reaching for instead. Guardrail: never point at a model the
        // pack no longer ships.
        let overrideThreshold = spec.threshold("model_override")
        for (task, counts) in record.overrides {
            guard let top = counts.max(by: { $0.value < $1.value }),
                  top.value >= overrideThreshold,
                  pack.model(id: top.key) != nil else { continue }
            snap.preferredModelByTask[task] = top.key
        }

        // sharpen_rate — offer the structure up front once sharpening is both
        // frequent enough and the majority behaviour for that task.
        let sharpenThreshold = spec.threshold("sharpen_rate")
        for (task, taps) in record.sharpened where taps >= sharpenThreshold {
            let total = record.coached[task] ?? 0
            guard total > 0, Double(taps) / Double(total) > 0.5 else { continue }
            snap.autoSharpenTasks.insert(task)
        }

        // technique_mute — only techniques the pack actually defines, so a
        // stale mute from an older pack can't silently suppress nothing.
        if record.muted.count >= spec.threshold("technique_mute") {
            snap.mutedTechniques = Set(record.muted.filter { pack.technique(id: $0) != nil })
        }

        return snap
    }

    /// Tasks where the coached prompt is usually *not* used — a signal that
    /// the playbook needs review. Surfaced as a nudge, never as a silent
    /// behaviour change.
    var lowAcceptanceTasks: [String] {
        guard record.enabled, let spec else { return [] }
        let threshold = spec.threshold("acceptance")
        return record.coached.compactMap { task, total -> String? in
            guard total >= threshold else { return nil }
            let accepted = record.accepted[task] ?? 0
            return Double(accepted) / Double(total) < 0.5 ? task : nil
        }
        .sorted()
    }

    /// Earlier-half vs recent-half average of the *raw ramble* score. If this
    /// climbs, the user is internalising the techniques — which is the point.
    var scoreTrend: (earlier: Int, recent: Int, samples: Int)? {
        guard let spec else { return nil }
        let scores = record.scores
        guard scores.count >= spec.threshold("score_trend") else { return nil }
        let split = scores.count / 2
        let earlier = Array(scores.prefix(split))
        let recent = Array(scores.suffix(scores.count - split))
        guard !earlier.isEmpty, !recent.isEmpty else { return nil }
        func mean(_ xs: [Int]) -> Int { Int((Double(xs.reduce(0, +)) / Double(xs.count)).rounded()) }
        return (mean(earlier), mean(recent), scores.count)
    }

    var totalSessions: Int { record.coached.values.reduce(0, +) }

    /// Everything the app has actually adjusted, in plain language. An empty
    /// list is the honest answer early on — the app says it is still watching
    /// rather than inventing an insight.
    var adaptations: [Adaptation] {
        guard record.enabled else { return [] }
        var out: [Adaptation] = []
        let snap = snapshot

        for (task, modelID) in snap.preferredModelByTask.sorted(by: { $0.key < $1.key }) {
            let taskLabel = TaskType(rawValue: task)?.label ?? task
            let modelName = pack.model(id: modelID)?.shortName ?? modelID
            out.append(.init(
                id: "model_override.\(task)",
                title: "\(taskLabel) now defaults to \(modelName)",
                detail: "You picked \(modelName) over the recommendation enough times that it became your default for this task. Tap any other model to override it here and now."))
        }

        for task in snap.autoSharpenTasks.sorted() {
            let taskLabel = TaskType(rawValue: task)?.label ?? task
            out.append(.init(
                id: "sharpen_rate.\(task)",
                title: "\(taskLabel) prompts arrive sharpened",
                detail: "You sharpen most \(taskLabel.lowercased()) prompts, so the tagged-section structure is applied up front instead of making you ask."))
        }

        if !snap.mutedTechniques.isEmpty {
            let names = snap.mutedTechniques
                .compactMap { pack.technique(id: $0)?.name }
                .sorted()
            out.append(.init(
                id: "technique_mute",
                title: "\(names.count) technique\(names.count == 1 ? "" : "s") muted",
                detail: names.joined(separator: ", ") + " — no longer applied or suggested."))
        }

        for task in lowAcceptanceTasks {
            let taskLabel = TaskType(rawValue: task)?.label ?? task
            out.append(.init(
                id: "acceptance.\(task)",
                title: "\(taskLabel) results are rarely used",
                detail: "You usually leave without copying these. Worth checking that playbook's techniques in the Technique library — or muting the ones that don't fit how you work."))
        }

        if let trend = scoreTrend {
            let delta = trend.recent - trend.earlier
            let phrase = delta > 2 ? "up \(delta) points" : (delta < -2 ? "down \(-delta) points" : "steady")
            out.append(.init(
                id: "score_trend",
                title: "Your raw prompts are \(phrase)",
                detail: "Across \(trend.samples) sessions: \(trend.earlier)/100 early on, \(trend.recent)/100 lately. This scores what you type *before* coaching."))
        }

        return out
    }

    // MARK: Reset

    /// Clears everything the app *inferred* and keeps what the user chose
    /// outright — the on/off switch and any muted techniques. Wiping an
    /// explicit choice under the banner of "reset learning" would be a
    /// surprise, and mutes are unmuted one at a time in the technique library.
    func reset() {
        let enabled = record.enabled
        let muted = record.muted
        record = Record()
        record.enabled = enabled
        record.muted = muted
        persist()
    }

    // MARK: Persistence (local JSON in Documents)

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Record.self, from: data) else { return }
        record = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
