import SwiftUI

/// Identity-based onboarding: welcome → claim a handle + display name → agree
/// to the Code of Conduct. Moderation/Code of Conduct is first-class per the
/// product spec, so it's a required step here, not a buried settings link.
struct OnboardingView: View {
    @State private var model: OnboardingViewModel
    let onFinished: () -> Void

    init(authService: AuthService, onFinished: @escaping () -> Void) {
        _model = State(initialValue: OnboardingViewModel(service: authService))
        self.onFinished = onFinished
    }

    var body: some View {
        VStack {
            Spacer(minLength: Tokens.Spacing.xl)
            Group {
                switch model.step {
                case .welcome: welcomeStep
                case .identity: identityStep
                case .codeOfConduct: codeOfConductStep
                }
            }
            .padding(.horizontal, Tokens.Spacing.xl)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            Spacer()
        }
        .animation(Tokens.Motion.gentle, value: model.step)
        .background(Tokens.Color.textPrimary.opacity(0.02))
    }

    private var welcomeStep: some View {
        VStack(spacing: Tokens.Spacing.xxl) {
            SloganView()
            Text("Connect, organize, and back each other up — your real self with friends, your handle in the Bro-hoods.")
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Get Bro'd In") { model.advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Text("Claim your identity").font(Tokens.Typography.title)
            Text("Your display name is who friends see. Your handle is how you show up in Bro-hoods.")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text("Display name").font(Tokens.Typography.caption.weight(.semibold))
                TextField("e.g. Marcus", text: $model.displayName)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text("Handle").font(Tokens.Typography.caption.weight(.semibold))
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(Tokens.Color.textSecondary)
                    TextField("ironbro", text: $model.handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .textFieldStyle(.roundedBorder)
                Text("Lowercase letters, numbers, underscores. 3–20 characters.")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }

            Button("Continue") { model.advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canContinueFromIdentity)
                .frame(maxWidth: .infinity)
        }
    }

    private var codeOfConductStep: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Text("Code of Conduct").font(Tokens.Typography.title)
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                conductRow("🤝", "Camaraderie over conflict — disagree without disrespect.")
                conductRow("🛡️", "No harassment, hate, or doxxing. Zero tolerance.")
                conductRow("💪", "Mentorship and accountability — lift each other up.")
                conductRow("🚩", "Report what's wrong instead of letting it slide.")
            }
            .padding(Tokens.Spacing.lg)
            .liquidGlass()

            Toggle(isOn: $model.agreedToCodeOfConduct) {
                Text("I agree to follow the MetaBro Code of Conduct")
                    .font(Tokens.Typography.caption.weight(.semibold))
            }

            if case .failed(let message) = model.phase {
                Text(message).font(Tokens.Typography.caption).foregroundStyle(.red)
            }

            Button {
                Task {
                    if await model.finish() { onFinished() }
                }
            } label: {
                if model.phase == .submitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Enter MetaBro").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canFinish)
        }
    }

    private func conductRow(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            Text(emoji)
            Text(text).font(Tokens.Typography.body)
        }
    }
}
