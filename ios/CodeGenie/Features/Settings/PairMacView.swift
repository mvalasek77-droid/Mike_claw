import SwiftUI

/// UI flow for pairing the iPhone with the user's Mac companion daemon.
///
/// Two paths in:
///  • **Bonjour list** — happy path on a shared Wi-Fi network.
///  • **Manual paste** — for advanced users tunneling over Tailscale,
///    or when Bonjour is blocked by a router.
///
/// Both end at the same place: a stored bearer token + a green
/// "connected" status pill.
struct PairMacView: View {
    @StateObject private var bridge = CompanionBridge()
    @State private var pasteURL: String = ""
    @State private var manualHost: String = ""
    @State private var manualPort: String = ""
    @State private var manualToken: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusBlock
                    discoveredBlock
                    manualBlock
                    helpBlock
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { bridge.startBrowsing() }
        .onDisappear { bridge.stopBrowsing() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pair your Mac")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Run the CodeGenie Companion on your Mac, then pair it once. The phone keeps reaching back into Xcode + Safari from there.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBlock: some View {
        GlassCard(title: "Status", icon: "link", tint: tint) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if case .connected = bridge.status {
                    Button("Disconnect") { bridge.disconnect() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    private var discoveredBlock: some View {
        GlassCard(title: "On your network", icon: "wifi", tint: LiquidGlass.accent) {
            if bridge.discovered.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Looking for `_codegenie-companion._tcp` …")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bridge.discovered) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "macbook")
                                .foregroundStyle(LiquidGlass.accent)
                            Text(entry.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("Tap to pair")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(10)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var manualBlock: some View {
        GlassCard(title: "Or pair manually", icon: "qrcode.viewfinder", tint: LiquidGlass.accentSecondary) {
            VStack(spacing: 10) {
                Text("Paste the pairing URL from the Mac terminal:")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                TextField("codegenie://pair?host=…&port=…&token=…", text: $pasteURL, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))

                PrimaryButton(title: "Connect", systemImage: "link", style: .filled) {
                    guard let url = URL(string: pasteURL) else { return }
                    Task { await bridge.connect(pairingURL: url) }
                }
                .disabled(pasteURL.isEmpty)
                .opacity(pasteURL.isEmpty ? 0.5 : 1)
            }
        }
    }

    private var helpBlock: some View {
        GlassCard(title: "Install the companion", icon: "terminal.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 6) {
                Text("On your Mac, run:")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("cd ~/code/codebaby/mac_companion\nswift run codegenie-companion")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                Text("It prints a `codegenie://pair?…` URL — paste that here, or scan the QR code shown by the menu bar app once we ship it.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var label: String {
        switch bridge.status {
        case .idle:           "Not paired"
        case .browsing:       "Searching the network…"
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
        case .idle:                            .white.opacity(0.4)
        }
    }
}
