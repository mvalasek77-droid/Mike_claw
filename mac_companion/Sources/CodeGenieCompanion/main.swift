import Foundation
import Darwin
import Dispatch

/// Entry point for the CodeGenie Companion daemon.
///
/// Runs as a long-lived process. On launch it:
///   1. Generates (or reads) a pairing token from `~/Library/Application
///      Support/CodeGenie/companion.token`.
///   2. Starts a local pairing server.
///   3. Advertises itself via Bonjour as `_codegenie-companion._tcp`.
///   4. Prints a QR-friendly pairing URL on stdout for scripted setup.
///
/// In a shipping product this is a menu-bar app. For now it's a CLI so
/// it builds and runs anywhere with the Swift toolchain.

let requestedPort = UInt16(ProcessInfo.processInfo.environment["CODEGENIE_PORT"].flatMap(UInt16.init) ?? 0)

func launchCompanion(port: UInt16) async throws -> (CompanionServer, CompanionServer.Pairing) {
    let server = try CompanionServer(port: port)
    let pairing = try await server.start()
    return (server, pairing)
}

func printReady(pairing: CompanionServer.Pairing, usedFallbackPort: Bool) {
    let qrPayload = "codegenie://pair?host=\(pairing.host)&port=\(pairing.port)&token=\(pairing.token)"
    print("CodeGenie Companion ready.")
    if usedFallbackPort {
        print("Port \(requestedPort) was busy, so CodeGenie picked port \(pairing.port).")
    }
    print("Your iPhone can now find this Mac automatically.")
    print("Pairing URL: \(qrPayload)")
    print("Token: \(pairing.token)")
    print("Use Ctrl-C to stop.")
    fflush(stdout)
}

let launched: (server: CompanionServer, pairing: CompanionServer.Pairing)
do {
    do {
        let result = try await launchCompanion(port: requestedPort)
        launched = (result.0, result.1)
        printReady(pairing: launched.pairing, usedFallbackPort: false)
    } catch where requestedPort != 0 {
        let result = try await launchCompanion(port: 0)
        launched = (result.0, result.1)
        printReady(pairing: launched.pairing, usedFallbackPort: true)
    }
} catch {
    fputs("CodeGenie Companion could not start: \(error.localizedDescription)\n", stderr)
    fputs("Close any old CodeGenie Companion terminal window and try again.\n", stderr)
    exit(1)
}

while !Task.isCancelled {
    try await Task.sleep(for: .seconds(3600))
    _ = launched.server
}
