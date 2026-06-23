import SwiftUI

@main
struct ScreenshotStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var store = ProjectStore()
    @StateObject private var purchases = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(store)
                .environmentObject(purchases)
                .preferredColorScheme(appState.colorScheme)
                .tint(LiquidGlass.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ProjectStore
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    @State private var splashDone = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            } else if !hasFinishedOnboarding {
                OnboardingView {
                    Motion.run(.smooth(duration: 0.6)) { hasFinishedOnboarding = true }
                    Haptics.success()
                }
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
                    .task { SampleContent.seedIfNeeded(into: store) }
            }
        }
        .motion(Motion.smooth, value: hasFinishedOnboarding)
        .motion(Motion.smooth, value: splashDone)
    }
}
