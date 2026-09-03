import SwiftUI

/// Pairing the iPhone with the Mac companion.
///
/// **Design note.** This screen used to show seven stacked cards at
/// once — status, prerequisites, a QR button, a Bonjour list, a manual
/// paste form, and terminal commands — with no indication of what to
/// do first. A first-time user cannot tell which of those is the path
/// and which are the escape hatches.
///
/// Now it is three numbered steps with one action each, and the escape
/// hatches live behind a single "It's not working" toggle. Once
/// connected the whole screen collapses to one confirmation.
struct PairMacView: View {
    @StateObject private var bridge = CompanionBridge.shared
    @State private var pasteURL: String = ""
    @State private var showScanner: Bool = false
    @State private var showTroubleshooting: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var isConnected: Bool {
        if case .connected = bridge.status { return true }
        return false
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if isConnected {
                        connectedCard
                    } else {
                        whyCard
                        stepOne
                        stepTwo
                        stepThree
                        troubleshootingToggle
                        if showTroubleshooting { troubleshootingCard }
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { bridge.startBrowsing() }
        .onDisappear { bridge.stopBrowsing() }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onScan: { payload in
                    showScanner = false
                    if let url = URL(string: payload), payload.hasPrefix("codegenie://") {
                        Task { await bridge.connect(pairingURL: url) }
                    } else {
                        // Not one of ours — surface what was actually
                        // scanned in the manual field rather than
                        // failing silently.
                        pasteURL = payload
                        showTroubleshooting = true
                    }
                },
                onCancel: { showScanner = false }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect a Mac")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text(isConnected
                 ? "Your phone and your Mac are talking to each other."
                 : "Three steps, about five minutes. You only do this once.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Connected state

    private var connectedCard: some View {
        VStack(spacing: 14) {
            GlassSurface(tier: .deep, corner: 22) {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                        .accessibilityHidden(true)
                    Text("Mac connected")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("CodeGenie can now build your apps and open App Store Connect on your Mac for you. Nothing else to do here.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            PrimaryButton(title: "Done", systemImage: "checkmark", style: .filled) {
                Haptics.success()
                dismiss()
            }
            Button("Disconnect this Mac") {
                Haptics.warning()
                bridge.disconnect()
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mac connected")
    }

    // MARK: Why — sets expectations before any work

    private var whyCard: some View {
        GlassSurface(tier: .raised, corner: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why a Mac?")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("Apple only lets iPhone apps be built on a Mac. CodeGenie runs that part for you in the background — you never open Xcode yourself.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can skip this for now and still design and build. You need it to put an app on a real iPhone.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The three steps

    private var stepOne: some View {
        stepCard(
            number: 1,
            title: "Install CodeGenie Companion",
            body: "A small free app for your Mac. Open this link on the Mac itself, not on your phone."
        ) {
            Link(destination: URL(string: "https://codegenie.app/companion")!) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Get the Mac app")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Get the Mac app")
            .accessibilityHint("Opens the download page. Do this on your Mac.")
        }
    }

    private var stepTwo: some View {
        stepCard(
            number: 2,
            title: "Open it on your Mac",
            body: "It appears in the menu bar along the top of the screen and shows a QR code. Leave that on screen for the next step."
        ) {
            EmptyView()
        }
    }

    private var stepThree: some View {
        stepCard(
            number: 3,
            title: "Scan the QR code",
            body: statusLine
        ) {
            PrimaryButton(title: "Scan the code", systemImage: "qrcode.viewfinder", style: .filled) {
                Haptics.selection()
                showScanner = true
            }
            .accessibilityHint("Opens the camera to scan the code shown on your Mac")
        }
    }

    /// Step 3's body doubles as the live status readout, so progress
    /// and failures appear where the user is already looking instead
    /// of in a separate status card higher up the screen.
    private var statusLine: String {
        switch bridge.status {
        case .idle, .browsing:
            return "Point your phone's camera at the code in the Mac's menu bar."
        case .connecting:
            return "Connecting to your Mac…"
        case .authenticating:
            return "Almost there — checking the code…"
        case .connected:
            return "Connected."
        case .failed(let message):
            return "That didn't work: \(message). Open \"It's not working\" below."
        }
    }

    private func stepCard<Action: View>(
        number: Int,
        title: String,
        body: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        GlassSurface(tier: .raised, corner: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(number)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LiquidGlass.accent))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(body)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                action()
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number). \(title). \(body)")
    }

    // MARK: Escape hatches, hidden until asked for

    private var troubleshootingToggle: some View {
        Button {
            Haptics.selection()
            Motion.run(.spring(response: 0.35)) { showTroubleshooting.toggle() }
        } label: {
            Label(
                showTroubleshooting ? "Hide help" : "It's not working",
                systemImage: showTroubleshooting ? "chevron.up" : "chevron.down"
            )
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
        }
        .accessibilityHint("Shows other ways to connect if scanning failed")
    }

    private var troubleshootingCard: some View {
        VStack(spacing: 14) {
            GlassCard(title: "Check these first", icon: "checklist", tint: LiquidGlass.warning) {
                VStack(alignment: .leading, spacing: 8) {
                    checkRow("Your Mac and your phone are on the same Wi-Fi network.")
                    checkRow("The Companion app is actually running — look for its icon in the Mac's menu bar.")
                    checkRow("Xcode is installed on the Mac. It's free from the Mac App Store.")
                }
            }

            if !bridge.discovered.isEmpty {
                GlassCard(title: "Macs we can see", icon: "wifi", tint: LiquidGlass.accent) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("These are on your network. Scanning the code is still the reliable way in.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        ForEach(bridge.discovered) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: "macbook")
                                    .foregroundStyle(LiquidGlass.accent)
                                    .accessibilityHidden(true)
                                Text(entry.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(LiquidGlass.primaryText)
                                Spacer()
                            }
                            .padding(10)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            GlassCard(title: "Type the code instead", icon: "keyboard", tint: LiquidGlass.accentSecondary) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The Companion app shows a link under the QR code. Type or paste it here.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    TextField("codegenie://pair?…", text: $pasteURL, axis: .vertical)
                        .lineLimit(2...3)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)))
                        .accessibilityLabel("Pairing link")

                    PrimaryButton(title: "Connect", systemImage: "link", style: .filled) {
                        let clean = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = URL(string: clean) else {
                            Haptics.error()
                            return
                        }
                        Task { await bridge.connect(pairingURL: url) }
                    }
                    .disabled(pasteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(pasteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
        }
    }

    private func checkRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
