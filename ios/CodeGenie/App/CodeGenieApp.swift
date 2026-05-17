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
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms = false
    @State private var splashDone: Bool = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            } else if hasFinishedOnboarding && hasAcceptedTerms {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
            } else if hasFinishedOnboarding {
                TermsAndPrivacyView {
                    Motion.run(.smooth(duration: 0.6)) {
                        hasAcceptedTerms = true
                    }
                    Haptics.success()
                }
                .transition(.opacity)
            } else {
                OnboardingView {
                    Motion.run(.smooth(duration: 0.6)) {
                        hasFinishedOnboarding = true
                    }
                    Haptics.success()
                }
                .transition(.opacity)
            }
        }
        .motion(Motion.smooth, value: hasFinishedOnboarding)
        .motion(Motion.smooth, value: hasAcceptedTerms)
        .motion(Motion.smooth, value: splashDone)
    }
}
