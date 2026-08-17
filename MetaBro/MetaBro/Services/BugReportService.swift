import Foundation

protocol BugReportService: Sendable {
    /// Snapshots current device/app diagnostics for the report form to show
    /// and, if the user opts in, attach.
    func diagnostics() async -> DeviceDiagnostics
    /// Submits a filled-out report.
    func submit(_ draft: BugReportDraft) async throws
}

extension BugReportService {
    /// Default diagnostics snapshot, shared by every backend: app/build
    /// version, device + OS, locale, and the last few minutes of in-app
    /// logs (plus a previous-launch crash breadcrumb, if any).
    static func currentDiagnostics() async -> DeviceDiagnostics {
        let info = Bundle.main.infoDictionary
        return DeviceDiagnostics(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "—",
            buildNumber: info?["CFBundleVersion"] as? String ?? "—",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: deviceModelIdentifier(),
            locale: Locale.current.identifier,
            recentLogs: await BroLog.store.exportText(),
            lastCrash: CrashReporter.lastCrash()
        )
    }

    private static func deviceModelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let chars = Mirror(reflecting: info.machine).children.compactMap { element -> Character? in
            guard let value = element.value as? Int8, value != 0 else { return nil }
            return Character(UnicodeScalar(UInt8(value)))
        }
        return String(chars)
    }
}

/// Offline-friendly backend: keeps submitted reports in memory so the demo
/// flow and tests can verify a submission happened without a server.
actor MockBugReportService: BugReportService {
    private var _submitted: [BugReportDraft] = []

    var submitted: [BugReportDraft] { _submitted }

    func diagnostics() async -> DeviceDiagnostics {
        await Self.currentDiagnostics()
    }

    func submit(_ draft: BugReportDraft) async throws {
        _submitted.append(draft)
    }
}
