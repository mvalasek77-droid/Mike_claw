import SwiftUI
import AuthenticationServices

/// First-run account registration, styled after Amazon KDP's warm "ink + amber"
/// sign-up. Offers Sign in with Apple or a manual publisher form. This is the
/// publisher account; per-title registration happens later in the Publish flow.
struct RegisterView: View {
    @EnvironmentObject private var store: MarketplaceStore

    @State private var name = ""
    @State private var email = ""
    @State private var agreed = false
    @State private var legalDoc: LegalDoc?
    @State private var authError: String?

    private var canContinue: Bool {
        !name.trimmed.isEmpty && email.contains("@") && agreed
    }

    var body: some View {
        ZStack {
            // KDP-style warm backdrop.
            LinearGradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.04),
                                    Color(red: 0.05, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            LinearGradient(colors: [Theme.kdp.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Create your publisher account")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)

                            LabeledField(label: "Publisher / pen name", text: $name,
                                         placeholder: "e.g. Mike Valasek", icon: "person.text.rectangle")
                            LabeledField(label: "Email", text: $email,
                                         placeholder: "you@example.com", icon: "envelope",
                                         keyboard: .emailAddress)

                            Button {
                                Haptics.selection()
                                agreed.toggle()
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(agreed ? Theme.kdp : Theme.inkFaint)
                                    (Text("I agree to the AI Marketplace ")
                                     + Text("Content & AI Disclosure Terms").foregroundColor(Theme.kdp)
                                     + Text(" and confirm I hold the rights to anything I publish."))
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(Theme.inkSoft)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)

                            HStack(spacing: 16) {
                                Button("Terms of Use") { legalDoc = .terms }
                                Button("Privacy Policy") { legalDoc = .privacy }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.kdp)
                        }
                    }

                    PrimaryButton(title: "Create account", systemImage: "arrow.right",
                                  tint: Theme.kdp, enabled: canContinue) {
                        withAnimation { store.register(name: name, email: email) }
                    }

                    appleSignIn

                    benefitRow
                }
                .screenPadding()
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $legalDoc) { LegalSheet(doc: $0) }
        .alert("Sign in failed", isPresented: .constant(authError != nil)) {
            Button("OK") { authError = nil }
        } message: { Text(authError ?? "") }
    }

    private var appleSignIn: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                Text("or").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.inkFaint)
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
            }
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!agreed)
            .opacity(agreed ? 1 : 0.5)
            if !agreed {
                Text("Agree to the terms above to continue.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            withAnimation {
                store.register(name: fullName, email: cred.email ?? "", appleUserID: cred.user)
            }
        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            if code == .canceled { return }
            authError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Marketplace")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Direct Publishing")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Theme.kdp)
                }
            }
            Text("Publish AI-made novels, music and film. Pass the AI Editor's 85% commercial bar and go live to millions of viewers.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var benefitRow: some View {
        HStack(spacing: 10) {
            benefit("85%", "you keep")
            benefit("85%", "quality bar")
            benefit("3", "media types")
        }
    }

    private func benefit(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.kdp)
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var icon: String? = nil
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.inkFaint)
                        .frame(width: 18)
                }
                TextField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled(keyboard == .emailAddress)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerS).strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        }
    }
}
