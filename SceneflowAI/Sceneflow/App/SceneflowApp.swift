import SwiftUI

@main
struct SceneflowApp: App {
    @StateObject private var store = ScreenplayStore()
    @StateObject private var ai = AIService()
    @StateObject private var entitlements = Entitlements()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(ai)
                .environmentObject(entitlements)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false
    @State private var splashDone = false

    var body: some View {
        ZStack {
            AmbientBackground().ignoresSafeArea()

            if !splashDone {
                SplashView { splashDone = true }
                    .transition(.opacity)
            } else if !hasFinishedOnboarding {
                OnboardingView {
                    Motion.run(.smooth) { hasFinishedOnboarding = true }
                    Haptics.success()
                }
                .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .motion(Motion.smooth, value: splashDone)
        .motion(Motion.smooth, value: hasFinishedOnboarding)
    }
}

struct SplashView: View {
    var onFinish: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Palette.marqueeGradient)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            Text("Sceneflow")
                .font(.displayLarge)
                .foregroundStyle(Palette.primaryText)
                .opacity(appeared ? 1 : 0)
            Text("Write. Structure. Sharpen.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Motion.run(.spring) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { onFinish() }
        }
    }
}
