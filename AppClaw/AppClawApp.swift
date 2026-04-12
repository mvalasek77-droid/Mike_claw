import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct AppClawApp: App {
    @StateObject private var appState = AppState()

    init() {
        HermesDreamEngine.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AppMode

enum AppMode { case video, chat }

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var onboardingComplete: Bool
    @Published var notificationsEnabled: Bool = false
    /// Toggles between the persistent TikTok companion view and the text chat view.
    @Published var currentMode: AppMode = .video

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    /// Called at the end of the onboarding flow.
    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}

// MARK: - RootView
//
// State machine:
//   onboardingComplete == false  → OnboardingView   (pick name, companion, permissions)
//   currentMode == .chat         → ChatView          (text chat)
//   currentMode == .video        → CompanionTikTokView (full-screen TikTok-style companion)

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.onboardingComplete {
                CompanionOnboardingView()
                    .environmentObject(appState)
                    .transition(.opacity)
            } else if appState.currentMode == .chat {
                ChatView()
                    .transition(.opacity)
            } else {
                CompanionTikTokView()
                    .environmentObject(appState)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.currentMode)
        .animation(.easeInOut(duration: 0.4), value: appState.onboardingComplete)
        .task {
            await HermesSessionState.shared.loadFromDisk()
            await HermesPrivacyGate.shared.configureHermesIfReady()

            // Boot all engines
            _ = IntimacyScalingEngine.shared
            _ = PsychologicalProfiler.shared
            _ = TrackingEngine.shared
            _ = ProactiveSuggestionController.shared

            // Start companion data tracker — respects TrackingPermissions exactly.
            // Called here so calendar/reminder scans run fresh on each launch.
            let persona = UserPersona.load()
            await CompanionDataTracker.shared.updatePermissions(persona.trackingPermissions, persona: persona)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            Task {
                await HermesIntegration.shared.logSessionEnd()
                HermesDreamEngine.shared.scheduleNextDream()
                await HermesKairos.shared.pause()
                // Flush all memory to disk before the app is suspended
                try? await HermesMemory.shared.persistNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await HermesPrivacyGate.shared.configureHermesIfReady()
                await ProactiveSuggestionController.shared.processQueue()
                // Re-scan on foreground — new events may have been added.
                let persona = UserPersona.load()
                await CompanionDataTracker.shared.updatePermissions(persona.trackingPermissions, persona: persona)
            }
        }
    }
}

// MARK: - Stub singletons referenced in RootView.task
// Remove these as you implement each engine in its own file.

private final class IntimacyScalingEngine {
    static let shared = IntimacyScalingEngine()
    private init() {}
}

private final class PsychologicalProfiler {
    static let shared = PsychologicalProfiler()
    private init() {}
}

private final class TrackingEngine {
    static let shared = TrackingEngine()
    private init() {}
}

private final class ProactiveSuggestionController {
    static let shared = ProactiveSuggestionController()
    private init() {}
    func processQueue() async {}
}
