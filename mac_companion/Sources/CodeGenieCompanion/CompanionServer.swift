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
    private var connections: [UUID: ClientConnection] = [:]
    private let queue = DispatchQueue(label: "com.codegenie.companion.server")

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
        // Bonjour
        listener.service = NWListener.Service(name: "CodeGenie", type: "_codegenie-companion._tcp")
        // The pairing host goes into the QR/paste URL — the fallback for
        // when Bonjour is blocked. It must be the Mac's LAN address; the
        // old hardcoded 127.0.0.1 made the iPhone connect to ITSELF, so
        // the fallback was broken exactly when it was needed.
        return Pairing(host: Self.lanIPv4() ?? "127.0.0.1", port: port, token: token)
    }

    /// Best-effort LAN IPv4 (prefers en0 — built-in Wi-Fi/Ethernet).
    private static func lanIPv4() -> String? {
        var best: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }   // skip lo0, utun, awdl…
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            if name == "en0" { return address }
            if best == nil { best = address }
        }
        return best
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
