import Foundation

/// Captures a breadcrumb for the one class of crash Swift can still observe
/// after the fact: uncaught `NSException`s bridged from Objective-C
/// frameworks. Swift's own traps (force-unwrap, `fatalError`, out-of-bounds)
/// terminate the process before any handler can run, so this is a
/// best-effort net rather than a full crash reporter — its job is to make
/// sure the *next* launch's bug report has something better than nothing.
enum CrashReporter {
    private static let breadcrumbURL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("metabro-last-crash.log")

    /// Installs the handler. Call once, as early as possible during launch.
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(exception.name.rawValue): \(exception.reason ?? "no reason")\n"
                + exception.callStackSymbols.joined(separator: "\n")
            try? text.write(to: CrashReporter.breadcrumbURL, atomically: true, encoding: .utf8)
        }
    }

    /// The breadcrumb left by the *previous* launch, if it didn't exit
    /// cleanly. Reports attach this once, then it's expected to be cleared.
    static func lastCrash() -> String? {
        try? String(contentsOf: breadcrumbURL, encoding: .utf8)
    }

    /// Clears the breadcrumb so a past crash doesn't keep resurfacing in
    /// every future report.
    static func clear() {
        try? FileManager.default.removeItem(at: breadcrumbURL)
    }
}
