import SwiftUI

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
    @State private var revealP8: Bool = false
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
                    .accessibilityAddTraits(.isHeader)
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
            .disabled(teamDraft.count < 6)
            .opacity(teamDraft.count < 6 ? 0.5 : 1)
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
                    walkRow(num: 3, body: "Set Access to **App Manager** — that's the tier needed for TestFlight uploads.")
                    walkRow(num: 4, body: "Tap Generate. The page now shows the **Issuer ID** at the top and your new key in the list.")
                    walkRow(num: 5, body: "Copy the **Key ID** (10 characters, e.g. `ABCDEFGH12`).")
                    walkRow(num: 6, body: "Tap **Download API Key** — you can only download the `.p8` file once.")
                    walkRow(num: 7, body: "Open it in any text editor on your Mac, copy everything between (and including) the BEGIN and END lines.")
                }
            }

            PrimaryButton(title: "Got the .p8 file — continue", systemImage: "arrow.right.circle.fill", style: .filled) {
                withAnimation(LiquidGlass.motion) { step = 3 }
            }
        }
    }

    // MARK: Step 3 — paste

    private var pasteStep: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Issuer ID", icon: "number.square.fill", tint: LiquidGlass.accent) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Long UUID at the top of the API page. Same for every key on your team.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    fieldRow("00000000-0000-0000-0000-000000000000", text: $issuerDraft, secure: false)
                }
            }
            GlassCard(title: "Key ID", icon: "key.fill", tint: LiquidGlass.accentSecondary) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("10 characters. Listed next to the key you just generated.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    fieldRow("ABCDEFGH12", text: $keyDraft, secure: false)
                }
            }
            GlassCard(title: ".p8 contents", icon: "doc.text.fill", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Paste from the file you downloaded.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        Spacer()
                        Button { revealP8.toggle() } label: {
                            Image(systemName: revealP8 ? "eye.slash" : "eye")
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        }
                        .accessibilityLabel(revealP8 ? "Hide private key" : "Show private key")
                    }
                    Group {
                        if revealP8 {
                            TextEditor(text: $p8Draft)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 110)
                        } else {
                            SecureField("-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----", text: $p8Draft)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                }
            }

            PrimaryButton(title: saved ? "Saved — close" : "Save to Keychain", systemImage: saved ? "checkmark.seal.fill" : "lock.shield.fill", style: .filled) {
                creds.setASCIssuerID(issuerDraft)
                creds.setASCKeyID(keyDraft)
                creds.setASCP8(p8Draft)
                Haptics.success()
                if saved {
                    dismiss()
                } else {
                    withAnimation { saved = true }
                }
            }
            .disabled(issuerDraft.isEmpty || keyDraft.isEmpty || p8Draft.isEmpty)
            .opacity((issuerDraft.isEmpty || keyDraft.isEmpty || p8Draft.isEmpty) ? 0.5 : 1)

            if saved {
                Label("Stored in iOS Keychain", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
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
