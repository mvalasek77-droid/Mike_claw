import SwiftUI
import Combine

/// Talks to the CodeGenie backend's `/runner/*` endpoints.
///
/// Wire shape (target API, served by the Mac runner):
///   POST  /runner/provision      → { runnerID, region, lease }
///   GET   /runner/{id}/stream    ← MJPEG / WebRTC video of the simulator
///   POST  /runner/{id}/touch     → { x, y, phase }
///   POST  /runner/{id}/keys      → { keys: [...] }
///   POST  /runner/{id}/testflight  → uploads .ipa to TestFlight
///   POST  /runner/{id}/handoff   → opens ASC on user's desktop Safari
///
/// This class is a thin client that the build / preview UI binds to. Today
/// it ships a believable stub so the rest of the app can be designed and
/// reviewed without a backend round-trip.
@MainActor
final class RemoteRunnerSession: ObservableObject {
    enum State {
        case idle, connecting, provisioning, streaming, failed

        var label: String {
            switch self {
            case .idle:         "Idle"
            case .connecting:   "Connecting to runner…"
            case .provisioning: "Booting iOS Simulator…"
            case .streaming:    "Streaming live"
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

    func sendToTestFlight() {
        Haptics.success()
        // Backend hits Apple's `altool` upload endpoint with the .ipa.
    }

    func openInDesktopXcode() {
        Haptics.tap(intensity: 0.6, sharpness: 0.6)
        // Sends a "wake" signal to the user's paired Mac via the CodeGenie
        // companion app, which `open`s the .xcodeproj on the desktop.
    }

    func handoffToAppStoreConnect() {
        Haptics.tap(intensity: 0.8, sharpness: 0.8)
        // Triggers the AppStoreConnectGuideView flow on the user's Mac via
        // the same companion bridge — Safari opens, the guide overlays.
    }
}
