import SwiftUI

/// Decides what to show at launch: a brief restore check, the onboarding flow
/// for first-time bros, or the five-tab app once an identity is established.
///
/// Auth resolves *before* the rest of the dependency graph is built, so mock
/// seed data (e.g. "your" demo post) is authored by whoever `Session.me`
/// turns out to be — not a placeholder that gets swapped out from under it.
@MainActor
@Observable
final class LaunchCoordinator {
    enum Phase: Equatable {
        case checking
        case onboarding
        case ready
    }

    private(set) var phase: Phase = .checking
    private(set) var container: AppContainer?

    func start() async {
        let authService = AppContainer.makeAuthService()
        if let user = await authService.restoreSession() {
            Session.shared.signIn(as: user)
            container = AppContainer.resolve()
            phase = .ready
        } else {
            phase = .onboarding
        }
    }

    func onboardingFinished() {
        container = AppContainer.resolve()
        phase = .ready
    }

    func signedOut() {
        container = nil
        phase = .onboarding
    }
}

struct LaunchGateView: View {
    @State var launch = LaunchCoordinator()

    var body: some View {
        Group {
            switch launch.phase {
            case .checking:
                LaunchSplashView()
            case .onboarding:
                OnboardingView(authService: AppContainer.makeAuthService()) {
                    launch.onboardingFinished()
                }
            case .ready:
                if let container = launch.container {
                    RootView(container: container, onSignOut: { launch.signedOut() })
                }
            }
        }
        .task { await launch.start() }
    }
}

private struct LaunchSplashView: View {
    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            SloganView()
            ProgressView()
        }
    }
}
