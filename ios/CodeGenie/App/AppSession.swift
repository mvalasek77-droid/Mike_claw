import SwiftUI
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published var colorScheme: ColorScheme? = nil
    @Published var currentJob: BuildJob?
    @Published var recentJobs: [BuildJob] = []
    @Published var pendingPreview: BuildJob?
    @Published var pendingASC: BuildJob?

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

    func openPreview(for job: BuildJob) {
        currentJob = nil
        pendingPreview = job
    }

    func openAppStoreConnect(for job: BuildJob) {
        currentJob = nil
        pendingASC = job
    }
}
