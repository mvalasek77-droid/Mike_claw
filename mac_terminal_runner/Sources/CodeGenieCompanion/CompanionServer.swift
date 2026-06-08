import Foundation
import Network

/// A minimal newline-delimited JSON server that speaks the CodeGenie
/// terminal runner protocol described in `docs/COMPANION_PROTOCOL.md`.
///
/// We use Apple's `Network.framework` instead of pulling in a full
/// WebSocket library so the runner stays a single binary with no
/// external dependencies. The framing implemented here is newline-
/// delimited JSON, matching the iOS `NWConnection` client.
public final class CompanionServer {
    public struct Pairing {
        public let host: String
        public let port: UInt16
        public let token: String
    }

    private let listener: NWListener
    private let token: String
    private var connections: [UUID: ClientConnection] = [:]
    private let queue = DispatchQueue(label: "com.codegenie.terminal-runner.server")

    public init(port: UInt16) throws {
        let params = NWParameters(tls: nil)
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false
        let nwPort = port == 0 ? .any : NWEndpoint.Port(rawValue: port) ?? .any
        self.listener = try NWListener(using: params, on: nwPort)
        self.token = TokenStore.loadOrCreate()
    }

    public func start() async throws -> Pairing {
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)

        // Wait for the listener to bind before reporting the port.
        let port = try await waitForPort()
        // Bonjour lets the iPhone find the terminal process on the same Wi-Fi.
        listener.service = NWListener.Service(name: "CodeGenie Terminal", type: "_codegenie-runner._tcp")
        return Pairing(host: "127.0.0.1", port: port, token: token)
    }

    public func stop() {
        listener.cancel()
        for c in connections.values { c.close() }
        connections.removeAll()
    }

    // MARK: Internals

    private func waitForPort() async throws -> UInt16 {
        for _ in 0..<200 {
            if case .ready = listener.state, let p = listener.port?.rawValue {
                return p
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "CodeGenieTerminalRunner", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "listener never became ready"
        ])
    }

    private func accept(_ conn: NWConnection) {
        let id = UUID()
        let client = ClientConnection(id: id, conn: conn, token: token, onClose: { [weak self] in
            self?.queue.async { self?.connections.removeValue(forKey: id) }
        })
        connections[id] = client
        client.start()
    }
}
