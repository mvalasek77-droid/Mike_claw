import SwiftUI
import UniformTypeIdentifiers

/// Four-step, hand-holding walkthrough for users who have never set up
/// an Apple Developer account. The existing `AppleDevSetupView` is the
/// power-user form (one screen, all fields). This wraps that form in
/// plain-English context so a first-timer understands what they're
/// signing up for, why they need both an Apple Developer account AND an
/// App Store Connect API key, and exactly what to click.
///
/// On completion, secrets land in the Keychain via the same
/// `Credentials` setters the power-user form uses — no duplicate state.
struct AppleDevWalkthroughView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    @State private var teamDraft: String = ""
    @State private var keyDraft: String = ""
    @State private var issuerDraft: String = ""
    @State private var p8Draft: String = ""
    @State private var saved: Bool = false
    @State private var showKeyFilePicker = false
    @State private var keyFileNote: String?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    progressBar
                    Group {
                        switch step {
                        case 0: signupStep
                        case 1: ascExplainerStep
                        case 2: keyGenStep
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
            teamDraft   = creds.appleTeamID
            keyDraft    = creds.ascKeyID
            issuerDraft = creds.ascIssuerID
            p8Draft     = creds.ascP8PEM
            if creds.hasAppleDevCreds { step = 3 }
        }
    }

    // MARK: Header + progress

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(step > 0 ? 0.9 : 0.25))
                    .onTapGesture {
                        guard step > 0 else { return }
                        withAnimation(LiquidGlass.motion) { step -= 1 }
                        Haptics.selection()
                    }
                    .accessibilityLabel("Back")
                    .accessibilityHidden(step == 0)
                Text("Apple Developer")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Spacer()
            }
            Text(stepSubtitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepSubtitle: String {
        switch step {
        case 0: "What you need to ship to the App Store."
        case 1: "Two Apple websites, one for each job."
        case 2: "Generate the key CodeGenie will use to upload."
        default: "Paste it below — it stays in your iOS Keychain."
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i <= step ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of 4")
    }

    // MARK: Step 0 — signup ($99/yr disclosure)

    private var signupStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Apple's $99/year program", icon: "applelogo", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    explainerRow(
                        icon: "dollarsign.circle.fill",
                        title: "Costs $99 USD per year",
                        body: "Apple charges everyone the same — solo developer or big studio. Without it, your app can't be sold or installed beyond your own device."
                    )
                    explainerRow(
                        icon: "person.fill",
                        title: "Use your existing Apple ID",
                        body: "The same one you use for iCloud and the App Store. You don't make a new account."
                    )
                    explainerRow(
                        icon: "clock.fill",
                        title: "Approval takes 24–48 hours",
                        body: "Apple reviews each new account. While you wait, CodeGenie can keep building and previewing on your phone."
                    )
                }
            }

            GlassCard(title: "Do you already have one?", icon: "questionmark.circle.fill", tint: LiquidGlass.accentSecondary) {
                VStack(spacing: 10) {
                    PrimaryButton(title: "Yes — I'm enrolled", systemImage: "checkmark.circle.fill", style: .filled) {
                        withAnimation(LiquidGlass.motion) { step = 1 }
                    }
                    Link(destination: URL(string: "https://developer.apple.com/programs/enroll/")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                            Text("No — open the enrollment page")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
                    }
                    Text("Come back here once Apple emails you that you're approved.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: Step 1 — ASC vs Dev Portal

    private var ascExplainerStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Two Apple websites", icon: "rectangle.split.2x1.fill", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 12) {
                    siteRow(
                        title: "developer.apple.com",
                        role: "Apple Developer Portal",
                        body: "Where you enroll and find your Team ID — a 10-character code that proves the build is yours."
                    )
                    Divider().background(.white.opacity(0.1))
                    siteRow(
                        title: "appstoreconnect.apple.com",
                        role: "App Store Connect (ASC)",
                        body: "Where finished builds live, where TestFlight invites go out, and where you fill in App Store metadata. You'll generate an API key here next."
                    )
                    Text("Same login. Different tools.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                        .padding(.top, 4)
                }
            }

            GlassCard(title: "What's a Team ID?", icon: "person.2.fill", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A 10-character code like `ABCD123456` that identifies you across Apple's tools. Find it at developer.apple.com → Membership.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    HStack(spacing: 10) {
                        Link(destination: URL(string: "https://developer.apple.com/account/#/membership/")!) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open Membership page")
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                        }
                        Spacer()
                    }
                    fieldRow("ABCD123456", text: $teamDraft, secure: false)
                    problem(teamDraft.isEmpty ? nil : CredentialCheck.teamID(teamDraft).message)
                    Button {
                        creds.setAppleTeamID(teamDraft)
                        Haptics.success()
                    } label: {
                        Text("Save Team ID")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.accent)
                    }
                }
            }

            PrimaryButton(title: "Continue", systemImage: "arrow.right.circle.fill", style: .filled) {
                creds.setAppleTeamID(teamDraft)
                withAnimation(LiquidGlass.motion) { step = 2 }
            }
            .disabled(!CredentialCheck.teamID(teamDraft).isUsable)
            .opacity(CredentialCheck.teamID(teamDraft).isUsable ? 1 : 0.5)
        }
    }

    // MARK: Step 2 — generate ASC API key

    private var keyGenStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Why a key?", icon: "key.fill", tint: LiquidGlass.accentSecondary) {
                Text("So CodeGenie can upload finished builds without prompting you for your Apple ID password every single time. The key is revocable — delete it from ASC any time and uploads stop.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            }

            GlassCard(title: "Open the right page", icon: "safari.fill", tint: LiquidGlass.accent) {
                Link(destination: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "safari.fill")
                        Text("Open ASC → Integrations → App Store Connect API")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(LiquidGlass.primaryText)
                }
            }

            GlassCard(title: "On that page", icon: "list.number", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 10) {
                    walkRow(num: 1, body: "Tap **Generate API Key** (or the **+** if you've used it before).")
                    walkRow(num: 2, body: "Name it `CodeGenie`.")
                    walkRow(num: 3, body: "Set Access to **App Manager**. If signing later fails with a permissions message, make a new key with **Admin** access instead — some accounts need it to create signing certificates.")
                    walkRow(num: 4, body: "Tap Generate. The page now shows the **Issuer ID** at the top and your new key in the list.")
                    walkRow(num: 5, body: "Copy the **Key ID** (10 characters, e.g. `ABCDEFGH12`).")
                    walkRow(num: 6, body: "Tap **Download API Key** — you can only download the `.p8` file once. On an iPhone it goes to the Files app, in Downloads.")
                    walkRow(num: 7, body: "Open it in any text editor on your Mac, copy everything between (and including) the BEGIN and END lines.")
                }
            }

            PrimaryButton(title: "Got the .p8 file — continue", systemImage: "arrow.right.circle.fill", style: .filled) {
                withAnimation(LiquidGlass.motion) { step = 3 }
            }
        }
    }

    // MARK: Step 3 — paste

    private var allCredentialsUsable: Bool {
        CredentialCheck.issuerID(issuerDraft).isUsable
            && CredentialCheck.keyID(keyDraft).isUsable
            && CredentialCheck.privateKey(p8Draft).isUsable
    }

    private var pasteStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "The key file", icon: "doc.badge.arrow.up.fill", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apple gave you a file named AuthKey_….p8. Choose it and CodeGenie reads the key and its ID for you.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(
                        title: CredentialCheck.privateKey(p8Draft).isUsable ? "Choose a different file" : "Choose the .p8 file",
                        systemImage: "folder",
                        style: CredentialCheck.privateKey(p8Draft).isUsable ? .glass : .filled
                    ) {
                        showKeyFilePicker = true
                    }
                    .accessibilityHint("Opens Files. Downloads from Safari are in the Downloads folder.")
                    if CredentialCheck.privateKey(p8Draft).isUsable {
                        Label("Key loaded.", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.success)
                    }
                    if let keyFileNote {
                        problem(keyFileNote)
                    }
                    DisclosureGroup("Paste the contents instead") {
                        VStack(alignment: .leading, spacing: 6) {
                            // A multi-line editor, never a secure
                            // field: a single-line field strips the
                            // line breaks the key is made of.
                            TextEditor(text: $p8Draft)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 110)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(LiquidGlass.primaryText)
                                .padding(10)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                                .privacySensitive()
                                .accessibilityLabel("Private key contents")
                            problem(p8Draft.isEmpty ? nil : CredentialCheck.privateKey(p8Draft).message)
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tint(LiquidGlass.accent)
                }
            }
            GlassCard(title: "Key ID", icon: "key.fill", tint: LiquidGlass.accentSecondary) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("10 characters, listed next to the key you just generated. It's also in the file's name.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    fieldRow("ABCDEFGH12", text: $keyDraft, secure: false)
                    problem(keyDraft.isEmpty ? nil : CredentialCheck.keyID(keyDraft).message)
                }
            }
            GlassCard(title: "Issuer ID", icon: "number.square.fill", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The long code with dashes above the list of keys. It's the same for every key on your team.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    fieldRow("00000000-0000-0000-0000-000000000000", text: $issuerDraft, secure: false)
                    problem(issuerDraft.isEmpty ? nil : CredentialCheck.issuerID(issuerDraft).message)
                }
            }

            PrimaryButton(title: saved ? "Saved — close" : "Save to Keychain", systemImage: saved ? "checkmark.seal.fill" : "lock.shield.fill", style: .filled) {
                if saved {
                    dismiss()
                    return
                }
                creds.setASCIssuerID(issuerDraft)
                creds.setASCKeyID(keyDraft)
                creds.setASCP8(p8Draft)
                Haptics.success()
                withAnimation { saved = true }
            }
            .disabled(!allCredentialsUsable)
            .opacity(allCredentialsUsable ? 1 : 0.5)

            if saved {
                Label("Stored in this iPhone's Keychain. It goes to your Mac when you upload, and nowhere else.", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fileImporter(
            isPresented: $showKeyFilePicker,
            allowedContentTypes: [.data, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            importKeyFile(result)
        }
    }

    /// Read the chosen file. Files outside the app's sandbox must be
    /// opened inside a security scope and the scope always released.
    private func importKeyFile(_ result: Result<[URL], Error>) {
        keyFileNote = nil
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result { keyFileNote = "Couldn't open that file. Try choosing it again." }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url), data.count < 64 * 1024,
              let text = String(data: data, encoding: .utf8)
        else {
            keyFileNote = "That file couldn't be read as a key. Choose the AuthKey_….p8 file Apple gave you."
            return
        }
        guard CredentialCheck.privateKey(text).isUsable else {
            keyFileNote = CredentialCheck.privateKey(text).message
            Haptics.error()
            return
        }
        p8Draft = text
        if let id = CredentialCheck.keyID(fromFileName: url.lastPathComponent) {
            keyDraft = id
        }
        saved = false
        Haptics.success()
    }

    @ViewBuilder
    private func problem(_ message: String?) -> some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

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
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            }
        }
    }

    private func siteRow(title: String, role: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(body)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
        }
    }

    private func walkRow(num: Int, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(num)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(LiquidGlass.accent.opacity(0.85)))
            Text(.init(body))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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
        .foregroundStyle(LiquidGlass.primaryText)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
    }
}
