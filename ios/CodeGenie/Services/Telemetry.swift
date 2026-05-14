import Foundation
import SwiftUI
import os.signpost

/// Opt-in, on-device telemetry. Counts build outcomes locally and
/// surfaces them in Settings → About so the user can see how the
/// swarm has performed *for them*. Nothing leaves the device.
///
/// Two layers:
///   * `os_signpost` for Instruments — useful when the user (or a
///     reviewer) has a development build attached.
///   * Persistent UserDefaults counters for the in-app summary.
///
/// We deliberately keep the data set tiny — no per-build IDs, no
/// prompts, no model names. Just rolling counts so a user can answer
/// "is this thing actually getting better?" without sending anything
/// home.
@MainActor
final class Telemetry: ObservableObject {
    static let shared = Telemetry()

    @AppStorage("telemetry.enabled") private(set) var enabled: Bool = false
    @Published private(set) var snapshot: Snapshot

    struct Snapshot: Codable, Equatable {
        var buildsStarted: Int = 0
        var buildsSucceeded: Int = 0
        var buildsFailed: Int = 0
        var totalRetries: Int = 0
        var totalSecondsElapsed: Double = 0
        var lastBuildAt: Date?

        var successRate: Double {
            guard buildsStarted > 0 else { return 0 }
            return Double(buildsSucceeded) / Double(buildsStarted)
        }

        var averageRetries: Double {
            guard buildsSucceeded + buildsFailed > 0 else { return 0 }
            return Double(totalRetries) / Double(buildsSucceeded + buildsFailed)
        }

        var averageSeconds: Double {
            guard buildsSucceeded + buildsFailed > 0 else { return 0 }
            return totalSecondsElapsed / Double(buildsSucceeded + buildsFailed)
        }
    }

    private static let storageKey = "telemetry.snapshot.v1"
    private let log = OSLog(subsystem: "com.codegenie", category: "telemetry")

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.snapshot = s
        } else {
            self.snapshot = Snapshot()
        }
    }

    func setEnabled(_ on: Bool) { enabled = on }

    func reset() {
        snapshot = Snapshot()
        persist()
    }

    // MARK: Counters

    func recordBuildStarted() {
        guard enabled else { return }
        os_signpost(.event, log: log, name: "BuildStarted")
        snapshot.buildsStarted += 1
        snapshot.lastBuildAt = .now
        persist()
    }

    func recordBuildFinished(succeeded: Bool, retries: Int, secondsElapsed: Double) {
        guard enabled else { return }
        os_signpost(.event, log: log,
                    name: succeeded ? "BuildSucceeded" : "BuildFailed")
        if succeeded { snapshot.buildsSucceeded += 1 }
        else         { snapshot.buildsFailed    += 1 }
        snapshot.totalRetries += max(0, retries)
        snapshot.totalSecondsElapsed += max(0, secondsElapsed)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
