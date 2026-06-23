import Foundation

/// Entry point for the CodeGenie terminal runner.
///
/// Runs as a long-lived Terminal process. On launch it:
///   1. Generates (or reads) a pairing token from `~/Library/Application
///      Support/CodeGenie/terminal-runner.token`.
///   2. Checks if the Claw server is healthy; if not, installs the binary
///      and starts it.
///   3. Starts a local network server on a random port.
///   4. Advertises itself via Bonjour as `_codegenie-runner._tcp`.
///   5. Prints a pairing URL on stdout for the iOS app.
///
/// This is intentionally a CLI, not a packaged Mac app.
@main
struct Main {
    static func main() async throws {
        // ——— Health check: ensure Claw server is available ———
        NSLog("[TerminalRunner] Checking Claw server health...")
        do {
            try await ClawService.shared.ensureServerRunning()
            NSLog("[TerminalRunner] Claw server is available")
        } catch {
            NSLog("[TerminalRunner] Warning: could not start Claw server: \(error)")
            NSLog("[TerminalRunner] The runner will continue, but build commands will attempt to start Claw on demand.")
        }

        // ——— Start the Bonjour companion server ———
        let port = UInt16(ProcessInfo.processInfo.environment["CODEGENIE_PORT"].flatMap(UInt16.init) ?? 0)
        let server = try CompanionServer(port: port)
        let pairing = try await server.start()
        let qrPayload = "codegenie://pair?host=\(pairing.host)&port=\(pairing.port)&token=\(pairing.token)"
        print("CodeGenie Terminal Runner ready.")
        print("Pairing URL: \(qrPayload)")
        print("Token: \(pairing.token)")
        print("Use ^C to stop.")

        // Handle graceful shutdown — terminate the Claw server process
        let sigSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigSrc.setEventHandler {
            NSLog("[TerminalRunner] Received SIGINT, shutting down...")
            ClawService.shared.stopServer()
            server.stop()
            sigSrc.cancel()
            exit(0)
        }
        sigSrc.resume()

        // Keep the run loop alive; server is held by this task.
        try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
    }
}