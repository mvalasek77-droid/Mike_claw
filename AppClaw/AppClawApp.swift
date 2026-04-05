import SwiftUI
import BackgroundTasks

@main
struct AppClawApp: App {

    @StateObject private var appState = AppState()

    init() {
        // Register BGProcessingTask as early as possible (before first scene)
        HermesDreamEngine.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)   // always dark — OpenClaw is a dark-first app
        }
    }
}

// MARK: - AppState

/// Single source of truth for app-level state shared across views.
@MainActor
final class AppState: ObservableObject {
    @Published var onboardingComplete: Bool
    @Published var privacyState: PrivacyConsentState = .notAsked

    init() {
        onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}

// MARK: - RootView

/// Gates between onboarding and the main chat interface.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var hermesReady = false

    var body: some View {
        Group {
            if !appState.onboardingComplete {
                OnboardingView()
            } else {
                ChatView()
            }
        }
        .task {
            // Load session state and start Hermes subsystems
            await HermesSessionState.shared.loadFromDisk()
            await HermesPrivacyGate.shared.configureHermesIfReady()
            hermesReady = true
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
                await HermesProactiveEngine.shared.refresh()
            }
        }
    }
}
