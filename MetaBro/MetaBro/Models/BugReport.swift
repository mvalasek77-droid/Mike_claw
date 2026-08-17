import Foundation

// Pure domain models for the bug-report flow — no SwiftUI/UIKit imports.

/// How badly a reported issue affects the user's experience.
enum BugSeverity: String, CaseIterable, Codable, Hashable, Sendable {
    case minor, major, crash

    var label: String {
        switch self {
        case .minor: "Minor annoyance"
        case .major: "Blocks what I was doing"
        case .crash: "App crashed"
        }
    }
}

/// Device/app context attached to every report so engineering doesn't have
/// to ask "what device and version were you on?" — captured automatically.
struct DeviceDiagnostics: Sendable {
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceModel: String
    var locale: String
    var recentLogs: String
    var lastCrash: String?
}

/// What the user fills in before submitting.
struct BugReportDraft: Sendable {
    var summary: String
    var details: String
    var severity: BugSeverity
    var includeDiagnostics: Bool
}
