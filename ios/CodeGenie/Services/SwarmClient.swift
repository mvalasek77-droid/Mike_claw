import Foundation
import Combine

/// Talks to the Genie Swarm backend (`/api/coding/swarm/*`).
///
/// Two transports:
///   • REST   — start jobs, fetch status, list workspace files.
///   • SSE    — subscribe to a job's event stream and surface every
///              agent thought, tool call, and diff to the UI.
///
/// We keep one client per BuildJob so cancellation tears the SSE down
/// cleanly when the user closes the build screen.
@MainActor
final class SwarmClient: ObservableObject {

    // MARK: - Public state

    @Published private(set) var events: [SwarmEvent] = []
    @Published private(set) var stage: BuildJob.Stage = .planning
    @Published private(set) var lastError: String?
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var jobID: String?
    /// Live pause state derived from `job.state` events. Flips to true
    /// when the backend emits `paused` and back to false on `resumed`
    /// or any subsequent normal state. Optimistic UI buttons should
    /// trust this rather than tracking their own flag.
    @Published private(set) var isPaused: Bool = false

    private let session: URLSession
    private var streamTask: Task<Void, Never>?
    private let credentials: Credentials

    init(credentials: Credentials = .shared, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    deinit { streamTask?.cancel() }

    // MARK: - REST

    func startBuild(spec: AppSpec) async throws -> String {
        var body: [String: Any] = [
            "spec": [
                "title": spec.title,
                "prompt": spec.prompt,
                "category": spec.category,
                "style": spec.style,
                "target_ios": spec.targetIOS,
                "features": spec.features
            ],
            "parallel": true,
            "skip_tests": false
        ]
        let overrides = credentials.agentModels
        if !overrides.isEmpty { body["model_overrides"] = overrides }
        if let cap = credentials.costCapUSD, cap > 0 { body["cost_cap_usd"] = cap }
        let custom = credentials.customAgents
            .filter { $0.enabled }
            .map { $0.wireForm }
        if !custom.isEmpty { body["custom_agents"] = custom }
        let response: [String: Any] = try await postJSON("/api/coding/swarm/build", body: body)
        guard let id = response["job_id"] as? String else {
            throw SwarmError.malformed("missing job_id")
        }
        jobID = id
        return id
    }

    func cancel(jobID: String) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/cancel", body: [:])
    }

    /// Pick up a cancelled or failed job from its latest checkpoint.
    /// Throws if the backend can't find the saved session.
    func resume(jobID: String) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/resume", body: [:])
    }

    /// Soft-pause the orchestrator between agents.
    func pause(jobID: String) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/pause", body: [:])
    }

    /// Release a paused orchestrator.
    func unpause(jobID: String) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/continue", body: [:])
    }

    /// Restore the workspace to a named snapshot.
    func restore(jobID: String, label: String) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/restore", body: ["label": label])
    }

    /// Fork a snapshot into a brand-new job (the original keeps
    /// running). Returns the new job id so the iOS UI can navigate to
    /// it; an optional `newTitle` overrides the spec's title.
    @discardableResult
    func fork(jobID: String, label: String, newTitle: String? = nil) async throws -> String {
        var body: [String: Any] = ["label": label]
        if let newTitle, !newTitle.isEmpty { body["title"] = newTitle }
        let response = try await postJSON("/api/coding/swarm/\(jobID)/fork", body: body)
        guard let new = response["job_id"] as? String else {
            throw SwarmError.malformed("missing job_id in fork response")
        }
        return new
    }

    /// Recent project records from the swarm's persistent memory.
    /// Pass `onlyFailed: true` to filter to failed runs (crash log).
    func recentProjects(limit: Int = 20, onlyFailed: Bool = false) async throws -> [ProjectRecord] {
        var path = "/api/coding/swarm/memory/projects?limit=\(limit)"
        if onlyFailed { path += "&only_failed=true" }
        let r: [String: Any] = try await getJSON(path)
        let entries = (r["projects"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let jobID = dict["job_id"] as? String,
                  let title = dict["title"] as? String,
                  let succeeded = dict["succeeded"] as? Bool,
                  let ts = dict["ts"] as? Double else { return nil }
            return ProjectRecord(
                jobID: jobID, title: title,
                succeeded: succeeded,
                summary: (dict["summary"] as? String) ?? "",
                at: Date(timeIntervalSince1970: ts)
            )
        }
    }

    /// Reasoning decisions the swarm logged for a specific job — used
    /// when the user taps a crash-log row to see what was happening
    /// when the build went sideways.
    func decisions(jobID: String) async throws -> [DecisionRecord] {
        let r: [String: Any] = try await getJSON("/api/coding/swarm/memory/decisions/\(jobID)")
        let entries = (r["decisions"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let context = dict["context"] as? String,
                  let decision = dict["decision"] as? String,
                  let ts = dict["ts"] as? Double else { return nil }
            return DecisionRecord(
                context: context, decision: decision,
                at: Date(timeIntervalSince1970: ts)
            )
        }
    }

    func files(jobID: String) async throws -> [String] {
        let r: [String: Any] = try await getJSON("/api/coding/swarm/\(jobID)/files")
        return (r["files"] as? [String]) ?? []
    }

    func file(jobID: String, path: String) async throws -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let r: [String: Any] = try await getJSON("/api/coding/swarm/\(jobID)/file?path=\(encoded)")
        return (r["body"] as? String) ?? ""
    }

    /// Submit accept/reject decisions for proposed file changes.
    func postDecisions(jobID: String, body: [String: Any]) async throws -> [String: Any] {
        try await postJSON("/api/coding/swarm/\(jobID)/decisions", body: body)
    }

    /// Capture a manual checkpoint of the workspace so the user can
    /// roll back to it later. Returns the snapshot's label.
    @discardableResult
    func snapshot(jobID: String, label: String? = nil) async throws -> String {
        var body: [String: Any] = [:]
        if let label { body["label"] = label }
        let response = try await postJSON("/api/coding/swarm/\(jobID)/snapshot", body: body)
        return (response["label"] as? String) ?? "snapshot"
    }

    /// List all snapshots for a job (orchestrator-internal + manual).
    func listSnapshots(jobID: String) async throws -> [SnapshotSummary] {
        let r: [String: Any] = try await getJSON("/api/coding/swarm/\(jobID)/snapshots")
        let entries = (r["snapshots"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let label = dict["label"] as? String else { return nil }
            return SnapshotSummary(
                label: label,
                at: Date(timeIntervalSince1970: (dict["at"] as? Double) ?? 0),
                files: dict["files"] as? Int ?? 0
            )
        }
    }

    /// Promote a green build to TestFlight without rebuilding.
    func ship(jobID: String, config: ShipConfig) async throws {
        var body: [String: Any] = [
            "ipa_path": config.ipaPath,
            "bundle_id": config.bundleID,
            "poll_after_upload": config.pollAfterUpload,
        ]
        if let v = config.appleID { body["apple_id"] = v }
        if let v = config.appSpecificPassword { body["app_specific_password"] = v }
        if let v = config.ascKeyID { body["asc_api_key_id"] = v }
        if let v = config.ascIssuerID { body["asc_api_issuer_id"] = v }
        if let v = config.ascKeyPath { body["asc_api_key_path"] = v }
        _ = try await postJSON("/api/coding/swarm/\(jobID)/ship", body: body)
    }

    /// URL the iOS share sheet can hand off so the user can save the
    /// generated workspace as a zip. We add the auth token via a
    /// query parameter so `URL` can be passed straight to `ShareLink`.
    func exportURL(jobID: String) -> URL? {
        var components = URLComponents(string: credentials.backendURL + "/api/coding/swarm/\(jobID)/export")
        if !credentials.backendToken.isEmpty {
            components?.queryItems = [URLQueryItem(name: "token", value: credentials.backendToken)]
        }
        return components?.url
    }

    // MARK: - SSE

    /// Subscribe to a job's event stream. Calls `onEvent` for every parsed
    /// `SwarmEvent`. Emits structured updates into `events`/`stage` for
    /// SwiftUI bindings.
    func openStream(jobID: String, onEvent: ((SwarmEvent) -> Void)? = nil) {
        streamTask?.cancel()
        self.jobID = jobID
        events.removeAll()
        isConnected = false

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.consumeStream(jobID: jobID, onEvent: onEvent)
            } catch is CancellationError {
                // expected on teardown
            } catch {
                await MainActor.run {
                    self.lastError = "\(error)"
                    self.isConnected = false
                }
            }
        }
    }

    func closeStream() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    // MARK: - Internals

    private func consumeStream(jobID: String, onEvent: ((SwarmEvent) -> Void)?) async throws {
        guard let url = URL(string: credentials.backendURL + "/api/coding/swarm/\(jobID)/stream") else {
            throw SwarmError.malformed("invalid backend URL")
        }
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SwarmError.http(response: response)
        }
        await MainActor.run { self.isConnected = true; self.lastError = nil }

        // Naive SSE parser — sufficient for our event format.
        var pendingData: String = ""
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            if line.isEmpty {
                if !pendingData.isEmpty,
                   let event = decodeEvent(pendingData) {
                    await ingest(event, forward: onEvent)
                }
                pendingData = ""
                continue
            }
            if line.hasPrefix("data: ") {
                pendingData += String(line.dropFirst(6))
            }
            // We ignore "event:" / "id:" / "retry:" — the type lives inside the JSON.
        }
    }

    private func ingest(_ event: SwarmEvent, forward: ((SwarmEvent) -> Void)?) async {
        events.append(event)
        if event.type == "job.state",
           let s = event.payload["state"] as? String {
            // Pause / resume are surfaced as job.state changes too —
            // map them to isPaused so the header badge can react.
            switch s {
            case "paused":  isPaused = true
            case "resumed": isPaused = false
            default:
                isPaused = false
                if let mapped = mapState(s) { stage = mapped }
            }
        }
        forward?(event)
    }

    private func mapState(_ s: String) -> BuildJob.Stage? {
        switch s {
        case "queued", "planning":     .planning
        case "building":               .generatingUI
        case "testing":                .linting
        case "reviewing":              .linting
        case "succeeded":              .readyForTest
        case "failed":                 .failed
        default:                       nil
        }
    }

    private func decodeEvent(_ json: String) -> SwarmEvent? {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return SwarmEvent(
            type: (raw["type"] as? String) ?? "log",
            ts: (raw["ts"] as? Double) ?? 0,
            jobID: (raw["job_id"] as? String) ?? "",
            agent: raw["agent"] as? String,
            payload: (raw["payload"] as? [String: Any]) ?? [:]
        )
    }

    // MARK: - HTTP helpers

    private func postJSON(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else { throw SwarmError.malformed("bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SwarmError.http(response: response)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func getJSON(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: credentials.backendURL + path) else { throw SwarmError.malformed("bad url") }
        var req = URLRequest(url: url)
        if !credentials.backendToken.isEmpty {
            req.setValue("Bearer \(credentials.backendToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SwarmError.http(response: response)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

// MARK: - Wire types

/// Mirror of the backend's Pydantic `SwarmEvent`. We keep the iOS copy
/// here (rather than in Models/) because it's intentionally untyped on
/// `payload` — different event types ship different shapes.
struct SnapshotSummary: Identifiable, Hashable {
    let label: String
    let at: Date
    let files: Int
    var id: String { label }
}

struct ProjectRecord: Identifiable, Hashable {
    let jobID: String
    let title: String
    let succeeded: Bool
    let summary: String
    let at: Date
    var id: String { jobID }
}

struct DecisionRecord: Identifiable, Hashable {
    let context: String
    let decision: String
    let at: Date
    var id: String { "\(context)|\(decision)|\(at.timeIntervalSince1970)" }
}

struct SwarmEvent: Identifiable {
    let id = UUID()
    let type: String
    let ts: Double
    let jobID: String
    let agent: String?
    let payload: [String: Any]
}

struct AppSpec: Hashable {
    var title: String
    var prompt: String
    var category: String = "utility"
    var style: String = "liquidGlass"
    var targetIOS: String = "17.0"
    var features: [String] = []
}

extension AppSpec {
    init(_ description: AppDescription) {
        self.init(
            title: description.title,
            prompt: description.prompt,
            category: description.category.rawValue,
            style: description.style.rawValue,
            features: description.features
        )
    }
}

enum SwarmError: Error, CustomStringConvertible {
    case malformed(String)
    case http(response: URLResponse)

    var description: String {
        switch self {
        case .malformed(let m): "malformed: \(m)"
        case .http(let r):
            if let h = r as? HTTPURLResponse { "HTTP \(h.statusCode)" } else { "HTTP error" }
        }
    }
}

/// Mirror of the backend's ShipRequest. Keeps iOS-facing names camel-cased.
struct ShipConfig: Hashable {
    var ipaPath: String
    var bundleID: String
    var appleID: String? = nil
    var appSpecificPassword: String? = nil
    var ascKeyID: String? = nil
    var ascIssuerID: String? = nil
    var ascKeyPath: String? = nil
    var pollAfterUpload: Bool = true

    /// Build a `ShipConfig` from the user's saved Apple Developer
    /// credentials. Returns nil when none are configured — the caller
    /// should prompt the user to open Apple Developer setup.
    @MainActor
    static func fromCredentials(
        ipaPath: String = "Build.ipa",
        bundleID: String,
        keyPath: String = "asc-key.p8",
        credentials: Credentials = .shared
    ) -> ShipConfig? {
        guard credentials.hasAppleDevCreds else { return nil }
        var config = ShipConfig(ipaPath: ipaPath, bundleID: bundleID)
        if !credentials.ascKeyID.isEmpty {
            config.ascKeyID = credentials.ascKeyID
            config.ascIssuerID = credentials.ascIssuerID
            config.ascKeyPath = keyPath
        }
        if !credentials.appSpecificPassword.isEmpty {
            config.appSpecificPassword = credentials.appSpecificPassword
        }
        return config
    }
}
