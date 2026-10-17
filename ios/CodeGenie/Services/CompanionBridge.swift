import Foundation
import Network
import Security

/// Talks to the CodeGenie Companion daemon running on the user's Mac.
///
/// Two phases:
///  1. **Discovery.** Listen for Bonjour services advertising
///     `_codegenie-companion._tcp` on the local network and surface
///     candidates to `discovered`. The user picks one.
///  2. **Connect.** Open a Network.framework TLS connection (line-
///     delimited JSON, matching the daemon's wire format), send `auth`
///     with the paired token, then dispatch typed commands.
///
/// We deliberately avoid `URLSessionWebSocketTask` because the Mac
/// daemon ships a minimal newline-delimited JSON server (no full RFC
/// 6455 framing); using NWConnection on the iOS side keeps the wire
/// format symmetric.
@MainActor
final class CompanionBridge: ObservableObject {

    /// Shared instance so a pairing survives the screen that made it.
    static let shared = CompanionBridge()

    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    /// True when a Mac is paired and reachable right now.
    var isConnected: Bool { status == .connected }

    enum Status: Equatable {
        case idle, browsing, connecting, authenticating, connected, failed(String)
    }

    struct Discovered: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: UInt16
    }

    private static let requestTimeout: TimeInterval = 30
    private static let reconnectMaxAttempts = 5
    private static let reconnectMaxBackoff: TimeInterval = 16

    /// SHA-256 fingerprint of the Mac daemon's self-signed TLS cert,
    /// scanned from the pairing QR code. When set, only that cert is
    /// accepted; when nil we fall back to standard system trust (which
    /// will reject self-signed certs, protecting against MITM).
    private var pinnedCertFingerprint: String?

    /// Saved pairing info for auto-reconnect.
    private var lastHost: String?
    private var lastPort: UInt16?
    private var lastToken: String?
    private var reconnectTask: Task<Void, Never>?

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
            // Resolve the port from the Bonjour result's metadata.
            var port: UInt16 = 0
            if case let .service(_, _, _, interface) = r.endpoint,
               let metadata = r.metadata,
               case let .bonjour(record) = metadata {
                // NWBrowser doesn't expose port directly — we resolve
                // via NWConnection to the endpoint. For the listing we
                // store 0 and resolve on connect.
                _ = interface // suppress unused warning
                _ = record
            }
            entries.append(Discovered(name: name, host: name + ".local", port: port))
        }
        let unique = Array(Dictionary(grouping: entries, by: { $0.name })
            .map { _, vs in vs[0] })
            .sorted { $0.name < $1.name }
        self.discovered = unique
    }

    /// Connect to a discovered service by resolving its Bonjour endpoint.
    func connect(discovered: Discovered, token: String) async {
        if discovered.port > 0 {
            await connect(host: discovered.host, port: discovered.port, token: token)
        } else {
            await connect(host: discovered.host, port: 24601, token: token)
        }
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

    /// Connect via host/port/token. The optional `certFingerprint` is the
    /// SHA-256 hash of the Mac daemon's self-signed cert, scanned from the
    /// QR code. When provided, only that exact cert is accepted (cert pinning).
    func connect(host: String, port: UInt16, token: String, certFingerprint: String? = nil) async {
        status = .connecting
        lastHost = host
        lastPort = port
        lastToken = token
        if let certFingerprint { pinnedCertFingerprint = certFingerprint }

        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let tlsOptions = NWProtocolTLS.Options()
        let pinnedFP = pinnedCertFingerprint
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions, { _, trust, complete in
                guard let pinnedFP else {
                    // No pinned cert — use standard system trust evaluation.
                    // This rejects self-signed certs, which is safer than
                    // accepting everything.
                    let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    var error: CFError?
                    let ok = SecTrustEvaluateWithError(secTrust, &error)
                    complete(ok)
                    return
                }
                // Pin to the specific cert fingerprint from QR pairing.
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                let certCount = SecTrustGetCertificateCount(secTrust)
                guard certCount > 0 else { complete(false); return }
                if let cert = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
                   let leaf = cert.first {
                    let der = SecCertificateCopyData(leaf) as Data
                    let hash = SHA256.hash(data: der)
                    let hex = hash.map { String(format: "%02x", $0) }.joined()
                    complete(hex == pinnedFP.lowercased())
                } else {
                    complete(false)
                }
            }, .main
        )
        let params = NWParameters(tls: tlsOptions)
        params.includePeerToPeer = true
        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.conn = conn

        let ready = await waitForReady(conn)
        if !ready {
            status = .failed("could not reach \(host):\(port)"); return
        }

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

    /// Disconnect and optionally attempt auto-reconnect.
    func disconnect(attemptReconnect: Bool = true) {
        conn?.cancel(); conn = nil
        pending.values.forEach { $0.resume(throwing: BridgeError.disconnected) }
        pending.removeAll()
        let wasConnected = status == .connected
        if wasConnected { status = .idle }
        // Auto-reconnect when the drop was unexpected (we were connected
        // and have saved pairing info).
        if attemptReconnect && wasConnected,
           let host = lastHost, let port = lastPort, let token = lastToken {
            scheduleReconnect(host: host, port: port, token: token)
        }
    }

    /// Explicitly disconnect without auto-reconnect (user-initiated unpair).
    func unpair() {
        reconnectTask?.cancel()
        reconnectTask = nil
        disconnect(attemptReconnect: false)
        lastHost = nil; lastPort = nil; lastToken = nil
        pinnedCertFingerprint = nil
        status = .idle
    }

    private func scheduleReconnect(host: String, port: UInt16, token: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var attempt = 0
            var backoff: TimeInterval = 1.0
            while !Task.isCancelled, let self, attempt < Self.reconnectMaxAttempts {
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                if Task.isCancelled { break }
                await self.connect(host: host, port: port, token: token)
                if self.isConnected { return }
                backoff = min(backoff * 2, Self.reconnectMaxBackoff)
            }
            if let self, !self.isConnected {
                self.status = .failed("reconnect failed after \(attempt) attempts")
            }
        }
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

    /// Ask the Mac to type one App Store Connect field into the
    /// frontmost Safari tab.
    ///
    /// The daemon has shipped `app_store_connect.fill` since the
    /// companion was written, but nothing on iOS ever called it — the
    /// guide's "Auto-fill" button just marked the step done. This is
    /// the missing wire.
    ///
    /// The Mac side always shows an Approve/Reject dialog before
    /// touching the page and refuses to run on any domain other than
    /// appstoreconnect.apple.com, so the human stays in the loop even
    /// though the request originates from the phone.
    ///
    /// Returns `false` when the user rejected the prompt on the Mac.
    /// Throws when Safari isn't on App Store Connect or the field
    /// can't be found on the current page.
    @discardableResult
    func fillASCField(field: String, value: String) async throws -> Bool {
        let r = try await request(
            type: "app_store_connect.fill",
            payload: ["field": field, "value": value]
        )
        return (r["filled"] as? Bool) ?? false
    }

    // MARK: - Shipping on the Mac

    /// Outcome of a long Mac-side step. `detail` is already written for
    /// a person to read; `logTail` is the raw tool output behind it.
    struct MacStepResult {
        let ok: Bool
        let phase: String
        let detail: String
        let logTail: String
        /// Absolute path on the Mac, set when an archive produced one.
        let ipaPath: String?

        init(_ response: [String: Any]) {
            ok = (response["ok"] as? Bool) ?? false
            phase = (response["phase"] as? String) ?? ""
            logTail = (response["log_tail"] as? String) ?? ""
            ipaPath = (response["absolute_path"] as? String)
                ?? (response["ipa_path"] as? String)
            detail = (response["detail"] as? String) ?? ""
        }
    }

    /// Ask the Mac to pull the generated app's source from the build
    /// server. Signing has to happen where Xcode is, and Xcode needs
    /// the actual files — this saves the user downloading and unzipping
    /// a workspace by hand. Returns the folder the project lives in.
    func fetchWorkspace(jobID: String, exportURL: String, token: String) async throws -> String {
        let r = try await request(
            type: "workspace.fetch",
            payload: ["job_id": jobID, "export_url": exportURL, "token": token]
        )
        guard (r["ok"] as? Bool) == true, let root = r["workspace_root"] as? String else {
            throw BridgeError.remote((r["detail"] as? String) ?? "could not fetch the workspace")
        }
        return root
    }

    /// Archive and export a signed .ipa on the Mac.
    ///
    /// The signing key is sent inline for this one command. It never
    /// touches CodeGenie's server, and the companion writes it
    /// owner-only and deletes it however the command ends.
    func archiveExport(
        workspaceRoot: String,
        teamID: String,
        keyID: String,
        issuerID: String,
        keyPEM: String
    ) async throws -> MacStepResult {
        MacStepResult(try await request(
            type: "xcodebuild.archive_export",
            payload: [
                "workspace_root": workspaceRoot,
                "team_id": teamID,
                "asc_api_key_id": keyID,
                "asc_api_issuer_id": issuerID,
                "asc_api_key_pem": keyPEM,
                "export_method": "app-store-connect",
                "configuration": "Release",
            ],
            timeout: 600
        ))
    }

    /// Validate and upload a signed .ipa to TestFlight from the Mac.
    func uploadToTestFlight(
        ipaPath: String,
        keyID: String,
        issuerID: String,
        keyPEM: String,
        appleID: String = "",
        appSpecificPassword: String = ""
    ) async throws -> MacStepResult {
        MacStepResult(try await request(
            type: "asc.upload",
            payload: [
                "ipa_path": ipaPath,
                "asc_api_key_id": keyID,
                "asc_api_issuer_id": issuerID,
                "asc_api_key_pem": keyPEM,
                "apple_id": appleID,
                "app_specific_password": appSpecificPassword,
            ],
            timeout: 300
        ))
    }

    // MARK: - Internals

    private func request(type: String, payload: [String: Any], timeout: TimeInterval? = nil) async throws -> [String: Any] {
        guard let conn else { throw BridgeError.notConnected }
        let id = "msg_" + UUID().uuidString.prefix(12)
        let envelope: [String: Any] = [
            "v": 1, "id": id, "kind": "request", "type": type, "payload": payload,
        ]
        let effectiveTimeout = timeout ?? Self.requestTimeout
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.pending[id] = cont
                    self.send(conn: conn, envelope: envelope) { error in
                        if let error {
                            self.pending.removeValue(forKey: id)
                            cont.resume(throwing: error)
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
                throw BridgeError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
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

enum BridgeError: Error, LocalizedError, CustomStringConvertible {
    case notConnected, disconnected, malformed, timeout, remote(String)
    var description: String {
        switch self {
        case .notConnected: "not connected"
        case .disconnected: "connection dropped"
        case .malformed:    "malformed message"
        case .timeout:      "request timed out — check that your Mac is awake"
        case .remote(let m): m
        }
    }
    var errorDescription: String? { description }
}

extension Notification.Name {
    static let companionEvent = Notification.Name("CodeGenie.CompanionEvent")
}
