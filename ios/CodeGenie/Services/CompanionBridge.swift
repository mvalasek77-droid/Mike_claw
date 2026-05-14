import Foundation
import Network

/// Talks to the CodeGenie Companion daemon running on the user's Mac.
///
/// Two phases:
///  1. **Discovery.** Listen for Bonjour services advertising
///     `_codegenie-companion._tcp` on the local network and surface
///     candidates to `discovered`. The user picks one.
///  2. **Connect.** Open a Network.framework TCP connection (line-
///     delimited JSON, matching the daemon's wire format), send `auth`
///     with the paired token, then dispatch typed commands.
///
/// We deliberately avoid `URLSessionWebSocketTask` because the Mac
/// daemon ships a minimal newline-delimited JSON server (no full RFC
/// 6455 framing); using NWConnection on the iOS side keeps the wire
/// format symmetric.
@MainActor
final class CompanionBridge: ObservableObject {

    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    enum Status: Equatable {
        case idle, browsing, connecting, authenticating, connected, failed(String)
    }

    struct Discovered: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: UInt16
    }

    // MARK: - Discovery

    private var browser: NWBrowser?

    func startBrowsing() {
        status = .browsing
        let params = NWParameters(tls: nil)
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_codegenie-companion._tcp", domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(browseResults: results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel(); browser = nil
        if status == .browsing { status = .idle }
    }

    private func handle(browseResults: Set<NWBrowser.Result>) {
        var entries: [Discovered] = []
        for r in browseResults {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            entries.append(Discovered(name: name, host: name + ".local", port: 0))
        }
        // De-dupe by name; sort for stable UI.
        let unique = Array(Dictionary(grouping: entries, by: { $0.name })
            .map { _, vs in vs[0] })
            .sorted { $0.name < $1.name }
        self.discovered = unique
    }

    // MARK: - Connection

    private var conn: NWConnection?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]

    /// Connect via a paired URL of the shape
    /// `codegenie://pair?host=…&port=…&token=…`
    /// (the daemon prints this on launch; the iOS UI shows a QR scanner).
    func connect(pairingURL: URL) async {
        guard let host = pairingURL.queryItem("host"),
              let portStr = pairingURL.queryItem("port"),
              let port = UInt16(portStr),
              let token = pairingURL.queryItem("token") else {
            status = .failed("malformed pairing URL"); return
        }
        await connect(host: host, port: port, token: token)
    }

    func connect(host: String, port: UInt16, token: String) async {
        status = .connecting
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.conn = conn

        let ready = await waitForReady(conn)
        if !ready {
            status = .failed("could not reach \(host):\(port)"); return
        }

        // Persist token so the user doesn't re-pair each launch.
        Credentials.shared.setBackendToken(token)

        startReadLoop(conn)

        status = .authenticating
        do {
            _ = try await request(type: "auth", payload: ["token": token])
            status = .connected
            lastError = nil
        } catch {
            status = .failed("auth failed: \(error)")
            disconnect()
        }
    }

    func disconnect() {
        conn?.cancel(); conn = nil
        pending.values.forEach { $0.resume(throwing: BridgeError.disconnected) }
        pending.removeAll()
        if case .connected = status { status = .idle }
    }

    // MARK: - Public command shortcuts

    func openXcodeProject(_ path: String) async throws {
        _ = try await request(type: "open_xcode_project", payload: ["path": path])
    }

    func openSafari(_ url: String, newWindow: Bool = false) async throws {
        _ = try await request(type: "open_safari", payload: ["url": url, "new_window": newWindow])
    }

    func ping() async throws -> Bool {
        let r = try await request(type: "ping", payload: [:])
        return (r["pong"] as? Bool) ?? false
    }

    // MARK: - Internals

    private func request(type: String, payload: [String: Any]) async throws -> [String: Any] {
        guard let conn else { throw BridgeError.notConnected }
        let id = "msg_" + UUID().uuidString.prefix(12)
        let envelope: [String: Any] = [
            "v": 1, "id": id, "kind": "request", "type": type, "payload": payload,
        ]
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            send(conn: conn, envelope: envelope) { error in
                if let error {
                    self.pending.removeValue(forKey: id)
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func send(conn: NWConnection, envelope: [String: Any], completion: @escaping (Error?) -> Void) {
        guard var data = try? JSONSerialization.data(withJSONObject: envelope) else {
            completion(BridgeError.malformed); return
        }
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { err in completion(err) })
    }

    private func waitForReady(_ conn: NWConnection) async -> Bool {
        await withCheckedContinuation { cont in
            let gate = ContinuationGate()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() { cont.resume(returning: true) }
                case .failed, .cancelled:
                    if gate.claim() { cont.resume(returning: false) }
                default: break
                }
            }
            conn.start(queue: .main)
        }
    }

    private func startReadLoop(_ conn: NWConnection) {
        var buffer = Data()

        func tick() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
                guard let self else { return }
                if let data { buffer.append(data) }
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<nl]
                    buffer.removeSubrange(...nl)
                    if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        Task { @MainActor in self.dispatchIncoming(json) }
                    }
                }
                if isComplete {
                    Task { @MainActor in self.disconnect() }
                } else {
                    Task { @MainActor in tick() }
                }
            }
        }
        tick()
    }

    private func dispatchIncoming(_ message: [String: Any]) {
        let kind = (message["kind"] as? String) ?? ""
        guard let respondTo = message["in_response_to"] as? String else { return }

        if kind == "response" {
            let cont = pending.removeValue(forKey: respondTo)
            if (message["ok"] as? Bool) == true {
                cont?.resume(returning: (message["payload"] as? [String: Any]) ?? [:])
            } else {
                let err = (message["error"] as? String) ?? "remote error"
                cont?.resume(throwing: BridgeError.remote(err))
            }
        }
        // "event" frames are surfaced to subscribers via NotificationCenter
        // so individual screens (e.g. RemoteBuildView) can stream
        // `xcodebuild.line` events without owning the bridge directly.
        if kind == "event" {
            NotificationCenter.default.post(
                name: .companionEvent,
                object: nil,
                userInfo: message
            )
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

// MARK: - Helpers

private extension URL {
    func queryItem(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}

enum BridgeError: Error, CustomStringConvertible {
    case notConnected, disconnected, malformed, remote(String)
    var description: String {
        switch self {
        case .notConnected: "not connected"
        case .disconnected: "connection dropped"
        case .malformed:    "malformed message"
        case .remote(let m): m
        }
    }
}

extension Notification.Name {
    static let companionEvent = Notification.Name("CodeGenie.CompanionEvent")
}
