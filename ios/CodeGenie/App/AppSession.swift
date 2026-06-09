import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var currentJob: BuildJob? {
        didSet { syncBuildState() }
    }
    @Published var recentJobs: [BuildJob] = [] {
        didSet { syncBuildState() }
    }
    @Published var pendingPreview: BuildJob?
    @Published var pendingASC: BuildJob?
    /// Backend id we should attach to when the cover opens for
    /// `currentJob`. Cleared on dismiss so a subsequent fresh build
    /// doesn't accidentally attach.
    @Published var currentJobBackendID: String? {
        didSet { syncBuildState() }
    }

    /// Whether we're restoring from a previously-saved build state.
    /// BuildScreen checks this to know whether to skip starting a new build
    /// (it should just attach to the existing backend stream instead).
    @Published var isResuming: Bool = false

    /// Log lines accumulated during the current build. Empty on fresh start;
    /// populated from BuildStateStore when resuming.
    @Published var resumedLogLines: [String] = []

    private var buildStateStore = BuildStateStore.shared

    func startBuild(from description: AppDescription) -> BuildJob {
        let job = BuildJob(description: description)
        currentJob = job
        currentJobBackendID = nil
        isResuming = false
        resumedLogLines = []
        recentJobs.insert(job, at: 0)
        Haptics.selection()
        // Save fresh build state immediately
        buildStateStore.save(job: job, backendID: nil, logLines: [])
        return job
    }

    /// Adopt a backend job — used after `SwarmClient.fork()` returns a
    /// new job_id. We make a shallow `BuildJob` so the Apps tab can
    /// list it; the live transcript will hydrate from the SSE stream
    /// the moment the user opens it.
    func adoptForkedJob(originalDescription source: AppDescription, newID: String, titleSuffix: String = "(fork)") {
        var copy = source
        copy.title = "\(source.title) \(titleSuffix)"
        let forked = BuildJob(id: UUID(), description: copy, stage: .planning, startedAt: .now)
        // We can't bind newID to BuildJob.id because BuildJob.id is a
        // UUID; the backend's job id is a string. The iOS layer keeps
        // its own UUID and stores the backend id in `description.prompt`
        // is not appropriate. Instead, we put the backend id in
        // a sibling map keyed by BuildJob.id so SnapshotPicker /
        // BuildScreen can resolve it.
        backendJobIDs[forked.id] = newID
        recentJobs.insert(forked, at: 0)
        Haptics.success()
    }

    /// Backend job id (string) for an in-app BuildJob. Used so the
    /// Apps tab and BuildScreen can pick up a forked or imported job.
    @Published private(set) var backendJobIDs: [UUID: String] = [:]

    /// Open an existing job in the BuildScreen. If `backendID` is set
    /// we'll attach to its SSE stream instead of starting a new build.
    func openJob(_ job: BuildJob, backendID: String? = nil) {
        currentJobBackendID = backendID
        currentJob = job
        isResuming = backendID != nil
        Haptics.selection()
    }

    func startBuildAndOpen(from description: AppDescription) {
        currentJobBackendID = nil
        isResuming = false
        resumedLogLines = []
        _ = startBuild(from: description)
    }

    func openPreview(for job: BuildJob) {
        currentJob = nil
        pendingPreview = job
    }

    func openAppStoreConnect(for job: BuildJob) {
        currentJob = nil
        pendingASC = job
    }

    /// Mark the current build as completed (success or failure) and
    /// clear the persisted state so the user isn't prompted to resume
    /// a finished build.
    func completeCurrentBuild() {
        if var job = currentJob {
            job.finishedAt = Date()
            currentJob = job
        }
        buildStateStore.clear()
    }

    /// Abandon the current build — user explicitly cancels or discards.
    func abandonCurrentBuild() {
        currentJob = nil
        currentJobBackendID = nil
        isResuming = false
        resumedLogLines = []
        buildStateStore.clear()
    }

    // MARK: - Build State Persistence

    /// Called whenever currentJob, recentJobs, or currentJobBackendID change.
    /// Saves to disk only if there's an active (in-progress) build.
    private func syncBuildState() {
        guard let job = currentJob else {
            // No active job — if there's a saved state, it should only
            // persist if the job was still in progress (not completed/failed).
            return
        }
        // Only persist in-progress builds
        let terminalStages: Set<BuildJob.Stage> = [.readyForTest, .shipping, .failed]
        if terminalStages.contains(job.stage) {
            buildStateStore.clear()
        } else {
            buildStateStore.save(job: job, backendID: currentJobBackendID)
        }
    }

    /// Check for a previously-saved build on startup. If found,
    /// restores the job and sets `isResuming = true` so BuildScreen
    /// knows to attach rather than start fresh.
    func restoreIfPossible() -> Bool {
        guard buildStateStore.hasActiveBuild,
              let state = buildStateStore.activeState,
              let job = state.job.toBuildJob() else {
            return false
        }
        currentJob = job
        currentJobBackendID = state.backendID
        isResuming = true
        resumedLogLines = state.recentLogLines
        recentJobs.insert(job, at: 0)
        Haptics.selection()
        return true
    }

    /// Update the stage of the current job (called by BuildScreen
    /// as stages progress) and persist the change.
    func updateCurrentJobStage(_ stage: BuildJob.Stage) {
        guard var job = currentJob else { return }
        job.stage = stage
        currentJob = job
    }
}