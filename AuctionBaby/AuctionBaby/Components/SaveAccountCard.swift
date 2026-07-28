import SwiftUI
import AuthenticationServices

/// "Save your account" card shown at the top of onboarding.
///
/// Three states, driven by `AuthService`:
///   • **Not configured** (`AB_AUTH_URL` blank) → the card is hidden
///     entirely and the app runs local-only exactly as it does in Demo Mode.
///   • **Not signed in** → the discreet card with a real Sign in with Apple
///     button. Explains the value ("survives a phone reset") in one line.
///   • **Signed in** → a subtle "Signed in with Apple" confirmation, optional
///     email underneath.
///
/// Extracted from `OnboardingView` so the SIWA UI is one place: the sheet
/// and any future settings screen can reuse the same component.
///
/// On successful sign-in the card fires `onSignedIn` (with the seeded name,
/// if Apple returned one) so the containing view can pre-fill fields and kick
/// off downstream flows (push permission, DOB, etc.).
struct SaveAccountCard: View {
    @EnvironmentObject private var auth: AuthService

    /// Called after a successful `signInWithApple` exchange. The name is
    /// whatever Apple returned on FIRST sign-in (nil otherwise — Apple only
    /// gives it once, ever).
    var onSignedIn: (RemoteUser) -> Void = { _ in }

    var body: some View {
        if !auth.isEnabled {
            EmptyView()
        } else if auth.isSignedIn {
            signedInState
        } else {
            signInState
        }
    }

    // MARK: - Signed in

    private var signedInState: some View {
        GlassCard(title: "Save your account",
                  icon: "person.crop.circle.badge.checkmark",
                  tint: Theme.gold) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.verify)
                    .font(.system(size: 18, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in with Apple")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    if let email = auth.user?.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                    } else {
                        Text("Your account will survive a reinstall.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: - Not signed in

    private var signInState: some View {
        GlassCard(title: "Save your account",
                  icon: "person.crop.circle.badge.checkmark",
                  tint: Theme.gold) {
            Text("Optional. Sign in with Apple so your profile and matches survive a phone reset or reinstall. You still fill everything below.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerS))
            .disabled(auth.inFlight)
            .opacity(auth.inFlight ? 0.6 : 1)
            if let error = auth.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            Task {
                let outcome = await auth.signInWithApple(credential)
                if case .success(_, let user) = outcome {
                    onSignedIn(user)
                }
            }
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
            auth.lastError = "Sign in with Apple failed. Try again, or continue without it."
        }
    }
}
