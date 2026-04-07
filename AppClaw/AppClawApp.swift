import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct AppClawApp: App {
    @StateObject private var appState = AppState()

    init() {
        HermesDreamEngine.shared.registerBackgroundTask()
        // Reset avatar-seen on each launch so you always get the reveal on first run post-onboarding
        // (Comment out to disable reset during development)
        // UserDefaults.standard.removeObject(forKey: "claw.seenAvatar")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var onboardingComplete: Bool
    @Published var notificationsEnabled: Bool = false
    @Published var companionSeenAvatar: Bool

    init() {
        onboardingComplete   = UserDefaults.standard.bool(forKey: "onboardingComplete")
        companionSeenAvatar  = UserDefaults.standard.bool(forKey: "claw.seenAvatar")
    }

    /// Called at the end of the onboarding flow.
    func completeOnboarding() {
        companionSeenAvatar = false
        UserDefaults.standard.removeObject(forKey: "claw.seenAvatar")
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    /// Called after the user dismisses the avatar reveal screen.
    func markAvatarSeen() {
        companionSeenAvatar = true
        UserDefaults.standard.set(true, forKey: "claw.seenAvatar")
    }
}

// MARK: - RootView
//
// State machine:
//   onboardingComplete == false  → OnboardingView  (pick name, companion, permissions)
//   onboardingComplete == true
//     companionSeenAvatar == false → CompanionFaceTimeView  (one-time avatar reveal)
//     companionSeenAvatar == true  → ChatView               (main app)

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.onboardingComplete {
                CompanionOnboardingView()
                    .environmentObject(appState)
                    .transition(.opacity)
            } else if !appState.companionSeenAvatar {
                CompanionFaceTimeView()
                    .environmentObject(appState)
                    .transition(.opacity)
            } else {
                ChatView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.companionSeenAvatar)
        .animation(.easeInOut(duration: 0.4), value: appState.onboardingComplete)
        .task {
            await HermesSessionState.shared.loadFromDisk()
            await HermesPrivacyGate.shared.configureHermesIfReady()

            // Boot all engines
            _ = IntimacyScalingEngine.shared
            _ = PsychologicalProfiler.shared
            _ = TrackingEngine.shared
            _ = ProactiveSuggestionController.shared
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            Task {
                await HermesIntegration.shared.logSessionEnd()
                HermesDreamEngine.shared.scheduleNextDream()
                await HermesKairos.shared.pause()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await HermesPrivacyGate.shared.configureHermesIfReady()
                await ProactiveSuggestionController.shared.processQueue()
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
