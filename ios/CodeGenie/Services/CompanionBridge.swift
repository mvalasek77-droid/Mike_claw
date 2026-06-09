import Foundation
import Network
import UIKit

/// Talks to the CodeGenie terminal runner running on the user's Mac.
///
/// Two connection paths:
///  1. **Wi-Fi discovery (primary).** Browse for `_codegenie-runner._tcp`
///     Bonjour services. User taps a discovered Mac → iPhone confirmation
///     dialog → sends `pair` request → Mac shows confirmation dialog
///     → if approved, token is returned → `auth` completes the connection.
///  2. **Manual URL.** Copy the `codegenie://pair?…` URL from Terminal
///     and paste it. Token is embedded, so no Mac-side confirmation needed.
@MainActor
final class CompanionBridge: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

    @Published private(set) var discovered: [Discovered] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastError: String?

    enum Status: Equatable {
        case idle, browsing, connecting, waitingForApproval, authenticating, connected, failed(String)
    }

    struct Discovered: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: UInt16
    }

    // MARK: - Discovery

    private var nwBrowser: NWBrowser?
    private var nsBrowser: NetServiceBrowser?
    private var resolvingServices: [String: NetService] = [:]  // name -> service
    private var resolvedEntries: [String: Discovered] = [:]     // name -> resolved entry

    func startBrowsing() {
        status = .browsing
        discovered = []
        resolvedEntries = [:]

        // Use NetServiceBrowser to discover services — it can resolve
        // host and port, unlike NWBrowser which only gives the name.
        let nsb = NetServiceBrowser()
        nsb.delegate = self
        nsb.searchForServices(ofType: "_codegenie-runner._tcp", inDomain: "local.")
        self.nsBrowser = nsb

        // Also use NWBrowser for faster name-based discovery
        let params = NWParameters(tls: nil)
        params.includePeerToPeer = true
        let nwBrowser = NWBrowser(
            for: .bonjour(type: "_codegenie-runner._tcp", domain: nil),
            using: params
        )
        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleNWBrowserResults(results)
            }
        }
        nwBrowser.start(queue: .main)
        self.nwBrowser = nwBrowser
    }

    func stopBrowsing() {
        nwBrowser?.cancel(); nwBrowser = nil
        nsBrowser?.stop(); nsBrowser = nil
        resolvingServices.removeAll()
        if status == .browsing { status = .idle }
    }

    // MARK: - NetServiceBrowserDelegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            // Resolve each service to get host + port
            service.delegate = self
            resolvingServices[service.name] = service
            service.resolve(withTimeout: 5.0)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        Task { @MainActor in
            resolvingServices.removeValue(forKey: service.name)
            resolvedEntries.removeValue(forKey: service.name)
            updateDiscoveredList()
        }
    }

    // MARK: - NetServiceDelegate

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            let name = sender.name
            let port = UInt16(sender.port)

            // Get the IPv4 address from addresses
            var host = name + ".local"
            if let addresses = sender.addresses, !addresses.isEmpty {
                // Parse sockaddr to get IP string
                for addrData in addresses {
                    var addr = addrData.withUnsafeBytes { ptr -> sockaddr_in in
                        ptr.baseAddress!.assumingMemoryBound(to: sockaddr_in.self).pointee
                    }
                    if addr.sin_family == AF_INET {
                        var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let ipStr = inet_ntop(AF_INET, &addr.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                        if ipStr != nil {
                            host = String(cString: ipBuffer)
                            break
                        }
                    }
                }
            }

            if port > 0 {
                resolvedEntries[name] = Discovered(name: name, host: host, port: port)
                updateDiscoveredList()
            }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        Task { @MainActor in
            // Resolution failed — we might still connect via .local hostname
            // if we get port from the NWBrowser results
        }
    }

    private func updateDiscoveredList() {
        // Merge resolved entries with any unresolved ones
        var entries: [Discovered] = Array(resolvedEntries.values)

        // Also check NWBrowser results for services we haven't resolved yet
        for entry in discovered where !resolvedEntries.keys.contains(entry.name) {
            // Keep the unresolved entry only if we don't have a resolved version
            if !entries.contains(where: { $0.name == entry.name }) {
                entries.append(entry)
            }
        }

        let unique = Array(Dictionary(grouping: entries, by: { $0.name })
            .map { _, vs in vs.first(where: { $0.port > 0 }) ?? vs[0] })
            .sorted { $0.name < $1.name }
        self.discovered = unique
    }

    // MARK: - NWBrowser results (supplementary)

    private func handleNWBrowserResults(_ results: Set<NWBrowser.Result>) {
        // We mainly use NWBrowser for change notifications to trigger
        // NetServiceBrowser resolution. But we also track discovered
        // names here in case NetServiceBrowser doesn't fire.
        var needsUpdate = false
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            if resolvedEntries[name] == nil && !discovered.contains(where: { $0.name == name }) {
                // Add unresolved entry — will be filled in when NetService resolves
                needsUpdate = true
            }
        }
        if needsUpdate {
            updateDiscoveredList()
        }
    }

    // MARK: - Connection

    private var conn: NWConnection?
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]

    /// Connect via a pairing URL (manual paste flow).
    func connect(pairingURL: URL) async {
        guard let host = pairingURL.queryItem("host"),
              let portStr = pairingURL.queryItem("port"),
              let port = UInt16(portStr),
              let token = pairingURL.queryItem("token") else {
            status = .failed("malformed pairing URL"); return
        }
        await connect(host: host, port: port, token: token)
    }

    /// Connect to a discovered Mac via Wi-Fi.
    /// Sends a `pair` request — Mac shows a confirmation dialog.
    func connectToDiscovered(_ mac: Discovered) async {
        guard mac.port > 0 else {
            // Try to resolve the service on the fly
            let resolved = await resolveService(name: mac.name)
            guard let resolved else {
                status = .failed("Could not resolve \(mac.name). Make sure the terminal runner is running on your Mac and both devices are on the same Wi-Fi.")
                return
            }
            await connectToDiscovered(resolved)
            return
        }

        status = .connecting

        let nwHost = NWEndpoint.Host(mac.host)
        let nwPort = NWEndpoint.Port(rawValue: mac.port)!
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.conn = connection

        let ready = await waitForReady(connection)
        if !ready {
            status = .failed("Could not reach \(mac.name)")
            return
        }

        startReadLoop(connection)

        // Step 1: Send `pair` request — Mac shows confirmation dialog
        status = .waitingForApproval
        do {
            let deviceName = UIDevice.current.name
            let response = try await request(type: "pair", payload: ["device": deviceName])
            guard let token = response["token"] as? String else {
                status = .failed("Invalid pairing response")
                return
            }

            // Step 2: Authenticate with the received token
            status = .authenticating
            Credentials.shared.setBackendToken(token)
            _ = try await request(type: "auth", payload: ["token": token])
            status = .connected
            lastError = nil
        } catch {
            status = .failed("Pairing failed: \(error)")
            disconnect()
        }
    }

    /// Resolve a Bonjour service by name to get host and port.
    private func resolveService(name: String) async -> Discovered? {
        await withCheckedContinuation { continuation in
            let service = NetService(domain: "local.", type: "_codegenie-runner._tcp", name: name)
            service.delegate = self
            resolvingServices[name] = service

            // Set a timeout
            let timeout = DispatchWorkItem { [weak self] in
                Task { @MainActor in
                    self?.resolvingServices.removeValue(forKey: name)
                    if let entry = self?.resolvedEntries[name] {
                        continuation.resume(returning: entry)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

            service.resolve(withTimeout: 5.0)
        }
    }

    /// Connect with a known host, port, and token (manual URL flow).
    func connect(host: String, port: UInt16, token: String) async {
        status = .connecting
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
        let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
        self.conn = connection

        let ready = await waitForReady(connection)
        if !ready {
            status = .failed("Could not reach \(host):\(port)")
            return
        }

        Credentials.shared.setBackendToken(token)
        startReadLoop(connection)

        status = .authenticating
        do {
            _ = try await request(type: "auth", payload: ["token": token])
            status = .connected
            lastError = nil
        } catch {
            status = .failed("Auth failed: \(error)")
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