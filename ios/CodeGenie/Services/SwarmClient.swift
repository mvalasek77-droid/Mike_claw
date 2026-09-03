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
    private static let maxRetainedEvents = 1_500
    private static let streamBatchSize = 24
    private static let streamFlushInterval: TimeInterval = 1.0 / 30.0

    init(credentials: Credentials? = nil, session: URLSession = .shared) {
        self.credentials = credentials ?? Credentials.shared
        self.session = session
    }

    deinit { streamTask?.cancel() }

    // MARK: - REST

    func startBuild(spec: AppSpec) async throws -> String {
        var body: [String: Any] = [
            "spec": [
                "title": spec.title,
                // Enriched orchestrator brief. Wraps the user's raw text in
                // explicit structure (quality bar, anti-patterns, agent
                // handoffs, platform conventions) so the swarm's Claude /
                // GPT agents start from the same ground truth.
                "prompt": spec.prompt,
                // Raw, unmodified user intent. Backends that want to retry
                // with a different brief or surface the user's original
                // words in telemetry / receipts read this instead of trying
                // to un-wrap the structured prompt.
                "raw_prompt": spec.rawPrompt,
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
        if let mb = credentials.snapshotCapMB, mb > 0 {
            body["max_snapshot_bytes"] = mb * 1024 * 1024
        }
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

    /// Compare two jobs' workspaces; returns the file-tree overview.
    func compareJobs(
        jobA: String, jobB: String, includeUnchanged: Bool = false,
    ) async throws -> ProjectDiff {
        let path = "/api/coding/swarm/compare/\(jobA)/\(jobB)?include_unchanged=\(includeUnchanged ? "true" : "false")"
        let r: [String: Any] = try await getJSON(path)
        let entries = (r["files"] as? [[String: Any]]) ?? []
        let counts = (r["counts"] as? [String: Int]) ?? [:]
        return ProjectDiff(
            jobA: jobA, jobB: jobB,
            files: entries.compactMap { dict in
                guard let p = dict["path"] as? String,
                      let s = dict["status"] as? String else { return nil }
                return ProjectDiff.FileEntry(
                    path: p, status: s,
                    aSize: dict["a_size"] as? Int,
                    bSize: dict["b_size"] as? Int,
                    aSha:  dict["a_sha"]  as? String,
                    bSha:  dict["b_sha"]  as? String,
                    isTextLike: (dict["is_text_like"] as? Bool) ?? false
                )
            },
            counts: counts
        )
    }

    /// Fetch both sides of a single file for inline rendering.
    func compareFile(
        jobA: String, jobB: String, path: String,
    ) async throws -> (String?, String?) {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let url = "/api/coding/swarm/compare/\(jobA)/\(jobB)/file?path=\(encoded)"
        let r: [String: Any] = try await getJSON(url)
        return (r["a_body"] as? String, r["b_body"] as? String)
    }

    /// List currently archived job workspaces.
    func listArchives() async throws -> [ArchivedJob] {
        let r: [String: Any] = try await getJSON("/api/coding/swarm/admin/archives")
        let entries = (r["archives"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let filename = dict["filename"] as? String,
                  let jobID = dict["job_id"] as? String else { return nil }
            return ArchivedJob(
                filename: filename,
                jobID: jobID,
                archivedAt: (dict["archived_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                sizeBytes: (dict["size_bytes"] as? Int) ?? 0,
                mtime: Date(timeIntervalSince1970: (dict["mtime"] as? Double) ?? 0)
            )
        }
    }

    /// Re-extract an archived workspace back into `workspace_root`.
    /// Returns the restored job id.
    @discardableResult
    func extractArchive(filename: String) async throws -> String {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        let r: [String: Any] = try await postJSON(
            "/api/coding/swarm/admin/archives/\(encoded)/extract", body: [:]
        )
        guard let jobID = r["job_id"] as? String else {
            throw SwarmError.malformed("missing job_id in extract response")
        }
        return jobID
    }

    /// Archive job workspaces older than `days`. Returns one summary
    /// per archive. Active jobs are skipped server-side.
    func archiveOldWorkspaces(olderThanDays days: Int) async throws -> [ArchiveSummary] {
        let r = try await postJSON(
            "/api/coding/swarm/admin/archive",
            body: ["older_than_days": days],
        )
        let entries = (r["archived"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let jobID = dict["job_id"] as? String,
                  let path = dict["archive_path"] as? String else { return nil }
            return ArchiveSummary(
                jobID: jobID,
                archivePath: path,
                bytesWritten: (dict["bytes_written"] as? Int) ?? 0,
                filesArchived: (dict["files_archived"] as? Int) ?? 0
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

    /// Search reasoning decisions across every remembered build.
    func searchDecisions(query: String, limit: Int = 30) async throws -> [DecisionSearchRecord] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let r: [String: Any] = try await getJSON(
            "/api/coding/swarm/memory/decisions/search?q=\(encoded)&limit=\(limit)"
        )
        let entries = (r["decisions"] as? [[String: Any]]) ?? []
        return entries.compactMap { dict in
            guard let jobID = dict["job_id"] as? String,
                  let context = dict["context"] as? String,
                  let decision = dict["decision"] as? String,
                  let ts = dict["ts"] as? Double else { return nil }
            return DecisionSearchRecord(
                jobID: jobID, context: context, decision: decision,
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

    /// Run the zero-token Perfection Matrix: 10,000 deterministic
    /// virtual probes across Apple review, accessibility, performance,
    /// resilience, security, polish, and App Store packaging.
    func runPerfection(jobID: String, probes: Int = 10_000) async throws -> PerfectionRun {
        let r = try await postJSON(
            "/api/coding/swarm/\(jobID)/perfection",
            body: ["probes": probes]
        )
        return try PerfectionRun(json: r)
    }

    /// Audit Xcode archive, Apple credentials, privacy, terms,
    /// screenshots, metadata, GitHub, and final Apple-required
    /// confirmation before attempting TestFlight upload.
    func runReleaseReadiness(
        jobID: String,
        ship: ShipConfig? = nil,
        github: GitHubSyncConfig? = nil
    ) async throws -> ReleaseReadinessRun {
        var body: [String: Any] = [:]
        if let ship { body["ship"] = ship.wireBody }
        if let github { body["github"] = github.wireBody }
        let r = try await postJSON("/api/coding/swarm/\(jobID)/release-readiness", body: body)
        return ReleaseReadinessRun(json: r)
    }

    /// Push the generated workspace to the user's GitHub repository.
    @discardableResult
    func syncGitHub(jobID: String, config: GitHubSyncConfig) async throws -> GitHubSyncResult {
        let r = try await postJSON("/api/coding/swarm/\(jobID)/github/sync", body: config.wireBody)
        return GitHubSyncResult(json: r)
    }

    /// Promote a green build to TestFlight without rebuilding.
    func ship(jobID: String, config: ShipConfig) async throws {
        _ = try await postJSON("/api/coding/swarm/\(jobID)/ship", body: config.wireBody)
    }

    /// Ask the App Store Connect coach a question.
    ///
    /// Not scoped to a job id: a user can be stuck on Apple's console
    /// long before a build exists and long after one is archived, and
    /// those are exactly the moments they most need an answer.
    func ascCoach(body: [String: Any]) async throws -> [String: Any] {
        try await postJSON("/api/coding/swarm/asc/coach", body: body)
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

        // Buffered SSE parsing keeps large agent transcripts from invalidating
        // SwiftUI hundreds of times per second.
        var pendingData: String = ""
        var bufferedEvents: [SwarmEvent] = []
        bufferedEvents.reserveCapacity(Self.streamBatchSize)
        var lastFlush = Date()

        func flushIfNeeded(force: Bool = false) async {
            guard !bufferedEvents.isEmpty else { return }
            let elapsed = Date().timeIntervalSince(lastFlush)
            guard force || bufferedEvents.count >= Self.streamBatchSize || elapsed >= Self.streamFlushInterval else { return }
            await ingest(bufferedEvents, forward: onEvent)
            bufferedEvents.removeAll(keepingCapacity: true)
            lastFlush = Date()
        }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            if line.isEmpty {
                if !pendingData.isEmpty,
                   let event = decodeEvent(pendingData) {
                    bufferedEvents.append(event)
                    await flushIfNeeded()
                }
                pendingData = ""
                continue
            }
            if line.hasPrefix("data: ") {
                pendingData += String(line.dropFirst(6))
            }
            // We ignore "event:" / "id:" / "retry:" — the type lives inside the JSON.
        }
        await flushIfNeeded(force: true)
    }

    private func ingest(_ newEvents: [SwarmEvent], forward: ((SwarmEvent) -> Void)?) async {
        let overflow = events.count + newEvents.count - Self.maxRetainedEvents
        if overflow > 0 {
            events.removeFirst(min(overflow, events.count))
        }
        events.append(contentsOf: newEvents)

        for event in newEvents {
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

struct DecisionSearchRecord: Identifiable, Hashable {
    let jobID: String
    let context: String
    let decision: String
    let at: Date
    var id: String { "\(jobID)|\(context)|\(decision)|\(at.timeIntervalSince1970)" }
}

struct ArchiveSummary: Identifiable, Hashable {
    let jobID: String
    let archivePath: String
    let bytesWritten: Int
    let filesArchived: Int
    var id: String { archivePath }
}

struct ProjectDiff: Hashable {
    let jobA: String
    let jobB: String
    let files: [FileEntry]
    let counts: [String: Int]

    struct FileEntry: Identifiable, Hashable {
        let path: String
        let status: String   // "same" | "added" | "removed" | "modified"
        let aSize: Int?
        let bSize: Int?
        let aSha: String?
        let bSha: String?
        let isTextLike: Bool
        var id: String { path }
    }

    /// Files grouped by status for the sectioned list view.
    var grouped: [(status: String, files: [FileEntry])] {
        let order = ["modified", "added", "removed", "same"]
        var bins: [String: [FileEntry]] = [:]
        for f in files { bins[f.status, default: []].append(f) }
        return order.compactMap { s in
            guard let xs = bins[s], !xs.isEmpty else { return nil }
            return (s, xs)
        }
    }
}

struct ArchivedJob: Identifiable, Hashable {
    let filename: String
    let jobID: String
    let archivedAt: Date?
    let sizeBytes: Int
    let mtime: Date
    var id: String { filename }
}

struct PerfectionRun: Identifiable, Hashable {
    let id: String
    let probesRun: Int
    let score: Double
    let releaseGate: String
    let summary: String
    let severityCounts: [String: Int]
    let axes: [PerfectionAxis]
    let findings: [PerfectionFinding]
    let nextActions: [String]

    init(json: [String: Any]) throws {
        guard let runID = json["run_id"] as? String else {
            throw SwarmError.malformed("missing run_id")
        }
        id = runID
        probesRun = Self.int(json["probes_run"])
        score = Self.double(json["score"])
        releaseGate = (json["release_gate"] as? String) ?? "blocked"
        summary = (json["summary"] as? String) ?? "Perfection Matrix complete."
        severityCounts = Self.intMap(json["severity_counts"])
        axes = ((json["axes"] as? [[String: Any]]) ?? []).map(PerfectionAxis.init(json:))
        findings = ((json["findings"] as? [[String: Any]]) ?? []).map(PerfectionFinding.init(json:))
        nextActions = (json["next_actions"] as? [String]) ?? []
    }

    var isReady: Bool { releaseGate == "ready" }
    var gateLabel: String {
        switch releaseGate {
        case "ready": "Ready"
        case "needs_polish": "Needs polish"
        default: "Blocked"
        }
    }

    fileprivate static func int(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    fileprivate static func double(_ value: Any?) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    fileprivate static func intMap(_ value: Any?) -> [String: Int] {
        let raw = (value as? [String: Any]) ?? [:]
        return raw.reduce(into: [:]) { partial, item in
            partial[item.key] = int(item.value)
        }
    }
}

struct PerfectionAxis: Identifiable, Hashable {
    let key: String
    let title: String
    let probes: Int
    let passed: Int
    let failed: Int
    let confidence: Double
    var id: String { key }

    init(json: [String: Any]) {
        key = (json["key"] as? String) ?? UUID().uuidString
        title = (json["title"] as? String) ?? key
        probes = PerfectionRun.int(json["probes"])
        passed = PerfectionRun.int(json["passed"])
        failed = PerfectionRun.int(json["failed"])
        confidence = PerfectionRun.double(json["confidence"])
    }
}

struct PerfectionFinding: Identifiable, Hashable {
    let id = UUID()
    let severity: String
    let axis: String
    let title: String
    let body: String
    let file: String?
    let line: Int?
    let recommendation: String?

    init(json: [String: Any]) {
        severity = (json["severity"] as? String) ?? "info"
        axis = (json["axis"] as? String) ?? "engineering"
        title = (json["title"] as? String) ?? "Finding"
        body = (json["body"] as? String) ?? ""
        file = json["file"] as? String
        if let rawLine = json["line"], !(rawLine is NSNull) {
            line = PerfectionRun.int(rawLine)
        } else {
            line = nil
        }
        recommendation = json["recommendation"] as? String
    }
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
    /// The enriched brief sent to the backend swarm. Built from the user's
    /// raw description but wrapped in structure the planner/codegen agents
    /// can actually parse — see `PromptBrief.enrich` for the format.
    var prompt: String
    /// The user's raw, unenriched prompt. Surfaced separately so the backend
    /// has unmodified ground truth for telemetry, retries with a different
    /// brief, and the Apps-tab card preview without parsing the wrapper.
    var rawPrompt: String
    var category: String = "utility"
    var style: String = "liquidGlass"
    var targetIOS: String = "17.0"
    var features: [String] = []
}

extension AppSpec {
    init(_ description: AppDescription) {
        let raw = description.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            title: description.title,
            prompt: PromptBrief.enrich(
                title: description.title,
                rawPrompt: raw,
                category: description.category,
                style: description.style,
                features: description.features
            ),
            rawPrompt: raw,
            category: description.category.rawValue,
            style: description.style.rawValue,
            features: description.features
        )
    }
}

/// Build-side prompt construction. Takes a user's raw natural-language
/// description and wraps it in a richly-structured brief the backend's
/// Claude + OpenAI agents can use without re-deriving context every turn.
///
/// Design goals, hard-won from comparing what the swarm produces against
/// what it COULD produce from the same user intent:
///
///   • Frontier models (Claude 4.x, GPT-5) reliably do better when the user
///     intent is wrapped in explicit XML tags than when it's interpolated
///     into prose. The planner agent can split `<user_intent>` from
///     `<context>` cleanly; the codegen agent can lift `<target_apis>`
///     and `<style_intent>` without parsing English.
///   • Naming the quality bar ("App-Store-shippable, App-of-the-Year
///     candidate") shifts model output materially. Asking for "an iOS app"
///     yields a sample; asking for an "App-of-the-Year candidate" yields
///     something with polish, accessibility, and edge-case handling.
///   • Style and category aren't bonus context — they're MORE specific than
///     the user's prompt. Spelling them out (Liquid Glass surfaces, Apple
///     HIG, system colours) saves the agents an inference hop and reduces
///     wrong-style first drafts that have to be rewritten.
///   • An anti-failure-mode rulebook ("don't ship placeholder lorem ipsum",
///     "don't stub the persistence layer") replaces 80% of the agent
///     round-trips the orchestrator otherwise spends correcting.
enum PromptBrief {
    static func enrich(
        title: String,
        rawPrompt: String,
        category: AppDescription.Category,
        style: AppDescription.Style,
        features: [String]
    ) -> String {
        var sections: [String] = []

        sections.append("""
        You are the orchestrator brief for a swarm of frontier coding agents (Claude + GPT) that will design, scaffold, implement, and ship a complete, App-Store-shippable iOS 17+ app. Treat every section below as ground truth and propagate the relevant slices to each downstream agent in the structured form provided.
        """)

        sections.append("""
        <quality_bar>
        Target: an App-of-the-Year-class iOS app, not a tutorial sample. Every screen ships with: real data flow, accessibility labels + Dynamic Type, haptics on meaningful actions, empty / error / loading states, dark-mode polish, and edge-case handling for the obvious failure modes (no network, slow disk, missing permission, force-quit mid-task). No lorem ipsum, no `// TODO`, no placeholder strings in shipped UI, no stubbed persistence layers.
        </quality_bar>
        """)

        sections.append("""
        <app_identity>
        <title>\(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(unset — agents must propose one)" : title.trimmingCharacters(in: .whitespacesAndNewlines))</title>
        <category>\(category.rawValue)</category>
        <category_hint>\(categoryHint(category))</category_hint>
        </app_identity>
        """)

        sections.append("""
        <user_intent>
        \(rawPrompt.isEmpty ? "(empty — refuse to build; ask the user for a description.)" : rawPrompt)
        </user_intent>
        """)

        if !features.isEmpty {
            sections.append("""
            <explicit_features>
            \(features.map { "• \($0)" }.joined(separator: "\n"))
            </explicit_features>
            """)
        }

        sections.append("""
        <style_intent>
        Design language: \(style.label).
        \(styleHint(style))
        </style_intent>
        """)

        sections.append("""
        <platform_conventions>
        • SwiftUI-first. UIKit only where SwiftUI doesn't yet cover the API.
        • Targets iOS 17.0 and above; use observation, NavigationStack, .scrollTargetBehavior where they materially help.
        • Apple Human Interface Guidelines for navigation hierarchy, control sizes, gesture priorities, and dynamic type scaling.
        • Use system colours (Theme/asset catalog) and SF Symbols. No vendored icon fonts.
        • Privacy: declare every collected data type in PrivacyInfo.xcprivacy; default to no collection until justified by a user-visible feature.
        • App-Store-ready by construction: bundle id, signing entitlements, app icon slot, launch screen, accessibility labels, no debug code paths reachable in Release.
        </platform_conventions>
        """)

        sections.append("""
        <agent_handoffs>
        • Planner (Claude): emit a Mermaid-style information architecture (screens, navigation edges, top-level state owners) before code. Cite which `<explicit_features>` map to which screen.
        • Scaffolder: produce a buildable Xcode project at the FIRST commit (compiles + runs to an empty launch screen). Do not pile up source files that don't compile.
        • UI codegen (GPT for structure / Claude for polish): one screen per turn, ship-quality each time. No placeholder dummies for "later".
        • Logic codegen: real persistence (SwiftData / Core Data / Files) appropriate to the data model. No `var items: [Item] = []` singletons.
        • Linter: enforce the <anti_patterns> rules below before any review.
        • Reviewer: read the diff with a release reviewer's eye — flag accessibility gaps, missing empty states, TODO leakage, and HIG violations.
        </agent_handoffs>
        """)

        sections.append("""
        <anti_patterns>
        Reject (don't ship) any of these in generated code:
        • `// TODO`, `// FIXME`, `fatalError("not implemented")`, `print("debug...")` left over from generation.
        • Lorem ipsum or "Sample Title" strings in shipped UI.
        • In-memory-only stores when the screen visibly implies persistence.
        • Hard-coded English strings without going through a Localizable.strings table when the app targets multiple regions.
        • Synchronous network calls on the main actor; missing `await` on async APIs.
        • Force-unwrapping (`!`) outside of test code unless invariant-justified in a one-line comment.
        • Custom colours hard-coded instead of routed through the asset catalog.
        • Buttons / icons without `.accessibilityLabel(_:)` when their visible text isn't descriptive.
        </anti_patterns>
        """)

        sections.append("""
        <output_contract>
        • Every code artifact compiles standalone — no dangling imports, no references to symbols that don't exist yet.
        • Every new screen lands with: SwiftUI view, preview block, accessibility labels, and at least one snapshot-worthy state (data) plus one empty / loading state.
        • Commit messages: imperative voice, scoped to a single concern (`Add settings screen`, `Wire up onboarding state machine`), no "WIP" or "stuff".
        </output_contract>
        """)

        return sections.joined(separator: "\n\n")
    }

    private static func categoryHint(_ category: AppDescription.Category) -> String {
        switch category {
        case .utility:      return "Bite-size, single-screen-feels but multi-screen-real. Optimise for first-launch glanceability."
        case .productivity: return "Trust the user with structure: lists, filters, dates, undo. Persistence is the spine; keyboard handling matters."
        case .lifestyle:    return "Soft surfaces, gentle haptics, day/night palette. Tracks data the user revisits but doesn't crunch."
        case .finance:      return "Precision over flourish: tabular data, currencies, decimals, totals that always reconcile. Conservative animation."
        case .social:       return "Optimistic UI on send; latency-tolerant retries; report/block plumbing wired by default. Identity model up front."
        case .health:       return "HealthKit integration where it earns its place; permissions framed in user-benefit copy; respect privacy by default."
        case .education:    return "Progressive disclosure: every screen teaches one idea. Track progress in persistent state; celebrate milestones with restraint."
        case .games:        return "60fps interactive core; SwiftUI for chrome, SpriteKit/Metal where the game loop needs frames. Onboard fast."
        case .photo:        return "Performance-sensitive image handling: thumbnails, lazy loading, ProRes/HEIF, photo permission gating at the right moment."
        }
    }

    private static func styleHint(_ style: AppDescription.Style) -> String {
        switch style {
        case .liquidGlass: return "Glass-tier backgrounds (.ultraThinMaterial / GlassEffect on 17+), tinted strokes, depth via shadow + blur, accent-coloured highlight states. Lean into iOS 26 glassEffect on supported versions."
        case .minimal:     return "Whitespace as primary design element, single accent colour, system type only, restraint everywhere. Negative space tells the story."
        case .playful:     return "Bouncy spring animations, soft gradients, large rounded corners, expressive icons, micro-interactions that reward exploration. Restraint on text density."
        case .editorial:   return "Type-driven hierarchy with serif or refined sans display fonts; generous horizontal rhythm; image-led layouts. Treats content as the design."
        }
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
    /// Package a signed .ipa first when one doesn't exist yet. On by
    /// default: a first-time user has never heard of an archive and
    /// should not have to produce one by hand.
    var autoArchive: Bool = true
    var teamID: String = ""
    /// Blank means "work it out on the Mac" — only that machine can
    /// see what the generated project actually is.
    var scheme: String = ""
    var workspaceOrProject: String = ""
    var configuration: String = "Release"
    var exportMethod: String = "app-store-connect"

    var wireBody: [String: Any] {
        var body: [String: Any] = [
            "ipa_path": ipaPath,
            "bundle_id": bundleID,
            "poll_after_upload": pollAfterUpload,
            "auto_archive": autoArchive,
            "team_id": teamID,
            "scheme": scheme,
            "workspace_or_project": workspaceOrProject,
            "configuration": configuration,
            "export_method": exportMethod,
        ]
        if let v = appleID { body["apple_id"] = v }
        if let v = appSpecificPassword { body["app_specific_password"] = v }
        if let v = ascKeyID { body["asc_api_key_id"] = v }
        if let v = ascIssuerID { body["asc_api_issuer_id"] = v }
        if let v = ascKeyPath { body["asc_api_key_path"] = v }
        return body
    }

    /// Build a `ShipConfig` from the user's saved Apple Developer
    /// credentials. Returns nil when none are configured — the caller
    /// should prompt the user to open Apple Developer setup.
    @MainActor
    static func fromCredentials(
        ipaPath: String = "Build.ipa",
        bundleID: String,
        keyPath: String = "asc-key.p8",
        credentials: Credentials? = nil
    ) -> ShipConfig? {
        let credentials = credentials ?? Credentials.shared
        guard credentials.hasAppleDevCreds else { return nil }
        var config = ShipConfig(ipaPath: ipaPath, bundleID: bundleID)
        // The team id is what lets Xcode pick the right signing
        // identity without asking anyone anything.
        config.teamID = credentials.appleTeamID
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

struct GitHubSyncConfig: Hashable {
    var repoURL: String
    var branch: String = "codegenie-build"
    var baseBranch: String = "main"
    var commitMessage: String = "Sync CodeGenie workspace"
    var token: String? = nil
    var openPR: Bool = false
    var prTitle: String? = nil
    var prBody: String? = nil

    var wireBody: [String: Any] {
        var body: [String: Any] = [
            "repo_url": repoURL,
            "branch": branch,
            "base_branch": baseBranch,
            "commit_message": commitMessage,
            "open_pr": openPR,
        ]
        if let token, !token.isEmpty { body["token"] = token }
        if let prTitle, !prTitle.isEmpty { body["pr_title"] = prTitle }
        if let prBody, !prBody.isEmpty { body["pr_body"] = prBody }
        return body
    }
}

struct GitHubSyncResult: Hashable {
    var ok: Bool
    var branch: String
    var remote: String
    var prRequested: Bool
    var prURL: String

    init(json: [String: Any]) {
        ok = json["ok"] as? Bool ?? false
        branch = json["branch"] as? String ?? ""
        remote = json["remote"] as? String ?? ""
        prRequested = json["pr_requested"] as? Bool ?? false
        prURL = json["pr_url"] as? String ?? ""
    }
}

struct ReleaseReadinessRun: Hashable {
    var releaseGate: String
    var score: Int
    var summary: String
    var nextActions: [String]
    var items: [ReleaseReadinessItem]

    var isReadyForTestFlight: Bool { releaseGate == "ready_for_testflight" }

    init(json: [String: Any]) {
        releaseGate = json["release_gate"] as? String ?? "needs_setup"
        score = json["score"] as? Int ?? 0
        summary = json["summary"] as? String ?? ""
        nextActions = json["next_actions"] as? [String] ?? []
        items = ((json["items"] as? [[String: Any]]) ?? []).map(ReleaseReadinessItem.init(json:))
    }
}

struct ReleaseReadinessItem: Identifiable, Hashable {
    var key: String
    var title: String
    var status: String
    var detail: String
    var action: String
    var required: Bool
    var id: String { key }

    init(json: [String: Any]) {
        key = json["key"] as? String ?? UUID().uuidString
        title = json["title"] as? String ?? key
        status = json["status"] as? String ?? "needs_setup"
        detail = json["detail"] as? String ?? ""
        action = json["action"] as? String ?? ""
        required = json["required"] as? Bool ?? false
    }
}
