import Foundation
import Network
import Security
import CryptoKit

/// Talks to the CodeGenie Companion running on the user's Mac.
///
/// The connection is TLS, pinned to the certificate fingerprint from
/// the pairing code, carrying newline-delimited JSON. Pinning is what
/// makes a self-signed certificate safe here: the fingerprint was read
/// off the Mac's own screen, so nothing else on the network can stand
/// in for it. That matters because the App Store Connect signing key
/// crosses this link when an app is uploaded.
///
/// The pairing lives in its own Keychain entry. It used to overwrite
/// the backend's bearer token, which both broke server requests and
/// made "is a Mac paired?" indistinguishable from "is a server token
/// set?".
@MainActor
final class CompanionBridge: ObservableObject {

    /// Shared so a pairing survives the screen that made it.
    static let shared = CompanionBridge()

    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?
    /// The saved pairing, whether or not the Mac is reachable right now.
    @Published private(set) var pairing: MacPairing?

    /// True when a Mac is paired and reachable right now.
    var isConnected: Bool { status == .connected }
    /// True when a Mac has been paired, reachable or not.
    var isPaired: Bool { pairing != nil }

    enum Status: Equatable {
        case idle, browsing, connecting, authenticating, connected, failed(String)
    }

    struct Discovered: Identifiable, Hashable {
        var id: String { name }
        let name: String
    }

    private static let requestTimeout: TimeInterval = 30
    private static let connectTimeout: TimeInterval = 10
    private static let reconnectMaxAttempts = 5
    private static let reconnectMaxBackoff: TimeInterval = 16

    private var reconnectTask: Task<Void, Never>?

    private init() {
        pairing = Self.loadPairing()
    }

    // MARK: - Discovery

    // Bonjour tells the user a companion is running nearby, which is a
    // useful "it's working" signal on the pairing screen. It is never
    // used to connect: an advertisement carries no token and no
    // fingerprint, so trusting one would defeat the pinning.

    private var browser: NWBrowser?

    func startBrowsing() {
        guard browser == nil else { return }
        if status == .idle { status = .browsing }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_codegenie-companion._tcp", domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names: [String] = results.compactMap { result in
                if case let .service(name, _, _, _) = result.endpoint { return name }
                return nil
            }
            Task { @MainActor in
                self?.discovered = Array(Set(names)).sorted().map { Discovered(name: $0) }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        if status == .browsing { status = .idle }
    }

    // MARK: - Connection

    private var conn: NWConnection?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]

    /// Pair from a scanned or pasted code. On failure `status` carries
    /// a message written for the person holding the phone.
    func connect(pairingURL: URL) async {
        await connect(pairingCode: pairingURL.absoluteString)
    }

    func connect(pairingCode: String) async {
        switch MacPairing.parse(pairingCode) {
        case .success(let parsed):
            await connect(to: parsed, isReconnect: false)
        case .failure(let problem):
            lastError = problem.message
            status = .failed(problem.message)
        }
    }

    /// Reconnect to the saved Mac, quietly. Called on launch and when
    /// the app returns to the foreground.
    func reconnectIfPaired() {
        guard let pairing, conn == nil, reconnectTask == nil else { return }
        switch status {
        case .connecting, .authenticating, .connected: return
        default: break
        }
        Task { await connect(to: pairing, isReconnect: true) }
    }

    private func connect(to target: MacPairing, isReconnect: Bool) async {
        teardownConnection(failing: BridgeError.disconnected)
        status = .connecting

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, trust, complete in
                complete(Self.certificateMatches(trust, pairing: target))
            },
            .global(qos: .userInitiated)
        )
        let params = NWParameters(tls: tls)
        params.includePeerToPeer = true

        guard let port = NWEndpoint.Port(rawValue: target.port) else {
            status = .failed("The pairing code has an invalid port.")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: params)
        conn = connection

        guard await waitForReady(connection) else {
            if conn === connection { conn = nil }
            connection.cancel()
            let message = "Couldn't reach your Mac. Check it's awake, on the same Wi-Fi, and that the companion is running. If you restarted the companion, scan its code again."
            lastError = message
            status = .failed(message)
            return
        }

        startReadLoop(connection)
        status = .authenticating
        do {
            _ = try await request(type: "auth", payload: ["token": target.token])
            // Saved only once the Mac has proved itself and accepted
            // the token, so a mistyped code never replaces a good one.
            if !isReconnect || pairing != target {
                pairing = target
                Self.savePairing(target)
            }
            status = .connected
            lastError = nil
        } catch {
            teardownConnection(failing: BridgeError.disconnected)
            let message = "Your Mac refused the pairing code. Scan the code it's showing now."
            lastError = message
            status = .failed(message)
        }
    }

    /// Runs off the main actor, on the security framework's queue.
    private nonisolated static func certificateMatches(_ trust: sec_trust_t, pairing: MacPairing) -> Bool {
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
              let leaf = chain.first
        else { return false }
        let der = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        return pairing.matches(certificateDigest: digest)
    }

    /// The connection dropped on its own. Try to get it back.
    private func connectionLost() {
        let wasConnected = status == .connected
        teardownConnection(failing: BridgeError.disconnected)
        status = .idle
        guard wasConnected, let pairing else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var backoff: TimeInterval = 1
            for _ in 0..<Self.reconnectMaxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.connect(to: pairing, isReconnect: true)
                if self.isConnected { break }
                backoff = min(backoff * 2, Self.reconnectMaxBackoff)
            }
            self?.reconnectTask = nil
        }
    }

    /// Close the connection but stay paired — the Mac will be found
    /// again next time.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        teardownConnection(failing: BridgeError.disconnected)
        status = .idle
    }

    /// Forget this Mac entirely.
    func unpair() {
        disconnect()
        pairing = nil
        Self.deletePairing()
        lastError = nil
    }

    private func teardownConnection(failing error: Error) {
        conn?.stateUpdateHandler = nil
        conn?.cancel()
        conn = nil
        timeouts.values.forEach { $0.cancel() }
        timeouts.removeAll()
        let waiting = pending
        pending.removeAll()
        waiting.values.forEach { $0.resume(throwing: error) }
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

    /// Send one request and wait for its response.
    ///
    /// Every request is bounded. Each waiting caller is resumed exactly
    /// once — by the response, the timeout, a send failure, or the
    /// connection going away — and whichever happens first removes the
    /// entry so the others find nothing to resume.
    private func request(
        type: String,
        payload: [String: Any],
        timeout: TimeInterval? = nil
    ) async throws -> [String: Any] {
        guard let conn else { throw BridgeError.notConnected }
        let id = "msg_" + UUID().uuidString.prefix(12)
        let envelope: [String: Any] = [
            "v": 1, "id": id, "kind": "request", "type": type, "payload": payload,
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: envelope) else {
            throw BridgeError.malformed
        }
        data.append(0x0A)
        let limit = timeout ?? Self.requestTimeout

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(id, with: .failure(BridgeError.timeout))
            }
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.finish(id, with: .failure(error)) }
            })
        }
    }

    private func finish(_ id: String, with result: Result<[String: Any], Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
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
                case .waiting:
                    // No route yet. The deadline below decides how
                    // long that is allowed to last.
                    break
                default:
                    break
                }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectTimeout) {
                if gate.claim() { cont.resume(returning: false) }
            }
        }
    }

    private func startReadLoop(_ conn: NWConnection) {
        let buffer = LineBuffer()

        func tick() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                let messages = buffer.append(data)
                let finished = isComplete || error != nil
                Task { @MainActor in
                    guard let self, self.conn === conn else { return }
                    for message in messages { self.dispatchIncoming(message) }
                    if finished { self.connectionLost() }
                }
                if !finished { Task { @MainActor in tick() } }
            }
        }
        tick()
    }

    private func dispatchIncoming(_ message: [String: Any]) {
        let kind = (message["kind"] as? String) ?? ""

        if kind == "response", let respondTo = message["in_response_to"] as? String {
            if (message["ok"] as? Bool) == true {
                finish(respondTo, with: .success((message["payload"] as? [String: Any]) ?? [:]))
            } else {
                let reason = (message["error"] as? String) ?? "remote error"
                finish(respondTo, with: .failure(BridgeError.remote(reason)))
            }
        }
        // "event" frames are surfaced via NotificationCenter so a
        // screen can show the Mac's progress without owning the bridge.
        if kind == "event" {
            NotificationCenter.default.post(name: .companionEvent, object: nil, userInfo: message)
        }
    }

    // MARK: - Pairing storage (Keychain)

    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.codegenie.mac-pairing",
        kSecAttrAccount as String: "default",
    ]

    private static func loadPairing() -> MacPairing? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(MacPairing.self, from: data)
    }

    private static func savePairing(_ pairing: MacPairing) {
        guard let data = try? JSONEncoder().encode(pairing) else { return }
        SecItemDelete(keychainQuery as CFDictionary)
        var add = keychainQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deletePairing() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}

/// Accumulates bytes from the socket and hands back whole JSON lines.
/// Touched only from the connection's serial queue.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    /// A line longer than this is not a message from our companion.
    private static let limit = 8 * 1024 * 1024

    func append(_ chunk: Data?) -> [[String: Any]] {
        if let chunk { data.append(chunk) }
        var messages: [[String: Any]] = []
        while let newline = data.firstIndex(of: 0x0A) {
            let line = data[data.startIndex..<newline]
            data.removeSubrange(data.startIndex...newline)
            if let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                messages.append(json)
            }
        }
        if data.count > Self.limit { data.removeAll() }
        return messages
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
