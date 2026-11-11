import SwiftUI

/// Getting an AI key, for someone who has never heard of one.
///
/// A build needs a key from Anthropic or OpenAI, and a first-time user
/// meets that requirement in the middle of describing their app. This
/// sheet opens right there, explains what a key is and what it costs,
/// takes them to the page that issues one, and checks the key works
/// before they go back — so "Build it" either works or says why not.
struct KeySetupView: View {
    let provider: AIProvider
    var onDone: () -> Void

    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var reveal = false
    @State private var check: CheckState = .idle
    @FocusState private var focused: Bool

    enum CheckState: Equatable {
        case idle
        case checking
        case works
        case rejected(String)
        /// Saved, but the provider couldn't be reached to confirm it.
        case unconfirmed(String)
    }

    private var verdict: CredentialCheck.Verdict {
        CredentialCheck.providerKey(draft, for: provider)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        explainer
                        steps
                        entry
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Connect \(provider.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            draft = provider == .anthropic ? creds.anthropicKey : creds.openaiKey
        }
    }

    private var explainer: some View {
        GlassSurface(tier: .deep, corner: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's an API key?")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text("The AI that writes your app is run by \(provider.displayName), and they charge for it by usage. A key is a password that lets CodeGenie use your \(provider.displayName) account, so you pay them directly — usually well under a dollar per build — and CodeGenie adds nothing on top.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.82))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var steps: some View {
        GlassCard(title: "Get one — about 3 minutes", icon: "list.number", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open \(provider.displayName)'s console and create an account, or sign in.")
                step(2, "Add a payment method and a small amount of credit. $5 is plenty to start.")
                step(3, "Create a new API key and copy it. It's shown only once.")
                step(4, "Come back here and paste it below.")
                Link(destination: provider.consoleURL) {
                    Label("Open \(provider.displayName)'s console", systemImage: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityHint("Opens in your browser")
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number). \(text)")
    }

    private var entry: some View {
        GlassCard(title: "Your key", icon: "key.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Group {
                        if reveal {
                            TextField("Paste your key", text: $draft)
                        } else {
                            SecureField("Paste your key", text: $draft)
                        }
                    }
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                    .accessibilityLabel("\(provider.displayName) API key")
                    .onChange(of: draft) { _, _ in check = .idle }

                    Button { reveal.toggle() } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel(reveal ? "Hide key" : "Show key")
                }

                if !draft.isEmpty, let message = verdict.message {
                    Label(message, systemImage: verdict.isUsable ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(verdict.isUsable ? LiquidGlass.primaryText.opacity(0.7) : LiquidGlass.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                statusLine

                if check == .works || isUnconfirmed {
                    PrimaryButton(title: "Done", systemImage: "checkmark", style: .filled) {
                        onDone()
                        dismiss()
                    }
                } else {
                    PrimaryButton(
                        title: check == .checking ? "Checking…" : "Save and check",
                        systemImage: "lock.shield.fill",
                        style: .filled
                    ) {
                        focused = false
                        Task { await saveAndCheck() }
                    }
                    .disabled(!verdict.isUsable || check == .checking)
                    .opacity(verdict.isUsable ? 1 : 0.5)
                }

                Text("Kept in this iPhone's Keychain. It is sent only with your own builds, over an encrypted connection, and CodeGenie's servers don't keep it.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isUnconfirmed: Bool {
        if case .unconfirmed = check { return true }
        return false
    }

    @ViewBuilder
    private var statusLine: some View {
        switch check {
        case .idle, .checking:
            EmptyView()
        case .works:
            Label("\(provider.displayName) accepted this key. You're ready to build.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.success)
                .fixedSize(horizontal: false, vertical: true)
        case .rejected(let why):
            Label(why, systemImage: "xmark.octagon.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.error)
                .fixedSize(horizontal: false, vertical: true)
        case .unconfirmed(let why):
            Label(why, systemImage: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Checking

    /// Ask the provider itself whether the key is good, with a request
    /// that costs nothing: listing models. The key goes straight from
    /// this phone to the provider.
    private func saveAndCheck() async {
        let key = CredentialCheck.tidy(draft)
        check = .checking

        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=1")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200..<300:
                creds.setKey(key, for: provider)
                check = .works
                Haptics.success()
            case 401, 403:
                check = .rejected("\(provider.displayName) didn't accept this key. Copy it again from their console — keys are shown only once, so you may need to create a new one.")
                Haptics.error()
            default:
                creds.setKey(key, for: provider)
                check = .unconfirmed("Saved. \(provider.displayName) answered with an error (\(code)), so the key couldn't be confirmed. If your first build fails, check your credit balance there.")
                Haptics.warning()
            }
        } catch {
            creds.setKey(key, for: provider)
            check = .unconfirmed("Saved, but \(provider.displayName) couldn't be reached to confirm it. Check your connection.")
            Haptics.warning()
        }
    }
}
