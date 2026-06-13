import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var currentJob: BuildJob?
    /// Created apps the user can return to from the Apps tab. Persisted to
    /// UserDefaults on every mutation; loaded in init. Without persistence
    /// the gallery resets to empty on every launch and creators can't get
    /// back to anything they built — which was the bug we were seeing.
    @Published var recentJobs: [BuildJob] = [] {
        didSet { saveJobs() }
    }
    @Published var pendingPreview: BuildJob?
    @Published var pendingASC: BuildJob?
    /// Backend id we should attach to when the cover opens for
    /// `currentJob`. Cleared on dismiss so a subsequent fresh build
    /// doesn't accidentally attach.
    @Published var currentJobBackendID: String?

    /// Cap on persisted jobs so a power user's gallery doesn't bloat
    /// UserDefaults or stall launch decode. ~50 is enough to scroll
    /// through months of builds without choking on disk I/O.
    private static let recentJobsCap = 50
    private static let recentJobsKey = "codegenie.recentJobs.v1"
    private static let backendIDsKey = "codegenie.backendJobIDs.v1"

    init() {
        // Load persisted state synchronously so the gallery is populated
        // before any view binds to it. Decode failures (e.g. after a
        // BuildJob shape change) reset rather than crash — losing the
        // gallery is recoverable; a crash loop is not.
        if let data = UserDefaults.standard.data(forKey: Self.recentJobsKey),
           let decoded = try? JSONDecoder().decode([BuildJob].self, from: data) {
            self.recentJobs = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.backendIDsKey),
           let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
            self.backendJobIDs = decoded
        }
    }

    private func saveJobs() {
        let capped = Array(recentJobs.prefix(Self.recentJobsCap))
        guard let data = try? JSONEncoder().encode(capped) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentJobsKey)
    }

    private func saveBackendIDs() {
        guard let data = try? JSONEncoder().encode(backendJobIDs) else { return }
        UserDefaults.standard.set(data, forKey: Self.backendIDsKey)
    }

    func startBuild(from description: AppDescription) -> BuildJob {
        let job = BuildJob(description: description)
        currentJob = job
        recentJobs.insert(job, at: 0)
        Haptics.selection()
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
        saveBackendIDs()
        recentJobs.insert(forked, at: 0)
        Haptics.success()
    }

    /// Backend job id (string) for an in-app BuildJob. Used so the
    /// Apps tab and BuildScreen can pick up a forked or imported job.
    @Published private(set) var backendJobIDs: [UUID: String] = [:]

    /// Record the backend's job id for a freshly-started build so the
    /// Apps tab can resume it on relaunch. Persists.
    func attachBackendJobID(_ backendID: String, to job: BuildJob) {
        backendJobIDs[job.id] = backendID
        saveBackendIDs()
    }

    /// Remove a job from the gallery (user swipe-to-delete from Apps tab).
    func deleteJob(_ job: BuildJob) {
        recentJobs.removeAll { $0.id == job.id }
        backendJobIDs[job.id] = nil
        saveBackendIDs()
    }

    /// Open an existing job in the BuildScreen. If `backendID` is set
    /// we'll attach to its SSE stream instead of starting a new build.
    func openJob(_ job: BuildJob, backendID: String? = nil) {
        currentJobBackendID = backendID
        currentJob = job
        Haptics.selection()
    }

    func startBuildAndOpen(from description: AppDescription) {
        currentJobBackendID = nil
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
}
