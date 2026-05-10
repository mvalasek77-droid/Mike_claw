import Foundation

/// Entry point for the CodeGenie Companion daemon.
///
/// Runs as a long-lived process. On launch it:
///   1. Generates (or reads) a pairing token from `~/Library/Application
///      Support/CodeGenie/companion.token`.
///   2. Starts a WebSocket server on a random port.
///   3. Advertises itself via Bonjour as `_codegenie-companion._tcp`.
///   4. Prints a QR-friendly pairing URL on stdout for scripted setup.
///
/// In a shipping product this is a menu-bar app. For now it's a CLI so
/// it builds and runs anywhere with the Swift toolchain.

@main
struct Main {
    static func main() async throws {
        let port = UInt16(ProcessInfo.processInfo.environment["CODEGENIE_PORT"].flatMap(UInt16.init) ?? 0)
        let server = try CompanionServer(port: port)
        let pairing = try await server.start()
        let qrPayload = "codegenie://pair?host=\(pairing.host)&port=\(pairing.port)&token=\(pairing.token)"
        print("CodeGenie Companion ready.")
        print("Pairing URL: \(qrPayload)")
        print("Token: \(pairing.token)")
        print("Use ⌃C to stop.")
        // Keep the run loop alive — server is held by the task.
        try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
    }
}
