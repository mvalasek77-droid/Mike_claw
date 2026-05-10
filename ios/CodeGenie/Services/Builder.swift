import Foundation
import SwiftUI

/// Drives a `BuildJob` through its stages.
///
/// In production this is wired to the CodeGenie backend (Anthropic + OpenAI
/// + a remote macOS runner). For development and previews the runner is
/// `LocalSimulatedBuilder` which steps through stages on a timer so we can
/// design and demo the build screen without a backend round-trip.
@MainActor
protocol BuilderService: AnyObject {
    func start(_ job: BuildJob, update: @escaping @MainActor (BuildJob.Stage) -> Void) async
    func cancel(_ jobID: BuildJob.ID)
}

@MainActor
final class LocalSimulatedBuilder: BuilderService {
    private var cancelled: Set<BuildJob.ID> = []

    func cancel(_ jobID: BuildJob.ID) { cancelled.insert(jobID) }

    func start(_ job: BuildJob, update: @escaping @MainActor (BuildJob.Stage) -> Void) async {
        let timeline: [(BuildJob.Stage, UInt64)] = [
            (.planning, 1_400_000_000),
            (.scaffolding, 2_000_000_000),
            (.generatingUI, 2_800_000_000),
            (.wiringLogic, 2_200_000_000),
            (.linting, 1_600_000_000),
            (.buildingIPA, 2_400_000_000),
            (.readyForTest, 0)
        ]

        for (stage, duration) in timeline {
            if cancelled.contains(job.id) { return }
            update(stage)
            Haptics.tap(intensity: 0.4, sharpness: 0.55)
            if duration > 0 {
                try? await Task.sleep(nanoseconds: duration)
            }
        }
        Haptics.success()
    }
}
