import SwiftUI

/// Thin wrapper around `TutorialView` for first-launch onboarding.
///
/// Kept as its own type so the app root can branch on it without
/// importing tutorial mode logic.
struct OnboardingView: View {
    var onFinish: () -> Void

    var body: some View {
        TutorialView(mode: .onboarding, onFinish: onFinish)
    }
}

#Preview {
    ZStack {
        LiquidGlassBackground().ignoresSafeArea()
        OnboardingView { }
    }
}
