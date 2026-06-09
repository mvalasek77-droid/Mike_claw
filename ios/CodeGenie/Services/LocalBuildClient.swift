import Foundation

/// Lightweight client that wraps CompanionBridge's build commands
/// with async/await, including polling for status updates.
///
/// Usage:
///   let client = LocalBuildClient(bridge: bridge)
///   let result = try await client.startBuild(spec: spec)
///   for try await status in client.pollStatus(jobID: result.jobID) { … }
@MainActor
final class LocalBuildClient {
    private let bridge: CompanionBridge

    /// How long to wait between status polls.
    var pollInterval: TimeInterval = 2.0

    init(bridge: CompanionBridge) {
        self.bridge = bridge
    }

    // MARK: - Start build

    /// Start a build on the paired Mac via CompanionBridge.
    /// Returns the initial BuildResult with job_id, project_path, and status.
    func startBuild(spec: AppSpec) async throws -> BuildResult {
        try await bridge.startBuild(spec: spec)
    }

    // MARK: - Poll status

    /// Async sequence that polls build status until the build reaches
    /// a terminal state (succeeded, failed) or an error occurs.
    func pollStatus(jobID: String) -> AsyncBuildStatusSequence {
        AsyncBuildStatusSequence(client: self, jobID: jobID)
    }

    /// Single status check — returns immediately.
    func checkStatus(jobID: String) async throws -> BuildStatusResult {
        try await bridge.buildStatus(jobID: jobID)
    }

    // MARK: - Push to GitHub

    /// Push the completed project to GitHub via the paired Mac.
    func pushToGithub(jobID: String, repoURL: String, branch: String, commitMessage: String, token: String? = nil) async throws -> GithubPushResult {
        try await bridge.pushToGithub(jobID: jobID, repoURL: repoURL, branch: branch, commitMessage: commitMessage, token: token)
    }

    // MARK: - Open in Xcode

    /// Ask the paired Mac to open the project in Xcode.
    func openInXcode(projectPath: String) async throws {
        try await bridge.openXcodeProject(projectPath)
    }

    // MARK: - Convenience: run build to completion

    /// Start a build and poll until it reaches a terminal state.
    /// Calls `onStage` for each status update so the UI can animate progress.
    func runBuildToCompletion(
        spec: AppSpec,
        onStage: @escaping @MainActor (BuildJob.Stage) -> Void
    ) async throws -> LocalBuildResult {
        let result = try await startBuild(spec: spec)
        var projectPath = result.projectPath

        for try await status in pollStatus(jobID: result.jobID) {
            let stage = mapStatus(status.status)
            onStage(stage)

            // Keep the latest project path (it may be empty until the build finishes)
            if !status.projectPath.isEmpty {
                projectPath = status.projectPath
            }

            // Terminal states
            if status.status == "completed" || status.status == "succeeded" || status.status == "failed" {
                return LocalBuildResult(
                    jobID: result.jobID,
                    projectPath: projectPath,
                    succeeded: status.status == "completed" || status.status == "succeeded",
                    error: status.error
                )
            }
        }

        // If the sequence ends without a terminal state, something went wrong
        return LocalBuildResult(
            jobID: result.jobID,
            projectPath: projectPath,
            succeeded: false,
            error: "Build polling ended without a terminal status"
        )
    }

    // MARK: - Status mapping

    /// Map the Claw server's status strings to the app's BuildJob.Stage.
    private func mapStatus(_ status: String) -> BuildJob.Stage {
        switch status {
        case "planning", "queued":    .planning
        case "scaffolding":           .scaffolding
        case "building":              .generatingUI
        case "generating_ui":         .generatingUI
        case "wiring_logic":          .wiringLogic
        case "wiring":                .wiringLogic
        case "linting":               .linting
        case "testing", "reviewing":  .linting
        case "building_ipa":          .buildingIPA
        case "packaging", "archiving": .buildingIPA
        case "completed", "succeeded": .readyForTest
        case "patching":               .readyForTest
        case "generating_icon":        .scaffolding
        case "running_perfection":     .perfecting
        case "generating_metadata":    .prepping
        case "taking_screenshots":     .prepping
        case "uploading_asc":          .prepping
        case "submitting":             .shipping
        case "failed":                .failed
        default:                      .planning
        }
    }
}

/// The final result of a local build.
struct LocalBuildResult {
    let jobID: String
    let projectPath: String
    let succeeded: Bool
    let error: String?
}

// MARK: - Async sequence for build status polling

struct AsyncBuildStatusSequence: AsyncSequence {
    typealias Element = BuildStatusResult
    let client: LocalBuildClient
    let jobID: String

    struct Iterator: AsyncIteratorProtocol {
        let client: LocalBuildClient
        let jobID: String
        var finished = false

        mutating func next() async throws -> BuildStatusResult? {
            guard !finished else { return nil }

            // Poll at the client's interval
            try await Task.sleep(nanoseconds: UInt64(client.pollInterval * 1_000_000_000))

            let status = try await client.checkStatus(jobID: jobID)

            // Terminal states end the sequence
            if status.status == "completed" || status.status == "succeeded" || status.status == "failed" {
                finished = true
            }

            return status
        }
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(client: client, jobID: jobID)
    }
}