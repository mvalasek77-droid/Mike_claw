import Foundation
import Network

/// The listener for the CodeGenie Companion protocol described in
/// `docs/COMPANION_PROTOCOL.md`: newline-delimited JSON over TLS.
///
/// Built on `Network.framework` so the daemon stays a single binary
/// with no external dependencies.
public final class CompanionServer {
    public struct Pairing {
        public let host: String
        public let port: UInt16
        public let token: String
        /// SHA-256 of this Mac's certificate. The phone accepts only a
        /// certificate with this fingerprint.
        public let fingerprint: String

        public var url: String {
            var components = URLComponents()
            components.scheme = "codegenie"
            components.host = "pair"
            components.queryItems = [
                URLQueryItem(name: "host", value: host),
                URLQueryItem(name: "port", value: String(port)),
                URLQueryItem(name: "token", value: token),
                URLQueryItem(name: "fp", value: fingerprint),
            ]
            return components.string ?? ""
        }
    }

    private let listener: NWListener
    private let token: String
    private let fingerprint: String
    private var connections: [UUID: ClientConnection] = [:]
    private let queue = DispatchQueue(label: "com.codegenie.companion.server")

    public init(port: UInt16) throws {
        let identity = try TLSIdentity.loadOrCreate()
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        guard let local = sec_identity_create(identity.identity) else {
            throw TLSIdentity.Failure.noIdentity
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, local)
        self.fingerprint = identity.fingerprint

        let params = NWParameters(tls: tls)
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
        // Bonjour
        listener.service = NWListener.Service(name: "CodeGenie", type: "_codegenie-companion._tcp")
        // The name other devices on the network can reach this Mac by.
        // It used to report 127.0.0.1, which on the phone is the phone.
        return Pairing(
            host: Self.reachableHostName(),
            port: port,
            token: token,
            fingerprint: fingerprint
        )
    }

    static func reachableHostName() -> String {
        let name = ProcessInfo.processInfo.hostName
        if name.isEmpty || name == "localhost" { return "localhost" }
        return name.contains(".") ? name : name + ".local"
    }

    public func stop() {
        listener.cancel()
        for c in connections.values { c.close() }
        connections.removeAll()
    }

    // MARK: Internals

    private func waitForPort() async throws -> UInt16 {
        for _ in 0..<200 {
            if case let .ready = listener.state, let p = listener.port?.rawValue {
                return p
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "Companion", code: 1, userInfo: [
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
