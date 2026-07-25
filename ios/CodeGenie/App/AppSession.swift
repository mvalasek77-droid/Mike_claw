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

    /// Persisted record of an in-progress build so the user can resume
    /// after a crash or force-quit. Shown as a callout on Home.
    @Published var pendingResume: ResumeRecord? {
        didSet { saveResumeRecord() }
    }

    struct ResumeRecord: Codable, Identifiable {
        let backendID: String
        let description: AppDescription
        let startedAt: Date
        var id: String { backendID }
    }

    private static let resumeKey = "codegenie.pendingResume.v1"

    /// Stash for preview→build return. When the user opens a preview
    /// from the success overlay, we nil `currentJob` (dismiss
    /// BuildScreen) and save the return context here. On preview
    /// dismiss, we re-open BuildScreen attached to the same backend
    /// job so the Submit button is still reachable.
    private var returnAfterPreview: (job: BuildJob, backendID: String)?

    /// Cap on persisted jobs so a power user's gallery doesn't bloat
    /// UserDefaults or stall launch decode. ~50 is enough to scroll
    /// through months of builds without choking on disk I/O.
    private static let recentJobsCap = 50
    private static let recentJobsKey = "codegenie.recentJobs.v1"
    private static let backendIDsKey = "codegenie.backendJobIDs.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.recentJobsKey),
           let decoded = try? JSONDecoder().decode([BuildJob].self, from: data) {
            self.recentJobs = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.backendIDsKey),
           let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
            self.backendJobIDs = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.resumeKey),
           let decoded = try? JSONDecoder().decode(ResumeRecord.self, from: data) {
            self.pendingResume = decoded
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
        if let bid = currentJobBackendID {
            returnAfterPreview = (job: job, backendID: bid)
        }
        currentJob = nil
        pendingPreview = job
    }

    func returnToBuildAfterPreview() {
        guard let stash = returnAfterPreview else { return }
        returnAfterPreview = nil
        currentJobBackendID = stash.backendID
        currentJob = stash.job
    }

    func openAppStoreConnect(for job: BuildJob) {
        currentJob = nil
        pendingASC = job
    }

    // MARK: - Resume record

    func registerBackendJob(backendID: String, description: AppDescription) {
        pendingResume = ResumeRecord(
            backendID: backendID,
            description: description,
            startedAt: .now
        )
    }

    func clearResumeRecord() {
        pendingResume = nil
    }

    func resumePendingBuild() {
        guard let record = pendingResume else { return }
        let job = BuildJob(description: record.description)
        currentJobBackendID = record.backendID
        backendJobIDs[job.id] = record.backendID
        saveBackendIDs()
        currentJob = job
        Haptics.selection()
    }

    private func saveResumeRecord() {
        if let record = pendingResume,
           let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.resumeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.resumeKey)
        }
    }
}
