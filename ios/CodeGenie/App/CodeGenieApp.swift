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
                .onAppear {
                    // Auto-restore any in-progress build state from a
                    // previous session (app was killed / backgrounded).
                    // Only attempt after onboarding is complete and terms
                    // are accepted — the RootView guards those gates.
                    if hasFinishedOnboarding && hasAcceptedTerms(session: session) {
                        session.restoreIfPossible()
                    }
                }
        }
    }

    private func hasAcceptedTerms(session: AppSession) -> Bool {
        UserDefaults.standard.bool(forKey: "hasAcceptedTerms")
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    @AppStorage("hasAcceptedTerms") private var hasAcceptedTerms = false
    @AppStorage("hasSeenSplash") private var hasSeenSplash = false
    @State private var splashReady: Bool = false

    var body: some View {
        ZStack {
            LiquidGlassBackground()
                .ignoresSafeArea()

            if !splashReady && !hasSeenSplash {
                SplashView { 
                    hasSeenSplash = true
                    withAnimation(.easeOut(duration: 0.3)) { splashReady = true }
                }
                    .transition(.opacity)
            } else if !hasFinishedOnboarding {
                OnboardingView {
                    Motion.run(.smooth(duration: 0.6)) {
                        hasFinishedOnboarding = true
                    }
                    Haptics.success()
                }
                .transition(.opacity)
            } else if !hasAcceptedTerms {
                TermsAndPrivacyView {
                    Motion.run(.smooth(duration: 0.6)) {
                        hasAcceptedTerms = true
                    }
                }
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
            }
        }
        .motion(Motion.smooth, value: hasFinishedOnboarding)
        .motion(Motion.smooth, value: hasAcceptedTerms)
        .motion(Motion.smooth, value: splashReady)
    }
}