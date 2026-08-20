import SwiftUI
import AuthenticationServices

/// Sign-in card on Profile. Guest state still works fully — signing
/// in unlocks cloud sync (once the backend exists) so state follows
/// you across devices.
struct AuthCard: View {
    @EnvironmentObject var portfolio: PortfolioService
    @ObservedObject var auth = AuthService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: auth.isSignedIn
                      ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                    .foregroundStyle(auth.isSignedIn ? .green : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.isSignedIn ? "Signed in with Apple" : "Playing as a guest")
                        .font(.subheadline.weight(.bold))
                    Text(auth.isSignedIn
                         ? (auth.signedInEmail ?? "Your positions and status sync across devices.")
                         : "Sign in to sync positions, XP, and badges across devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if auth.isSignedIn {
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Label("Sign out", systemImage: "arrow.backward.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        AuthService.shared.startSignInFromResult(auth)
                    case .failure(let error):
                        AuthService.shared.recordError(error.localizedDescription)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
            }

            if let err = auth.lastError {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground)))
    }
}
