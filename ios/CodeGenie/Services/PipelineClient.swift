import Foundation

/// Client for the post-build pipeline endpoints on the Claw server.
///
/// After a build succeeds (`.readyForTest`), the user can walk through
/// Phase 2–5: preview → perfection → metadata prep → App Store ship.
/// Each phase has one or more API calls that this client wraps.
@MainActor
final class PipelineClient: ObservableObject {

    // MARK: - Result types

    struct PatchResult: Hashable {
        let ok: Bool
        let filesChanged: [String]
        let message: String
    }

    struct IconResult: Hashable {
        let ok: Bool
        let iconURL: String
        let message: String
    }

    struct PerfectionResult: Hashable {
        let runID: String
        let score: Double
        let releaseGate: String
    }

    struct MetadataResult: Hashable {
        let ok: Bool
        let name: String
        let subtitle: String
        let keywords: [String]
        let description: String
        let promotionalText: String
        let privacyPolicyURL: String
        let category: String
    }

    struct ScreenshotsResult: Hashable {
        let ok: Bool
        let screenshotURLs: [String]
        let message: String
    }

    struct UploadResult: Hashable {
        let ok: Bool
        let buildNumber: String
        let uploadID: String
        let message: String
    }

    struct SubmitResult: Hashable {
        let ok: Bool
        let submissionID: String
        let status: String
        let message: String
    }

    struct AscSignInResult: Hashable {
        let jobID: String
        let status: String   // "signed_in" or "needs_sign_in"
        let appID: String?
        let appName: String?
        let bundleID: String?
        let message: String?
    }

    struct LegalPagesResult: Hashable {
        let jobID: String
        let status: String
        let privacyURL: String
        let termsURL: String
        let repoURL: String
    }

    // MARK: - State

    @Published private(set) var isPatching: Bool = false
    @Published private(set) var isGeneratingIcon: Bool = false
    @Published private(set) var isRunningPerfection: Bool = false
    @Published private(set) var isGeneratingMetadata: Bool = false
    @Published private(set) var isTakingScreenshots: Bool = false
    @Published private(set) var isUploading: Bool = false
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var isCheckingAscSignIn: Bool = false
    @Published private(set) var isGeneratingLegalPages: Bool = false
    @Published private(set) var lastError: String?

    private let credentials: Credentials
    private let session: URLSession

    init(credentials: Credentials? = nil, session: URLSession = .shared) {
        self.credentials = credentials ?? Credentials.shared
        self.session = session
    }

    // MARK: - Phase 2 – Preview & Patch

    /// Submit a bug report / patch request. The server analyses the
    /// description, edits the specified files, and returns a diff.
    func patchBuild(jobID: String, bugDescription: String, filesToEdit: [String] = []) async throws -> PatchResult {
        isPatching = true
        defer { isPatching = false }
        lastError = nil
        var body: [String: Any] = [
            "bug_description": bugDescription,
        ]
        if !filesToEdit.isEmpty { body["files_to_edit"] = filesToEdit }
        let r = try await postJSON("/api/coding/swarm/\(jobID)/patch", body: body)
        return PatchResult(
            ok: (r["ok"] as? Bool) ?? false,
            filesChanged: (r["files_changed"] as? [String]) ?? [],
            message: (r["message"] as? String) ?? "Patch applied"
        )
    }

    /// Generate an app icon from a text prompt.
    func generateIcon(jobID: String, prompt: String) async throws -> IconResult {
        isGeneratingIcon = true
        defer { isGeneratingIcon = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/icon", body: ["prompt": prompt])
        return IconResult(
            ok: (r["ok"] as? Bool) ?? false,
            iconURL: (r["icon_url"] as? String) ?? "",
            message: (r["message"] as? String) ?? "Icon generated"
        )
    }

    // MARK: - Phase 3 – Perfection

    /// Run the Perfection Matrix against the built app.
    func runPerfection(jobID: String) async throws -> PerfectionResult {
        isRunningPerfection = true
        defer { isRunningPerfection = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/perfection", body: ["probes": 10_000])
        return PerfectionResult(
            runID: (r["run_id"] as? String) ?? "",
            score: (r["score"] as? Double) ?? 0,
            releaseGate: (r["release_gate"] as? String) ?? "blocked"
        )
    }

    // MARK: - Phase 4 – Metadata Prep

    /// Ask the server to generate App Store metadata (name, subtitle,
    /// keywords, description, etc.).
    func generateMetadata(jobID: String) async throws -> MetadataResult {
        isGeneratingMetadata = true
        defer { isGeneratingMetadata = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/metadata", body: [:])
        return MetadataResult(
            ok: (r["ok"] as? Bool) ?? false,
            name: (r["name"] as? String) ?? "",
            subtitle: (r["subtitle"] as? String) ?? "",
            keywords: (r["keywords"] as? [String]) ?? [],
            description: (r["description"] as? String) ?? "",
            promotionalText: (r["promotional_text"] as? String) ?? "",
            privacyPolicyURL: (r["privacy_policy_url"] as? String) ?? "",
            category: (r["primary_category"] as? String) ?? ""
        )
    }

    /// Trigger automatic screenshot generation for the app.
    func takeScreenshots(jobID: String) async throws -> ScreenshotsResult {
        isTakingScreenshots = true
        defer { isTakingScreenshots = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/screenshots", body: [:])
        return ScreenshotsResult(
            ok: (r["ok"] as? Bool) ?? false,
            screenshotURLs: (r["screenshot_urls"] as? [String]) ?? [],
            message: (r["message"] as? String) ?? "Screenshots taken"
        )
    }

    // MARK: - Phase 5 – Ship

    /// Check if an app record exists in App Store Connect for the build's bundle ID.
    /// Returns whether the user is signed in and the app exists, or a helpful message.
    func checkAscSignIn(jobID: String) async throws -> AscSignInResult {
        isCheckingAscSignIn = true
        defer { isCheckingAscSignIn = false }
        lastError = nil
        let r = try await getJSON("/api/build/\(jobID)/asc-signin")
        return AscSignInResult(
            jobID: (r["job_id"] as? String) ?? jobID,
            status: (r["status"] as? String) ?? "needs_sign_in",
            appID: r["app_id"] as? String,
            appName: r["app_name"] as? String,
            bundleID: r["bundle_id"] as? String,
            message: r["message"] as? String
        )
    }

    /// Generate and publish privacy policy & terms of use HTML to GitHub Pages.
    func generateLegalPages(jobID: String) async throws -> LegalPagesResult {
        isGeneratingLegalPages = true
        defer { isGeneratingLegalPages = false }
        lastError = nil
        let r = try await postJSON("/api/build/\(jobID)/legal-pages", body: [:])
        return LegalPagesResult(
            jobID: (r["job_id"] as? String) ?? jobID,
            status: (r["status"] as? String) ?? "unknown",
            privacyURL: (r["privacy_url"] as? String) ?? "",
            termsURL: (r["terms_url"] as? String) ?? "",
            repoURL: (r["repo_url"] as? String) ?? ""
        )
    }

    // MARK: - Phase 5 – Ship (legacy)

    /// Upload the built IPA to App Store Connect.
    func uploadBuild(jobID: String) async throws -> UploadResult {
        isUploading = true
        defer { isUploading = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/upload", body: [:])
        return UploadResult(
            ok: (r["ok"] as? Bool) ?? false,
            buildNumber: (r["build_number"] as? String) ?? "",
            uploadID: (r["upload_id"] as? String) ?? "",
            message: (r["message"] as? String) ?? "Upload complete"
        )
    }

    /// Submit the uploaded build for App Store Review.
    func submitForReview(jobID: String) async throws -> SubmitResult {
        isSubmitting = true
        defer { isSubmitting = false }
        lastError = nil
        let r = try await postJSON("/api/coding/swarm/\(jobID)/submit", body: [:])
        return SubmitResult(
            ok: (r["ok"] as? Bool) ?? false,
            submissionID: (r["submission_id"] as? String) ?? "",
            status: (r["status"] as? String) ?? "unknown",
            message: (r["message"] as? String) ?? "Submitted"
        )
    }

    // MARK: - HTTP helpers

    private func getJSON(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else {
            throw PipelineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PipelineError.httpError(statusCode: statusCode)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func postJSON(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else {
            throw PipelineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PipelineError.httpError(statusCode: statusCode)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

enum PipelineError: Error, CustomStringConvertible {
    case invalidURL
    case httpError(statusCode: Int)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP error \(code)"
        }
    }
}