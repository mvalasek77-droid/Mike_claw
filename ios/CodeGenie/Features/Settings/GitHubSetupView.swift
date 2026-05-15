import SwiftUI

/// Three-step, hand-holding walkthrough for users who have never touched
/// GitHub. The whole point is that someone who doesn't know what
/// "version control" means can finish this and end up with their PAT
/// safely in the Keychain — without us assuming any prior knowledge.
///
/// Step 1 — explainer ("what's GitHub, do I need an account?")
/// Step 2 — token generation ("here's the exact page, here's what to tick")
/// Step 3 — paste + verify
struct GitHubSetupView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var usernameDraft: String = ""
    @State private var patDraft: String = ""
    @State private var repoDraft: String = ""
    @State private var revealPAT: Bool = false
    @State private var saved: Bool = false

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    progressBar
                    Group {
                        switch step {
                        case 0: explainerStep
                        case 1: tokenStep
                        default: pasteStep
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            usernameDraft = creds.githubUsername
            patDraft      = creds.githubPAT
            repoDraft     = creds.githubDefaultRepo
            if creds.hasGithub { step = 2 }
        }
    }

    // MARK: Header + progress

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(step > 0 ? 0.9 : 0.25))
                    .onTapGesture {
                        guard step > 0 else { return }
                        withAnimation(LiquidGlass.motion) { step -= 1 }
                        Haptics.selection()
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHidden(step == 0)
                Text("Connect GitHub")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text(stepSubtitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepSubtitle: String {
        switch step {
        case 0: "First time here? We'll walk you through it."
        case 1: "Generate a one-time token so CodeGenie can push your code."
        default: "Paste it below and we'll keep it safe in the iOS Keychain."
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of 3")
    }

    // MARK: Step 0 — explainer

    private var explainerStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "What is GitHub?", icon: "questionmark.circle.fill", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    explainerRow(
                        icon: "shippingbox.fill",
                        title: "A safe place for your code",
                        body: "Think Dropbox or iCloud — but built for source code. Every change is saved with a tag so you can roll back if a build breaks something."
                    )
                    explainerRow(
                        icon: "person.2.fill",
                        title: "Share or collaborate later",
                        body: "If a friend or contractor ever helps with the app, you'll send them a GitHub link. Same if you switch Macs."
                    )
                    explainerRow(
                        icon: "checkmark.shield.fill",
                        title: "Optional — your app still ships without it",
                        body: "CodeGenie can build and submit to TestFlight without GitHub. We recommend it as a backup so a year of work isn't on one Mac."
                    )
                }
            }

            GlassCard(title: "Do you already have an account?", icon: "person.crop.circle.badge.questionmark", tint: LiquidGlass.accentSecondary) {
                VStack(spacing: 10) {
                    PrimaryButton(title: "Yes — I have a GitHub account", systemImage: "checkmark.circle.fill", style: .filled) {
                        withAnimation(LiquidGlass.motion) { step = 1 }
                    }
                    Link(destination: URL(string: "https://github.com/signup")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                            Text("No — open github.com/signup in Safari")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                    }
                    .accessibilityHint("Opens the GitHub signup page in your browser")

                    Text("Free. Email + password is enough — you don't need any paid plan.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            Button("I'll skip GitHub for now") {
                Haptics.selection()
                dismiss()
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, 4)
            .accessibilityHint("Close without connecting GitHub")
        }
    }

    private func explainerRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    // MARK: Step 1 — token generation walkthrough

    private var tokenStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Generate a token", icon: "key.fill", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A token is like a one-time password GitHub creates just for CodeGenie. You can revoke it later from your GitHub settings — your real password never leaves Apple's keyboard.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))

                    Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=CodeGenie")!) {
                        HStack(spacing: 10) {
                            Image(systemName: "safari.fill")
                            Text("Open token page")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(LiquidGlass.auroraGradient, in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .accessibilityHint("Opens GitHub's new token page in your browser, pre-filled for CodeGenie")
                }
            }

            GlassCard(title: "On the GitHub page", icon: "list.number", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    walkRow(num: 1, body: "Sign in if asked.")
                    walkRow(num: 2, body: "The note will already say \"CodeGenie\" — leave it.")
                    walkRow(num: 3, body: "Set Expiration to 90 days (you can renew later).")
                    walkRow(num: 4, body: "Under Select scopes, tick the box that says **repo**. Nothing else.")
                    walkRow(num: 5, body: "Scroll down and tap Generate token.")
                    walkRow(num: 6, body: "Copy the long string starting with `ghp_…` — you only see it once.")
                    walkRow(num: 7, body: "Come back here and tap Continue.")
                }
            }

            PrimaryButton(title: "I copied my token — continue", systemImage: "arrow.right.circle.fill", style: .filled) {
                withAnimation(LiquidGlass.motion) { step = 2 }
            }
        }
    }

    private func walkRow(num: Int, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LiquidGlass.accent.opacity(0.85)))
            Text(.init(body))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step 2 — paste + verify

    private var pasteStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Your GitHub username", icon: "person.fill", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The handle on your GitHub profile, e.g. `octocat`.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    fieldRow("octocat", text: $usernameDraft, secure: false)
                }
            }

            GlassCard(title: "Paste your token", icon: "key.fill", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Starts with `ghp_…`. Stays on this device — never sent to our servers.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack {
                        Group {
                            if revealPAT {
                                TextField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $patDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $patDraft)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                        Button { revealPAT.toggle() } label: {
                            Image(systemName: revealPAT ? "eye.slash" : "eye")
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel(revealPAT ? "Hide token" : "Show token")
                    }
                }
            }

            GlassCard(title: "Default repo (optional)", icon: "folder.fill", tint: LiquidGlass.accentSecondary) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If you already created an empty repo on GitHub, paste it as `username/repo`. Leave blank and CodeGenie will pick a name based on your app.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    fieldRow("\(usernameDraft.isEmpty ? "octocat" : usernameDraft)/tide-times", text: $repoDraft, secure: false)
                }
            }

            PrimaryButton(title: saved ? "Saved — close" : "Save to Keychain", systemImage: saved ? "checkmark.seal.fill" : "lock.shield.fill", style: .filled) {
                creds.setGithubUsername(usernameDraft)
                creds.setGithubPAT(patDraft)
                creds.setGithubDefaultRepo(repoDraft)
                Haptics.success()
                if saved {
                    dismiss()
                } else {
                    withAnimation { saved = true }
                }
            }
            .disabled(usernameDraft.isEmpty || patDraft.isEmpty)
            .opacity((usernameDraft.isEmpty || patDraft.isEmpty) ? 0.5 : 1)

            if saved {
                Label("Stored in iOS Keychain", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ placeholder: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }
}
