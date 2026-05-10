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

    func openPreview(for job: BuildJob) {
        currentJob = nil
        pendingPreview = job
    }

    func openAppStoreConnect(for job: BuildJob) {
        currentJob = nil
        pendingASC = job
    }
}
