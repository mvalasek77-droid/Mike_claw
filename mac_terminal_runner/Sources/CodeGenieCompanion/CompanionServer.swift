import Foundation
import Network

/// A minimal newline-delimited JSON server that speaks the CodeGenie
/// terminal runner protocol described in `docs/COMPANION_PROTOCOL.md`.
///
/// We use Apple's `Network.framework` instead of pulling in a full
/// WebSocket library so the runner stays a single binary with no
/// external dependencies. The framing implemented here is newline-
/// delimited JSON, matching the iOS `NWConnection` client.
///
/// Connection flow:
///   1. Server advertises via Bonjour (`_codegenie-runner._tcp`) with
///      a TXT record containing the port.
///   2. iOS discovers the server, user taps it, and sends a `pair` request.
///   3. Server shows a macOS confirmation dialog ("Allow [Device] to connect?").
///   4. If approved, server returns the auth token.
///   5. iOS stores the token and sends `auth` to complete the connection.
///
/// Alternatively, the server prints a `codegenie://pair?…` URL with embedded
/// token for manual copy-paste pairing (no confirmation dialog needed since
/// the user already has physical access to both devices).
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
        params.includePeerToPeer = true  // Required for Bonjour discovery from iOS
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

        // Get the actual LAN IP (not 127.0.0.1) so the iPhone can reach us.
        let lanIP = Self.getLANIP()

        // Advertise via Bonjour with TXT record containing the port.
        // The TXT record lets the iOS client discover the port without
        // needing the manual pairing URL.
        let txtRecord: [String: String] = [
            "port": "\(port)",
            "proto": "1",
        ]
        listener.service = NWListener.Service(
            name: Host.current().localizedName ?? "Mac",
            type: "_codegenie-runner._tcp",
            domain: nil,
            txtRecord: NWTXTRecord(txtRecord)
        )

        return Pairing(host: lanIP, port: port, token: token)
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

    /// Resolve the Mac's actual LAN IP address so the iPhone on the
    /// same Wi-Fi network can reach us.
    private static func getLANIP() -> String {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return "127.0.0.1"
        }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // IPv4 only, skip loopback
            guard addrFamily == UInt8(AF_INET) else {
                ptr = current.pointee.ifa_next
                continue
            }
            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else {
                ptr = current.pointee.ifa_next
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                // Prefer en0 (Wi-Fi), but accept any non-loopback interface
                if name == "en0" {
                    return ip
                }
                if address == nil {
                    address = ip
                }
            }

            ptr = current.pointee.ifa_next
        }
        return address ?? "127.0.0.1"
    }
}

/// Helper to create an NWTXTRecord from a dictionary.
/// Network.framework doesn't expose a public init for this,
/// so we use dns_sd.h's TXTRecordCreate API underneath.
private func NWTXTRecord(_ dict: [String: String]) -> Data {
    // Build a DNS TXT record (RFC 1035 format) manually.
    // Each entry: 1 byte length + key=value (no null terminator)
    var data = Data()
    for (key, value) in dict {
        let entry = "\(key)=\(value)"
        let bytes = [UInt8](entry.utf8)
        guard bytes.count <= 255 else { continue }  // TXT record max per-entry length
        data.append(UInt8(bytes.count))
        data.append(contentsOf: bytes)
    }
    return data
}