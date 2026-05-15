import SwiftUI

/// One-screen onboarding for the user's Apple Developer Program
/// credentials. CodeGenie needs these before it can sign builds and
/// upload to TestFlight on the user's behalf.
///
/// Two paths supported:
///   1. **App Store Connect API key (recommended).** Issuer ID + Key ID
///      + the .p8 PEM. No 2FA prompts on every build.
///   2. **Apple ID + app-specific password (legacy fallback).** Easier
///      to set up but Apple may surface 2FA challenges; useful for
///      one-off uploads.
///
/// All secrets land in the iOS Keychain via `Credentials`. Only the
/// non-secret IDs persist to UserDefaults.
struct AppleDevSetupView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    @State private var teamID: String = ""
    @State private var keyID: String = ""
    @State private var issuerID: String = ""
    @State private var p8: String = ""
    @State private var appPwd: String = ""
    @State private var revealP8: Bool = false
    @State private var revealPwd: Bool = false
    @State private var savedAt: Date?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    statusBlock
                    teamIDBlock
                    ascAPIBlock
                    legacyBlock
                    helpBlock
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            teamID = creds.appleTeamID
            keyID = creds.ascKeyID
            issuerID = creds.ascIssuerID
            p8 = creds.ascP8PEM
            appPwd = creds.appSpecificPassword
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apple Developer Program")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("CodeGenie signs builds and uploads to TestFlight using these. Stored in the iOS Keychain — never sent to our servers.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBlock: some View {
        let ok = creds.hasAppleDevCreds
        return GlassCard(
            title: ok ? "Connected" : "Not connected yet",
            icon: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
            tint: ok ? LiquidGlass.success : LiquidGlass.warning
        ) {
            Text(ok
                 ? "You're set — Build → Submit will sign and upload automatically."
                 : "Add your Team ID + either an ASC API key (preferred) or Apple ID + app-specific password.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
        }
    }

    private var teamIDBlock: some View {
        GlassCard(title: "Team ID", icon: "person.2.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Find this at developer.apple.com → Membership. 10-character alphanumeric, e.g. ABCD123456.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                fieldRow("ABCD123456", text: $teamID, secure: false)
                Button("Save Team ID") {
                    creds.setAppleTeamID(teamID)
                    savedAt = .now
                    Haptics.success()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
            }
        }
    }

    private var ascAPIBlock: some View {
        GlassCard(title: "App Store Connect API key", icon: "key.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended path. Generate at appstoreconnect.apple.com → Users and Access → Keys.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))

                Text("Issuer ID").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.6)).textCase(.uppercase)
                fieldRow("00000000-0000-0000-0000-000000000000", text: $issuerID, secure: false)

                Text("Key ID").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.6)).textCase(.uppercase)
                fieldRow("ABCDEFGH12", text: $keyID, secure: false)

                HStack {
                    Text(".p8 contents").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.6)).textCase(.uppercase)
                    Spacer()
                    Button { revealP8.toggle() } label: {
                        Image(systemName: revealP8 ? "eye.slash" : "eye")
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    }
                    .accessibilityLabel(revealP8 ? "Hide private key" : "Show private key")
                }
                Group {
                    if revealP8 {
                        TextEditor(text: $p8)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 90)
                    } else {
                        SecureField("-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----", text: $p8)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(LiquidGlass.primaryText)
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                PrimaryButton(title: "Save ASC API key", systemImage: "checkmark.seal", style: .filled) {
                    creds.setASCKeyID(keyID)
                    creds.setASCIssuerID(issuerID)
                    creds.setASCP8(p8)
                    savedAt = .now
                    Haptics.success()
                }
                .disabled(keyID.isEmpty || issuerID.isEmpty || p8.isEmpty)
                .opacity((keyID.isEmpty || issuerID.isEmpty || p8.isEmpty) ? 0.5 : 1)
            }
        }
    }

    private var legacyBlock: some View {
        GlassCard(title: "Apple ID + app-specific password", icon: "lock.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Fallback path. Generate at appleid.apple.com → Sign-In and Security → App-Specific Passwords.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))

                HStack {
                    Text("Password").font(.caption2).foregroundStyle(LiquidGlass.primaryText.opacity(0.6)).textCase(.uppercase)
                    Spacer()
                    Button { revealPwd.toggle() } label: {
                        Image(systemName: revealPwd ? "eye.slash" : "eye")
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    }
                    .accessibilityLabel(revealPwd ? "Hide password" : "Show password")
                }
                fieldRow("abcd-efgh-ijkl-mnop", text: $appPwd, secure: !revealPwd)

                PrimaryButton(title: "Save", systemImage: "checkmark", style: .glass) {
                    creds.setAppSpecificPassword(appPwd)
                    savedAt = .now
                    Haptics.success()
                }
                .disabled(appPwd.isEmpty)
                .opacity(appPwd.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var helpBlock: some View {
        GlassCard(title: "Where do these come from?", icon: "questionmark.circle.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: URL(string: "https://developer.apple.com/account")!) {
                    Label("Developer account → Membership", systemImage: "arrow.up.right.square")
                        .foregroundStyle(LiquidGlass.accent)
                }
                Link(destination: URL(string: "https://appstoreconnect.apple.com/access/api")!) {
                    Label("ASC → Users and Access → Keys", systemImage: "arrow.up.right.square")
                        .foregroundStyle(LiquidGlass.accent)
                }
                Link(destination: URL(string: "https://appleid.apple.com/account/manage")!) {
                    Label("Apple ID → app-specific passwords", systemImage: "arrow.up.right.square")
                        .foregroundStyle(LiquidGlass.accent)
                }
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }

    // MARK: Helpers

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
