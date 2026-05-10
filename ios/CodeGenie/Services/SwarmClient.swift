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
        let body: [String: Any] = [
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

    func files(jobID: String) async throws -> [String] {
        let r: [String: Any] = try await getJSON("/api/coding/swarm/\(jobID)/files")
        return (r["files"] as? [String]) ?? []
    }

    func file(jobID: String, path: String) async throws -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let r: [String: Any] = try await getJSON("/api/coding/swarm/\(jobID)/file?path=\(encoded)")
        return (r["body"] as? String) ?? ""
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
           let s = event.payload["state"] as? String,
           let mapped = mapState(s) {
            stage = mapped
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
