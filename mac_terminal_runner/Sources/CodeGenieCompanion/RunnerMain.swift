import Foundation

/// Entry point for the CodeGenie terminal runner.
///
/// Runs as a long-lived Terminal process. On launch it:
///   1. Generates (or reads) a pairing token from `~/Library/Application
///      Support/CodeGenie/terminal-runner.token`.
///   2. Starts a local network server on a random port.
///   3. Advertises itself via Bonjour as `_codegenie-runner._tcp`.
///   4. Prints a pairing URL on stdout for the iOS app.
///
/// This is intentionally a CLI, not a packaged Mac app.
@main
struct Main {
    static func main() async throws {
        let port = UInt16(ProcessInfo.processInfo.environment["CODEGENIE_PORT"].flatMap(UInt16.init) ?? 0)
        let server = try CompanionServer(port: port)
        let pairing = try await server.start()
        let qrPayload = "codegenie://pair?host=\(pairing.host)&port=\(pairing.port)&token=\(pairing.token)"
        print("CodeGenie Terminal Runner ready.")
        print("Pairing URL: \(qrPayload)")
        print("Token: \(pairing.token)")
        print("Use ^C to stop.")
        // Keep the run loop alive; server is held by this task.
        try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
    }
}
