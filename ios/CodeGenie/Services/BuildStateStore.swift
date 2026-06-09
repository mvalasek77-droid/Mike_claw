import Foundation

/// Persists in-progress build state so the user can resume after the app
/// is killed or backgrounded. Uses a lightweight JSON file in the app's
/// Application Support directory — UserDefaults would work for small
/// payloads but a JSON file scales better with transcript logs.
///
/// Lifecycle:
///   1. User starts a build → `save(activeJob:backendID:log:)` is called
///   2. App is backgrounded/killed → state is already on disk
///   3. User reopens the app → `AppSession` checks `hasActiveBuild`
///      and auto-navigates to BuildScreen with `attachToBackendID`
///   4. Build completes or user cancels → `clear()` removes the file
final class BuildStateStore {
    static let shared = BuildStateStore()

    private let fileManager = FileManager.default
    private let stateFilename = "active_build_state.json"

    private var stateURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CodeGenie", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(stateFilename)
    }

    // MARK: - Types

    struct ActiveBuildState: Codable {
        let job: BuildJobSnapshot
        let backendID: String?
        /// Last few log lines (capped at 50) so the transcript isn't empty on restore.
        let recentLogLines: [String]
        /// When the state was saved (for staleness checks)
        let savedAt: Date

        enum CodingKeys: String, CodingKey {
            case job, backendID, recentLogLines, savedAt
        }

        init(job: BuildJobSnapshot, backendID: String?, recentLogLines: [String], savedAt: Date) {
            self.job = job; self.backendID = backendID
            self.recentLogLines = recentLogLines; self.savedAt = savedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            job = try c.decode(BuildJobSnapshot.self, forKey: .job)
            backendID = try c.decodeIfPresent(String.self, forKey: .backendID)
            recentLogLines = try c.decode([String].self, forKey: .recentLogLines)
            savedAt = try c.decode(Date.self, forKey: .savedAt)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(job, forKey: .job)
            try c.encodeIfPresent(backendID, forKey: .backendID)
            try c.encode(recentLogLines, forKey: .recentLogLines)
            try c.encode(savedAt, forKey: .savedAt)
        }

        var isStale: Bool {
            // Don't offer to resume builds older than 24 hours
            Date().timeIntervalSince(savedAt) > 86400
        }
    }

    /// A Codable snapshot of BuildJob. We don't make BuildJob itself
    /// Codable because it's a value type used everywhere and adding
    /// Codable would force all dependents to conform. Instead, we
    /// convert to/from this lightweight struct at the boundary.
    struct BuildJobSnapshot: Codable {
        let id: String
        let title: String
        let prompt: String
        let category: String
        let style: String
        let features: [String]
        let stage: String
        let startedAt: Date
        let finishedAt: Date?

        init(from job: BuildJob) {
            self.id = job.id.uuidString
            self.title = job.description.title
            self.prompt = job.description.prompt
            self.category = job.description.category.rawValue
            self.style = job.description.style.rawValue
            self.features = job.description.features
            self.stage = job.stage.rawValue
            self.startedAt = job.startedAt
            self.finishedAt = job.finishedAt
        }

        func toBuildJob() -> BuildJob? {
            guard let uuid = UUID(uuidString: id),
                  let cat = AppDescription.Category(rawValue: category),
                  let sty = AppDescription.Style(rawValue: style),
                  let stg = BuildJob.Stage(rawValue: stage) else { return nil }

            let desc = AppDescription(
                id: uuid,
                title: title,
                prompt: prompt,
                category: cat,
                style: sty,
                features: features
            )
            var job = BuildJob(id: uuid, description: desc, stage: stg, startedAt: startedAt)
            job.finishedAt = finishedAt
            return job
        }
    }

    // MARK: - Public API

    /// Whether there's an active (non-completed, non-failed) build on disk.
    var hasActiveBuild: Bool {
        guard let state = load() else { return false }
        // Completed or failed builds are not "active"
        if state.job.stage == BuildJob.Stage.readyForTest.rawValue ||
            state.job.stage == BuildJob.Stage.shipping.rawValue ||
            state.job.stage == BuildJob.Stage.failed.rawValue {
            return false
        }
        // Don't resume stale builds
        return !state.isStale
    }

    /// The current persisted state, if any.
    var activeState: ActiveBuildState? {
        load()
    }

    /// Save the current build state. Called whenever the build stage changes
    /// or periodically during long-running builds.
    func save(job: BuildJob, backendID: String?, logLines: [String] = []) {
        let snapshot = BuildJobSnapshot(from: job)
        // Cap log lines to keep the file small
        let recent = Array(logLines.suffix(50))
        let state = ActiveBuildState(
            job: snapshot,
            backendID: backendID,
            recentLogLines: recent,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// Remove persisted build state. Called when a build completes,
    /// fails permanently, or the user explicitly abandons it.
    func clear() {
        try? fileManager.removeItem(at: stateURL)
    }

    // MARK: - Internal

    private func load() -> ActiveBuildState? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(ActiveBuildState.self, from: data) else {
            return nil
        }
        return state
    }
}