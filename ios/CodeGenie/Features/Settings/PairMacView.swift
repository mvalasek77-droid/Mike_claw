import SwiftUI

/// UI flow for pairing the iPhone with the user's Mac companion daemon.
///
/// The path is Wi-Fi discovery plus one tap.
struct PairMacView: View {
    @StateObject private var bridge = CompanionBridge()
    @StateObject private var creds = Credentials.shared
    @State private var pairingMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let companionGitHubURL = URL(string: "https://github.com/mvalasek77-droid/Mike_claw/tree/replay-codegenie-ux-safety/mac_companion")!

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusBlock
                    oneStepPairBlock
                    explanationBlock
                    macSetupBlock
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            bridge.startBrowsing()
        }
        .onDisappear { bridge.stopBrowsing() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pair your Mac")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Connect over Wi-Fi. Keep your iPhone and Mac on the same network, then tap your Mac name when it appears.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBlock: some View {
        GlassCard(title: "Status", icon: "link", tint: tint) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Spacer()
                if isPairedOrConnected {
                    Button("Forget") { bridge.disconnect(forgetPairing: true) }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    private var oneStepPairBlock: some View {
        GlassCard(title: "Wi-Fi pairing", icon: "wifi", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 12) {
                if case .connected = bridge.status {
                    Label("This iPhone is paired. You can close this screen.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                    PrimaryButton(title: "Done", systemImage: "checkmark", style: .filled) {
                        dismiss()
                    }
                } else if creds.hasCompanionPairing && pairingMessage == nil {
                    Label("This iPhone already trusts \(creds.companionHost).", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                    Text("To use a different Mac, tap Forget in the Status card, then pick the new Mac here.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Done", systemImage: "checkmark", style: .filled) {
                        dismiss()
                    }
                } else if bridge.discovered.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        ProgressView().tint(LiquidGlass.primaryText)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Looking for your Mac on Wi-Fi...")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text("If your Mac is not listed, open the Mac companion on your Mac, keep both devices on the same Wi-Fi, then come back here.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Found \(bridge.discovered.count == 1 ? "your Mac" : "\(bridge.discovered.count) Macs"). Tap the Mac name you recognize.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.72))

                    ForEach(bridge.discovered) { entry in
                        Button {
                            Task { await pair(entry) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "macbook")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(LiquidGlass.accent)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Your Mac: \(macName(entry))")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText)
                                    Text("Pair \(macName(entry))")
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.62))
                                }
                                Spacer()
                                Image(systemName: "link.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(LiquidGlass.success)
                            }
                            .padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pair \(macName(entry))")
                    }
                }

                if let pairingMessage {
                    Label(pairingMessage, systemImage: messageIcon)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(messageTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var macSetupBlock: some View {
        GlassCard(title: "Mac not showing?", icon: "questionmark.circle.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                explainerRow(
                    icon: "1.circle.fill",
                    title: "Open the companion on your Mac",
                    body: "The companion is the small Mac helper that lets CodeGenie use Xcode and Safari."
                )
                explainerRow(
                    icon: "2.circle.fill",
                    title: "Stay on the same Wi-Fi",
                    body: "Keep the Mac and iPhone on the same network. Leave the companion open."
                )
                explainerRow(
                    icon: "3.circle.fill",
                    title: "Return to this screen",
                    body: "Your Mac appears above by name. Tap it once to pair."
                )
                Link(destination: setupEmailURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                        Text("Email setup link to my Mac")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                Link(destination: companionGitHubURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.app.fill")
                        Text("Open Mac setup page")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                }
            }
        }
    }

    private var explanationBlock: some View {
        GlassCard(title: "What happens", icon: "list.number", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 10) {
                explainerRow(
                    icon: "1.circle.fill",
                    title: "Same Wi-Fi",
                    body: "Your Mac announces its name on your Wi-Fi. You should see something like 'Your Mac: Mike's MacBook Pro'. Nothing is sent to the cloud."
                )
                explainerRow(
                    icon: "2.circle.fill",
                    title: "One tap approval",
                    body: "Tapping the Mac saves a private pairing token on this iPhone."
                )
                explainerRow(
                    icon: "3.circle.fill",
                    title: "Build from the phone",
                    body: "CodeGenie can ask that Mac to open Safari, run Xcode, and bring the finished app back."
                )
            }
        }
    }

    private func explainerRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(LiquidGlass.accent.opacity(0.18)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(body)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            }
        }
    }

    private func pair(_ entry: CompanionBridge.Discovered) async {
        pairingMessage = "Pairing \(macName(entry))..."
        let paired = await bridge.connect(discovered: entry)
        if paired {
            pairingMessage = "\(macName(entry)) is paired. CodeGenie can use this Mac for Xcode and Safari."
            Haptics.success()
        } else {
            pairingMessage = "Could not pair \(macName(entry)). Keep the companion open on your Mac and try again."
            Haptics.error()
        }
    }

    private func macName(_ entry: CompanionBridge.Discovered) -> String {
        entry.name
            .replacingOccurrences(of: "CodeGenie on ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var setupEmailURL: URL {
        let body = """
        Open this email on your Mac, then do this:

        1. Open the CodeGenie Mac setup page:
        \(companionGitHubURL.absoluteString)

        2. Open CodeGenie Companion on the Mac and leave it open.
        3. Return to CodeGenie on your iPhone.
        4. Your Mac name should appear on the Pair Mac screen.
        5. Tap your Mac name once to finish Wi-Fi pairing.
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CodeGenie Mac companion setup"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? companionGitHubURL
    }

    private var messageIcon: String {
        guard let pairingMessage else { return "info.circle.fill" }
        return pairingMessage.contains("is paired") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var messageTint: Color {
        guard let pairingMessage else { return LiquidGlass.accent }
        return pairingMessage.contains("is paired") ? LiquidGlass.success : LiquidGlass.warning
    }

    private var label: String {
        switch bridge.status {
        case .idle:           creds.hasCompanionPairing ? "Paired to \(creds.companionHost)" : "Not paired"
        case .browsing:       creds.hasCompanionPairing ? "Paired — checking network…" : "Searching the network…"
        case .connecting:     "Connecting…"
        case .authenticating: "Authenticating…"
        case .connected:      "Connected to your Mac"
        case .failed(let m):  "Failed: \(m)"
        }
    }

    private var tint: Color {
        switch bridge.status {
        case .connected:                       LiquidGlass.success
        case .connecting, .authenticating, .browsing: LiquidGlass.warning
        case .failed:                          .red
        case .idle:                            creds.hasCompanionPairing ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.4)
        }
    }

    private var isPairedOrConnected: Bool {
        if case .connected = bridge.status { return true }
        return creds.hasCompanionPairing
    }
}
