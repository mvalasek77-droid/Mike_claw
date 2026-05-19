import Foundation
import Network

/// A minimal WebSocket-ish server that speaks the CodeGenie Companion
/// protocol described in `docs/COMPANION_PROTOCOL.md`.
///
/// We use Apple's `Network.framework` instead of pulling in a full
/// WebSocket library so the daemon stays a single binary with no
/// external dependencies. The framing implemented here is a pragmatic
/// subset of RFC 6455 — enough to talk to URLSessionWebSocketTask on
/// the iOS side, not enough to be a general-purpose WebSocket server.
public final class CompanionServer {
    public struct Pairing {
        public let host: String
        public let port: UInt16
        public let token: String
    }

    private let listener: NWListener
    private let token: String
    private let requestedPort: UInt16
    private var connections: [UUID: ClientConnection] = [:]
    private var boundPort: UInt16 = 0
    private let queue = DispatchQueue(label: "com.codegenie.companion.server")

    public init(port: UInt16) throws {
        let params = NWParameters(tls: nil)
        params.allowLocalEndpointReuse = false
        params.includePeerToPeer = false
        let nwPort = port == 0 ? .any : NWEndpoint.Port(rawValue: port) ?? .any
        self.listener = try NWListener(using: params, on: nwPort)
        self.token = TokenStore.loadOrCreate()
        self.requestedPort = port
    }

    public func start() async throws -> Pairing {
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.service = NWListener.Service(name: "CodeGenie on \(macDisplayName())", type: "_codegenie-companion._tcp")
        let port = try await waitForPort()
        boundPort = port
        return Pairing(host: localPairingHost(), port: port, token: token)
    }

    public func stop() {
        listener.cancel()
        for c in connections.values { c.close() }
        connections.removeAll()
    }

    // MARK: Internals

    private func waitForPort() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener.port?.rawValue else {
                        if gate.claim() {
                            continuation.resume(throwing: CompanionServerError.listenerReadyWithoutPort)
                        }
                        return
                    }
                    if gate.claim() { continuation.resume(returning: port) }
                case .failed(let error):
                    if gate.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if gate.claim() { continuation.resume(throwing: CompanionServerError.listenerCancelled) }
                default:
                    break
                }
            }
            listener.start(queue: queue)

            func pollPort(remaining: Int) {
                queue.asyncAfter(deadline: .now() + .milliseconds(25)) {
                    if let port = self.listener.port?.rawValue {
                        if gate.claim() { continuation.resume(returning: port) }
                        return
                    }
                    if remaining <= 0 {
                        if gate.claim() { continuation.resume(throwing: CompanionServerError.listenerTimedOut) }
                        return
                    }
                    pollPort(remaining: remaining - 1)
                }
            }

            if self.requestedPort != 0 {
                queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    if gate.claim() {
                        continuation.resume(returning: self.requestedPort)
                    }
                }
            } else {
                pollPort(remaining: 200)
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = UUID()
        let client = ClientConnection(
            id: id,
            conn: conn,
            token: token,
            pairingProvider: { [weak self] in
                guard let self else {
                    return Pairing(host: "127.0.0.1", port: 0, token: "")
                }
                return Pairing(host: self.localPairingHost(), port: self.boundPort, token: self.token)
            },
            onClose: { [weak self] in
                self?.queue.async { self?.connections.removeValue(forKey: id) }
            }
        )
        connections[id] = client
        client.start()
    }

    private func localPairingHost() -> String {
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host != "localhost" else { return "127.0.0.1" }
        if host.hasSuffix(".local") || host.contains(".") { return host }
        return host + ".local"
    }

    private func macDisplayName() -> String {
        if let localized = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }
        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: ".lan", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? "This Mac" : host
    }
}

extension CompanionServer: @unchecked Sendable {}

private enum CompanionServerError: Error, LocalizedError {
    case listenerReadyWithoutPort
    case listenerCancelled
    case listenerTimedOut

    var errorDescription: String? {
        switch self {
        case .listenerReadyWithoutPort:
            "The Mac listener started, but macOS did not report a port."
        case .listenerCancelled:
            "The Mac listener stopped before pairing could start."
        case .listenerTimedOut:
            "The Mac listener did not report a port in time."
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
