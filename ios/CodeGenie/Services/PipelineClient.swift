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

    struct AscIconResult: Hashable {
        let needsManualAction: Bool
        let iconUploaded: Bool
        let url: String
        let message: String
    }

    struct WhatsNewResult: Hashable {
        let ok: Bool
        let message: String
    }

    // MARK: - Beta Tester & Review models

    struct Tester: Codable, Identifiable {
        let id: String
        let email: String
        let firstName: String?
        let lastName: String?
        let state: String?
        let inviteType: String?

        enum CodingKeys: String, CodingKey {
            case id, email
            case firstName = "first_name"
            case lastName = "last_name"
            case state
            case inviteType = "invite_type"
        }
    }

    struct BetaReviewStatus: Codable {
        let betaReviewState: String
        let submittedDate: String?

        enum CodingKeys: String, CodingKey {
            case betaReviewState = "beta_review_state"
            case submittedDate = "submitted_date"
        }
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

    /// Check if the app icon has been uploaded to ASC.
    /// Returns instructions for manual Safari upload if not yet uploaded.
    func checkAscIcon() async throws -> AscIconResult {
        lastError = nil
        let r = try await postJSON("/api/asc-icon", body: ["app_id": "6778610091"])
        return AscIconResult(
            needsManualAction: (r["needs_manual_action"] as? Bool) ?? true,
            iconUploaded: (r["icon_uploaded"] as? Bool) ?? false,
            url: (r["url"] as? String) ?? "https://appstoreconnect.apple.com",
            message: (r["message"] as? String) ?? ""
        )
    }

    /// Set the "What's New" release notes for the current version in ASC.
    /// Only works after a build has been attached to the version.
    func setWhatsNew(jobID: String) async throws -> WhatsNewResult {
        lastError = nil
        let r = try await patchJSON("/api/asc-whatsnew", body: [
            "version_localization_id": "b74d4e0d-07ce-4555-983a-3905af5978e7",
            "whats_new": "Initial release of ChadDrop — AI-powered text analysis that reads between the lines."
        ])
        return WhatsNewResult(
            ok: (r["ok"] as? Bool) ?? false,
            message: (r["message"] as? String) ?? (r["error"] as? String) ?? "Unknown"
        )
    }

    // MARK: - Beta Tester & Review

    /// List all beta testers for the app.
    func listTesters() async throws -> [Tester] {
        lastError = nil
        let r = try await getJSON("/api/testers")
        guard let testersData = r["testers"] as? [[String: Any]] else {
            return []
        }
        return testersData.compactMap { dict -> Tester? in
            guard let id = dict["id"] as? String,
                  let email = dict["email"] as? String else { return nil }
            return Tester(
                id: id,
                email: email,
                firstName: dict["first_name"] as? String,
                lastName: dict["last_name"] as? String,
                state: dict["state"] as? String,
                inviteType: dict["invite_type"] as? String
            )
        }
    }

    /// Add a beta tester by email.
    func addTester(email: String, firstName: String, lastName: String) async throws -> Tester {
        lastError = nil
        var body: [String: Any] = ["email": email]
        if !firstName.isEmpty { body["first_name"] = firstName }
        if !lastName.isEmpty { body["last_name"] = lastName }
        let r = try await postJSON("/api/testers", body: body)
        guard let id = r["id"] as? String,
              let emailResp = r["email"] as? String else {
            throw PipelineError.decodingError("Missing fields in add tester response")
        }
        return Tester(
            id: id,
            email: emailResp,
            firstName: r["first_name"] as? String,
            lastName: r["last_name"] as? String,
            state: r["state"] as? String,
            inviteType: r["invite_type"] as? String
        )
    }

    /// Remove a beta tester.
    func removeTester(id: String) async throws {
        lastError = nil
        guard let url = URL(string: credentials.backendURL + "/api/testers/\(id)") else {
            throw PipelineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 204 || (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PipelineError.httpError(statusCode: statusCode)
        }
    }

    /// Assign testers to a build.
    func assignTesters(buildId: String, testerIds: [String]) async throws {
        lastError = nil
        let r = try await postJSON("/api/testers/assign-build", body: [
            "build_id": buildId,
            "tester_ids": testerIds
        ])
        // If the call succeeded, we're done. If 409, the error will be thrown by postJSON.
        _ = r
    }

    /// Submit the current build for beta review.
    func submitBetaReview(buildId: String) async throws -> BetaReviewStatus {
        lastError = nil
        let r = try await postJSON("/api/beta-review/submit", body: ["build_id": buildId])
        return BetaReviewStatus(
            betaReviewState: (r["beta_review_state"] as? String) ?? "UNKNOWN",
            submittedDate: r["submitted_date"] as? String
        )
    }

    /// Get beta review status for the current build.
    func getBetaReviewStatus(buildId: String = "") async throws -> BetaReviewStatus {
        lastError = nil
        let r = try await getJSON("/api/beta-review")
        return BetaReviewStatus(
            betaReviewState: (r["beta_review_state"] as? String) ?? "UNKNOWN",
            submittedDate: r["submitted_date"] as? String
        )
    }

    /// Set beta app review contact info.
    func setBetaReviewDetail(firstName: String, lastName: String, email: String, phone: String) async throws {
        lastError = nil
        let _ = try await postJSON("/api/beta-review/detail", body: [
            "contact_first_name": firstName,
            "contact_last_name": lastName,
            "contact_email": email,
            "contact_phone": phone
        ])
    }

    /// Create/update beta build localization (What's New for TestFlight).
    func setBetaBuildLocalization(buildId: String, locale: String, whatsNew: String) async throws {
        lastError = nil
        let _ = try await postJSON("/api/beta-review/localization", body: [
            "build_id": buildId,
            "locale": locale,
            "whats_new": whatsNew
        ])
    }

    /// Create/update beta app localization (description, feedback email).
    func setBetaAppLocalization(locale: String, feedbackEmail: String, description: String) async throws {
        lastError = nil
        var body: [String: Any] = [
            "locale": locale,
            "feedback_email": feedbackEmail
        ]
        if !description.isEmpty {
            body["description"] = description
        }
        let _ = try await postJSON("/api/beta-review/app-localization", body: body)
    }

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

    // MARK: - AI Recovery

    @Published private(set) var isSteering: Bool = false
    @Published private(set) var isRecovering: Bool = false

    /// Ask the AI steering engine to diagnose a failed pipeline step
    /// and propose a recovery action.
    ///
    /// - Parameters:
    ///   - jobID: The backend job ID.
    ///   - step: Which pipeline step failed (raw value, e.g. "archive").
    ///   - errorMessage: The error string from the failed step.
    ///   - retryCount: How many times this step has already been retried.
    /// - Returns: A `RecoveryProposal` describing what went wrong and how to fix it.
    func steer(jobID: String, step: PipelineStep, errorMessage: String, retryCount: Int = 0) async throws -> RecoveryProposal {
        isSteering = true
        defer { isSteering = false }
        lastError = nil

        let body: [String: Any] = [
            "job_id": jobID,
            "step": step.rawValue,
            "failure_mode": "unknown",  // Server will diagnose the actual failure mode
            "error_message": errorMessage,
            "retry_count": retryCount,
            "previous_errors": [] as [String]
        ]

        let r = try await postJSON("/api/build/\(jobID)/steer", body: body)

        // Decode the RecoveryProposal from the JSON response
        guard let id = r["id"] as? String,
              let stepStr = r["step"] as? String,
              let failureModeStr = r["failure_mode"] as? String,
              let actionStr = r["action"] as? String,
              let diagnosis = r["diagnosis"] as? String,
              let fixDescription = r["fix_description"] as? String else {
            throw PipelineError.decodingError("Missing required fields in steer response")
        }

        let failureMode = FailureMode(rawValue: failureModeStr) ?? .unknown
        let action = RecoveryAction(rawValue: actionStr) ?? .manualIntervention
        let fixParams = (r["fix_params"] as? [String: String]) ?? [:]
        let confidence = (r["confidence"] as? Double) ?? 0.0
        let requiresHumanAction = (r["requires_human_action"] as? Bool) ?? false
        let humanActionDescription = r["human_action_description"] as? String
        let autoFix = (r["auto_fix"] as? Bool) ?? false

        return RecoveryProposal(
            id: id,
            jobID: r["job_id"] as? String ?? jobID,
            step: stepStr,
            failureMode: failureMode,
            action: action,
            diagnosis: diagnosis,
            fixDescription: fixDescription,
            fixParams: fixParams,
            confidence: confidence,
            requiresHumanAction: requiresHumanAction,
            humanActionDescription: humanActionDescription,
            autoFix: autoFix
        )
    }

    /// Apply a recovery action approved by the user and retry the step.
    ///
    /// - Parameters:
    ///   - jobID: The backend job ID.
    ///   - proposal: The recovery proposal the user approved (possibly with
    ///     modified `fixParams` if they edited them).
    /// - Returns: A `RecoveryResult` indicating whether the fix was applied
    ///   and which step is being retried.
    func recover(jobID: String, proposal: RecoveryProposal) async throws -> RecoveryResult {
        isRecovering = true
        defer { isRecovering = false }
        lastError = nil

        let request = RecoveryRequest(
            jobID: jobID,
            step: proposal.step,
            proposalID: proposal.id,
            action: proposal.action,
            fixParams: proposal.fixParams
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)

        let r = try await postJSONData("/api/build/\(jobID)/recover", bodyData: data)

        return RecoveryResult(
            ok: (r["ok"] as? Bool) ?? false,
            stepRetrying: r["step_retrying"] as? String,
            message: (r["message"] as? String) ?? "Recovery applied"
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

    /// PATCH JSON and return the parsed response dictionary.
    /// Used by `setWhatsNew()` and other PATCH endpoints.
    private func patchJSON(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else {
            throw PipelineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // For PATCH errors, try to parse the error body for a useful message
            if let http = response as? HTTPURLResponse,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return body
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PipelineError.httpError(statusCode: statusCode)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// POST pre-encoded JSON data and return the parsed response dictionary.
    /// Used by `recover()` which encodes a `Codable` request struct.
    private func postJSONData(_ path: String, bodyData: Data) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else {
            throw PipelineError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyData

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
    case decodingError(String)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .httpError(let code): return "HTTP error \(code)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        }
    }
}