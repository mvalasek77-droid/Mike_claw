import SwiftUI
import Combine

/// Persisted pointer to the last backend build the user started. Lives
/// in UserDefaults (no secrets — the token stays in Keychain) so a
/// force-quit, crash, or phone restart doesn't orphan a build that is
/// still running server-side. HomeView reads this to offer
/// "Pick up where you left off".
struct ResumeRecord: Codable, Equatable {
    let backendID: String
    let description: AppDescription
    let startedAt: Date
}

@MainActor
final class AppSession: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var currentJob: BuildJob?
    @Published var recentJobs: [BuildJob] = []
    @Published var pendingPreview: BuildJob?
    @Published var pendingASC: BuildJob?
    /// Backend id we should attach to when the cover opens for
    /// `currentJob`. Cleared on dismiss so a subsequent fresh build
    /// doesn't accidentally attach.
    @Published var currentJobBackendID: String?
    /// The last interrupted backend build, if any. Survives app
    /// restarts; cleared when that build goes green or the user
    /// dismisses the callout.
    @Published private(set) var pendingResume: ResumeRecord?

    private static let resumeKey = "build.resume.record"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.resumeKey),
           let record = try? JSONDecoder().decode(ResumeRecord.self, from: data) {
            pendingResume = record
        }
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
        recentJobs.insert(forked, at: 0)
        Haptics.success()
    }

    /// Backend job id (string) for an in-app BuildJob. Used so the
    /// Apps tab and BuildScreen can pick up a forked or imported job.
    @Published private(set) var backendJobIDs: [UUID: String] = [:]

    /// Record that `job` is running as `backendID` on the swarm. Called
    /// by BuildScreen the moment `startBuild` returns, so leaving the
    /// screen (or the app dying) never loses the handle to a build
    /// that's still burning tokens server-side.
    func registerBackendJob(_ backendID: String, for job: BuildJob) {
        backendJobIDs[job.id] = backendID
        let record = ResumeRecord(backendID: backendID, description: job.description, startedAt: job.startedAt)
        pendingResume = record
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.resumeKey)
        }
    }

    /// Forget the interrupted-build record — the build went green, or
    /// the user explicitly dismissed the callout.
    func clearResumeRecord() {
        pendingResume = nil
        UserDefaults.standard.removeObject(forKey: Self.resumeKey)
    }

    /// Reopen the interrupted build: attach to its SSE stream without
    /// starting (or paying for) a new one.
    func resumePendingBuild() {
        guard let record = pendingResume else { return }
        let job = BuildJob(description: record.description, stage: .planning, startedAt: record.startedAt)
        backendJobIDs[job.id] = record.backendID
        openJob(job, backendID: record.backendID)
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
