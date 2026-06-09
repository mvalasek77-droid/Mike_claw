import SwiftUI

/// UI flow for pairing the iPhone with the user's Mac terminal runner.
///
/// Two connection paths:
///  1. **Wi-Fi auto-discovery** (primary) — tap a discovered Mac, confirm,
///     and you're in. Same Wi-Fi required.
///  2. **Manual URL paste** (fallback) — copy the pairing URL from Mac Terminal
///     and paste it here.
///
/// Both paths require user confirmation before connecting (security gate).
struct PairMacView: View {
    @StateObject private var bridge = CompanionBridge()
    @State private var pasteURL: String = ""
    @State private var copiedCommand: Bool = false
    @State private var emailedCommand: Bool = false
    @State private var showConfirmConnect: Bool = false
    @State private var pendingMac: CompanionBridge.Discovered?
    @State private var showManual: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusBlock
                    stepByStepGuide
                    discoveredBlock
                    manualToggle
                    if showManual { manualBlock }
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { bridge.startBrowsing() }
        .onDisappear { bridge.stopBrowsing() }
        .alert("Connect to \(pendingMac?.name ?? "Mac")?", isPresented: $showConfirmConnect) {
            Button("Connect") {
                guard let mac = pendingMac else { return }
                Task {
                    await bridge.connect(host: mac.host, port: mac.port > 0 ? mac.port : 9000, token: "")
                }
            }
            Button("Cancel", role: .cancel) {
                pendingMac = nil
            }
        } message: {
            Text("This will allow CodeGenie on this iPhone to send commands to \(pendingMac?.name ?? "that Mac"). Only connect to Macs you trust.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pair your Mac")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Run one command on your Mac, then connect over Wi-Fi. Your Mac and iPhone must be on the same network.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Connection status

    private var statusBlock: some View {
        GlassCard(title: "Connection", icon: "link", tint: tint) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Spacer()
                if case .connected = bridge.status {
                    Button("Disconnect") { bridge.disconnect() }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    // MARK: - Step-by-step setup guide

    /// Clear 4-step walkthrough:
    /// 1. Copy command (tappable box)
    /// 2. Email it to your Mac
    /// 3. Open Terminal on Mac (with illustration)
    /// 4. Paste and run — then tap your Mac below
    private var stepByStepGuide: some View {
        GlassCard(title: "Setup", icon: "list.number", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 16) {

                // Step 1: Copy command
                stepRow(number: 1,
                    icon: "doc.on.doc",
                    iconColor: LiquidGlass.accent,
                    title: "Copy the command",
                    body: "Tap the box below to copy it to your clipboard."
                )
                terminalCommandBox

                divider

                // Step 2: Send to Mac
                stepRow(number: 2,
                    icon: "envelope.fill",
                    iconColor: LiquidGlass.accent,
                    title: "Send it to your Mac",
                    body: "Email or AirDrop the command to yourself."
                )
                emailButton

                divider

                // Step 3: Open Terminal on Mac
                stepRow(number: 3,
                    icon: "terminal.fill",
                    iconColor: LiquidGlass.accent,
                    title: "Open Terminal on your Mac",
                    body: "Press ⌘ Space, type \"Terminal\", press Enter."
                )
                macTerminalIllustration

                divider

                // Step 4: Paste and run
                stepRow(number: 4,
                    icon: "play.fill",
                    iconColor: LiquidGlass.success,
                    title: "Paste and press Enter",
                    body: "⌘V to paste, then Enter. Once Terminal says \"Listening…\", tap your Mac in the list below."
                )
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
    }

    // MARK: - Step row

    private func stepRow(number: Int, icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                Circle()
                    .strokeBorder(iconColor.opacity(0.35), lineWidth: 0.5)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Terminal command (tappable copy)

    private var terminalCommandBox: some View {
        Button {
            UIPasteboard.general.string = "cd ~/code/Mike_claw && swift run codegenie-terminal-runner"
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.3)) { copiedCommand = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeOut(duration: 0.3)) { copiedCommand = false }
            }
        } label: {
            HStack(spacing: 8) {
                Text("cd ~/code/Mike_claw && swift run codegenie-terminal-runner")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copiedCommand ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(copiedCommand ? LiquidGlass.success : LiquidGlass.primaryText.opacity(0.5))
            }
            .padding(10)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy terminal command")
        .accessibilityHint("Tap to copy the command to clipboard")
    }

    // MARK: - Email button

    private var emailButton: some View {
        Button {
            let command = "cd ~/code/Mike_claw && swift run codegenie-terminal-runner"
            let subject = "CodeGenie — Terminal Command"
            let body = "Open Terminal on your Mac (⌘ Space → type \"Terminal\" → Enter) and paste this command:\n\n\(command)\n\nOnce Terminal says \"Listening…\" open CodeGenie on your iPhone and tap your Mac in the Wi-Fi list."
            let encoded = "mailto:?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            if let url = URL(string: encoded) {
                UIApplication.shared.open(url)
            }
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.3)) { emailedCommand = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeOut(duration: 0.3)) { emailedCommand = false }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: emailedCommand ? "checkmark.circle.fill" : "envelope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(emailedCommand ? LiquidGlass.success : LiquidGlass.accent)
                Text(emailedCommand ? "Opened Mail" : "✉️ Email to yourself")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(LiquidGlass.accent.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(LiquidGlass.accent.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mac Terminal illustration

    private var macTerminalIllustration: some View {
        HStack(spacing: 12) {
            // Mini Terminal window
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 100, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )
                // Traffic light dots
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Circle().fill(.yellow).frame(width: 6, height: 6)
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .frame(width: 100, height: 72, alignment: .topLeading)

                // Fake prompt
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Text("~")
                            .foregroundStyle(LiquidGlass.accent)
                        Text("$")
                            .foregroundStyle(.white)
                    }
                    Text("_")
                        .foregroundStyle(.white.opacity(0.6))
                        .font(.system(size: 8))
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .offset(y: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "macbook")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Terminal.app")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(LiquidGlass.primaryText)
                Text("⌘ Space → \"Terminal\" → Enter")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Wi-Fi discovery (primary path)

    private var discoveredBlock: some View {
        GlassCard(title: "Wi-Fi", icon: "wifi", tint: LiquidGlass.accent) {
            if bridge.discovered.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().tint(LiquidGlass.primaryText)
                    Text("Looking for Macs on your Wi-Fi…")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap a Mac to connect. You'll be asked to confirm before anything is sent.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(bridge.discovered) { entry in
                        Button {
                            Haptics.selection()
                            pendingMac = entry
                            showConfirmConnect = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "macbook")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(LiquidGlass.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText)
                                    Text("Tap to connect")
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.3))
                            }
                            .padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LiquidGlass.accent.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Manual paste (collapsible fallback)

    private var manualToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showManual.toggle()
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showManual ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LiquidGlass.accent)
                Text("Manual pairing (advanced)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private var manualBlock: some View {
        GlassCard(title: "Paste pairing URL", icon: "link", tint: LiquidGlass.accentSecondary) {
            VStack(spacing: 10) {
                Text("If Wi-Fi discovery doesn't work, copy the codegenie://… URL that Terminal prints and paste it here:")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                TextField("codegenie://pair?host=…&port=…&token=…", text: $pasteURL, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiquidGlass.primaryText)
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
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Helpers

    private var label: String {
        switch bridge.status {
        case .idle:           "Not paired"
        case .browsing:       "Searching Wi-Fi…"
        case .connecting:     "Connecting…"
        case .authenticating: "Authenticating…"
        case .connected:      "Connected ✓"
        case .failed(let m):  "Failed: \(m)"
        }
    }

    private var tint: Color {
        switch bridge.status {
        case .connected:                            LiquidGlass.success
        case .connecting, .authenticating, .browsing: LiquidGlass.warning
        case .failed:                               .red
        case .idle:                                 LiquidGlass.primaryText.opacity(0.4)
        }
    }
}