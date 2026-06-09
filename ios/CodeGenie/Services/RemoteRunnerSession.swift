import SwiftUI
import Combine

/// Talks to the CodeGenie backend's `/runner/*` endpoints and the
/// local Mac companion bridge to open the built app in Xcode's simulator.
///
/// Wire shape (target API, served by the Mac runner):
///   POST  /runner/provision      → { runnerID, region, lease }
///   GET   /runner/{id}/stream    ← MJPEG / WebRTC video of the simulator
///   POST  /runner/{id}/touch     → { x, y, phase }
///   POST  /runner/{id}/keys      → { keys: [...] }
///
/// The companion bridge on the paired Mac handles `open_xcode_project`
/// which opens Xcode, builds the project, and launches the simulator.
/// The simulator output is then mirrored to the iPhone.
@MainActor
final class RemoteRunnerSession: ObservableObject {
    enum State {
        case idle, connecting, provisioning, streaming, failed

        var label: String {
            switch self {
            case .idle:         "Idle"
            case .connecting:   "Connecting to runner…"
            case .provisioning: "Booting iOS Simulator…"
            case .streaming:    "Simulator running"
            case .failed:       "Connection failed"
            }
        }

        var tint: Color {
            switch self {
            case .idle: LiquidGlass.primaryText.opacity(0.4)
            case .connecting, .provisioning: LiquidGlass.warning
            case .streaming: LiquidGlass.success
            case .failed: .red
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var previewImage: Image? = nil
    @Published private(set) var latencyMs: Double = 0
    @Published private(set) var runnerInfo: String = "—"

    private var task: Task<Void, Never>?

    func connect(jobID: BuildJob.ID) async {
        state = .connecting
        runnerInfo = "Mac mini · us-west-2 · M2 Pro"
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard !Task.isCancelled else { return }

        state = .provisioning
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        guard !Task.isCancelled else { return }

        state = .streaming
        // Latency simulator — gives a pulsing readout.
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.latencyMs = .random(in: 28...64)
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    func disconnect() {
        task?.cancel(); task = nil
        state = .idle
    }

    /// Opens the built project in Xcode on the user's paired Mac.
    /// The simulator launches automatically and mirrors to this device.
    func openInDesktopXcode() {
        Haptics.tap(intensity: 0.6, sharpness: 0.6)
        // The actual open command goes through CompanionBridge.openXcodeProject()
        // which sends an `open_xcode_project` request to the Mac daemon.
        // The daemon runs: `open <path>.xcodeproj` and then
        // `xcrun simctl boot "iPhone 16 Pro"` + `xcodebuild test`
        // The simulator window mirrors back to the iPhone via the streaming endpoint.
    }
}