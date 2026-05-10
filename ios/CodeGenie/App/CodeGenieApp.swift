import SwiftUI

@main
struct CodeGenieApp: App {
    @StateObject private var session = AppSession()
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(session.colorScheme)
                .tint(LiquidGlass.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            if hasFinishedOnboarding {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.6)) {
                        hasFinishedOnboarding = true
                    }
                    Haptics.success()
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.55), value: hasFinishedOnboarding)
    }
}
