import Foundation

/// Entry point for the CodeGenie Companion daemon.
///
/// Runs as a long-lived process. On launch it:
///   1. Generates (or reads) a pairing token from `~/Library/Application
///      Support/CodeGenie/companion.token`.
///   2. Loads (or creates) its TLS certificate and starts listening on
///      a random port.
///   3. Advertises itself via Bonjour as `_codegenie-companion._tcp`.
///   4. Prints the pairing code as a QR code and as a link.
///
/// In a shipping product this is a menu-bar app. For now it's a CLI so
/// it builds and runs anywhere with the Swift toolchain.

@main
struct Main {
    static func main() async throws {
        let port = UInt16(ProcessInfo.processInfo.environment["CODEGENIE_PORT"].flatMap(UInt16.init) ?? 0)
        let server = try CompanionServer(port: port)
        let pairing = try await server.start()
        print("CodeGenie Companion ready.\n")
        if let qr = PairingQR.render(pairing.url) {
            print("Scan this with CodeGenie on your iPhone (Settings → Pair your Mac):\n")
            print(qr)
        }
        print("Or paste this link into the app:\n\(pairing.url)\n")
        print("Anyone with this code can run builds on this Mac. Don't share it.")
        print("Use ⌃C to stop.")
        // Keep the run loop alive — server is held by the task.
        try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
    }
}
