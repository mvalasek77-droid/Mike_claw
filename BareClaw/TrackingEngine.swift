import Foundation

// MARK: - TrackingEngine
//
// Lightweight engagement tracker. Records session duration, message counts,
// and feature usage so other engines can make timing-aware decisions
// (e.g. suppress proactive messages during a deep chat session).

@MainActor
final class TrackingEngine {
    static let shared = TrackingEngine()

    private var sessionStart: Date?

    private let defaults          = UserDefaults.standard
    private let totalSessionsKey  = "track.totalSessions"
    private let avgSessionMinKey  = "track.avgSessionMin"
    private let featureUsageKey   = "track.featureUsage"

    private(set) var totalSessions:     Int    = 0
    private(set) var avgSessionMinutes: Double = 0
    private(set) var currentSessionMessages: Int = 0
    private var featureUsage: [String: Int] = [:]

    private init() {
        totalSessions     = defaults.integer(forKey: totalSessionsKey)
        avgSessionMinutes = defaults.double(forKey: avgSessionMinKey)
        if let data  = defaults.data(forKey: featureUsageKey),
           let usage = try? JSONDecoder().decode([String: Int].self, from: data) {
            featureUsage = usage
        }
    }

    // MARK: - Session lifecycle

    func sessionStarted() {
        sessionStart = Date()
        currentSessionMessages = 0
        totalSessions += 1
        defaults.set(totalSessions, forKey: totalSessionsKey)
        DiagnosticsLog.info("tracking", "Session started.", details: ["totalSessions": "\(totalSessions)"])
    }

    func sessionEnded() {
        guard let start = sessionStart else { return }
        let minutes = Date().timeIntervalSince(start) / 60
        let n = max(1, Double(totalSessions))
        avgSessionMinutes = (avgSessionMinutes * (n - 1) + minutes) / n
        defaults.set(avgSessionMinutes, forKey: avgSessionMinKey)
        sessionStart = nil
        DiagnosticsLog.info("tracking", "Session ended.", details: [
            "durationMin": String(format: "%.1f", minutes),
            "avgMin": String(format: "%.1f", avgSessionMinutes)
        ])
    }

    func messageSent() {
        currentSessionMessages += 1
    }

    // MARK: - Feature usage

    func trackFeature(_ name: String) {
        featureUsage[name, default: 0] += 1
        if let data = try? JSONEncoder().encode(featureUsage) {
            defaults.set(data, forKey: featureUsageKey)
        }
    }

    func usageCount(for feature: String) -> Int {
        featureUsage[feature] ?? 0
    }

    // MARK: - Derived signals

    /// True when the user has been in an active session for 10+ minutes.
    var isDeepSession: Bool {
        guard let start = sessionStart else { return false }
        return Date().timeIntervalSince(start) > 600
    }

    var isFirstSession: Bool { totalSessions <= 1 }

    /// Current session duration in minutes (0 if no active session).
    var currentSessionMinutes: Double {
        guard let start = sessionStart else { return 0 }
        return Date().timeIntervalSince(start) / 60
    }
}
