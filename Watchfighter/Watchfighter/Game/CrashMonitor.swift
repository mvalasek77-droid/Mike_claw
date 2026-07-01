import Foundation

/// A lightweight, dependency-free crash monitor: installs a POSIX signal
/// handler and an uncaught-exception handler once at launch, and persists a
/// plain-text crash log to disk if the app goes down hard. On the *next*
/// launch, `GameScreen` checks `pendingCrashReport()` and offers the player a
/// chance to review and send it through the bug-report sheet.
///
/// This is not a full crash-reporting SDK (no symbolication, no network
/// upload) — it's a best-effort local net so a hard crash isn't silent, sized
/// for a small watchOS app with no backend of its own.
enum CrashMonitor {
    private static let logDirectoryName = "CrashLogs"
    private static var didInstall = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true

        NSSetUncaughtExceptionHandler { exception in
            CrashMonitor.writeLog(
                reason: "Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "no reason given")",
                stack: exception.callStackSymbols
            )
        }

        for signalNumber in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(signalNumber) { receivedSignal in
                CrashMonitor.writeLog(
                    reason: "Signal \(receivedSignal) received",
                    stack: Thread.callStackSymbols
                )
                signal(receivedSignal, SIG_DFL)
                raise(receivedSignal)
            }
        }
    }

    private static func writeLog(reason: String, stack: [String]) {
        let report = """
        Watchfighter crash report
        Time: \(ISO8601DateFormatter().string(from: Date()))
        Reason: \(reason)

        Stack:
        \(stack.joined(separator: "\n"))
        """
        guard let url = logDirectory()?.appendingPathComponent("crash-\(Int(Date().timeIntervalSince1970)).log") else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The most recent crash report on disk, if any (checked once at launch).
    static func pendingCrashReport() -> String? {
        guard let dir = logDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              let latest = files.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first,
              let text = try? String(contentsOf: latest, encoding: .utf8) else {
            return nil
        }
        return text
    }

    /// Call once the pending report has been shown/handled so it isn't
    /// re-surfaced on the following launch.
    static func clearPendingCrashReports() {
        guard let dir = logDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func logDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(logDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
