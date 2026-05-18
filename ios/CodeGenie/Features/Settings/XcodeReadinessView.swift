import SwiftUI

/// Plain-English explainer + status check for Xcode on the paired Mac.
///
/// First-timers don't know what Xcode is, why they need a Mac, or what
/// "command line tools" means. This screen says it once, plainly, and
/// shows a live status pulled from the Mac companion if one is paired.
struct XcodeReadinessView: View {
    @StateObject private var creds = Credentials.shared
    @StateObject private var bridge = CompanionBridge()
    @Environment(\.dismiss) private var dismiss
    @State private var showPairMac: Bool = false
    @State private var openingMacStore: Bool = false
    @State private var macStoreMessage: String?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    statusCard
                    explainerCard
                    installCard
                    signinCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showPairMac) {
            PairMacView()
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Xcode")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("The free Apple program that turns CodeGenie's output into a real iPhone app.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        let paired = creds.hasCompanionPairing
        return GlassCard(
            title: paired ? "Mac paired — Xcode reachable" : "Pair a Mac first",
            icon: paired ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
            tint: paired ? LiquidGlass.success : LiquidGlass.warning
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(paired
                     ? "When you start a build, CodeGenie sends the source to your Mac, runs Xcode there, and streams the result back to your phone."
                     : "CodeGenie needs to talk to a Mac running Xcode. Open Settings → Pair your Mac to get connected first.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
            }
        }
    }

    private var explainerCard: some View {
        GlassCard(title: "What is Xcode?", icon: "questionmark.circle.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 10) {
                explainerRow(
                    icon: "hammer.fill",
                    title: "Apple's build tool",
                    body: "Xcode reads your app's source code and produces the `.ipa` file the App Store accepts. Every iPhone app on the App Store was built by Xcode at some point."
                )
                explainerRow(
                    icon: "macbook",
                    title: "Why the Mac is involved",
                    body: "Apple requires iPhone apps to be built with Xcode on a Mac. CodeGenie streamlines that process by sending the build to your paired Mac and bringing the result back to your phone."
                )
                explainerRow(
                    icon: "gift.fill",
                    title: "Free",
                    body: "Xcode is free from the Mac App Store. No subscription, no trial, no account beyond the Apple ID you already use."
                )
            }
        }
    }

    private var installCard: some View {
        GlassCard(title: "Don't have Xcode yet?", icon: "arrow.down.circle.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 10) {
                Text("It's a 7-15 GB download. Plan for 30 minutes the first time.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                Button {
                    Task { await openXcodeOnMac() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                        Text(openingMacStore ? "Opening on Mac..." : "Download on Mac")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(LiquidGlass.primaryText)
                }
                .buttonStyle(.plain)
                .disabled(openingMacStore)
                .accessibilityHint("Opens the Xcode page in the Mac App Store on your paired Mac")

                if let macStoreMessage {
                    Text(macStoreMessage)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Link(destination: URL(string: "https://apps.apple.com/app/xcode/id497799835")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("Open web page here")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(LiquidGlass.accent)
                }
            }
        }
    }

    private var signinCard: some View {
        GlassCard(title: "After installing", icon: "list.number", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                walkRow(num: 1, body: "Open Xcode once. Click Agree on the license — Apple won't let it build until you do.")
                walkRow(num: 2, body: "Xcode → Settings → Accounts → tap **+** → sign in with the same Apple ID you use on your iPhone.")
                walkRow(num: 3, body: "After setup, CodeGenie can run Xcode for you from the phone.")
                Text("Skipping any of these steps causes a cryptic build error later. Doing them once saves the headache.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .padding(.top, 6)
            }
        }
    }

    // MARK: Helpers

    private func openXcodeOnMac() async {
        guard creds.hasCompanionPairing else {
            macStoreMessage = "Pair your Mac first, then CodeGenie can open Xcode there."
            showPairMac = true
            Haptics.warning()
            return
        }
        openingMacStore = true
        macStoreMessage = nil
        defer { openingMacStore = false }
        do {
            if !isBridgeConnected {
                guard await bridge.connectStoredPairing() else {
                    macStoreMessage = "Could not reach the Mac companion. Start it on your Mac, then try again."
                    Haptics.error()
                    return
                }
            }
            try await bridge.openURLOnMac("macappstores://apps.apple.com/app/xcode/id497799835")
            macStoreMessage = "Opened the Xcode download on your Mac."
            Haptics.success()
        } catch {
            macStoreMessage = "Could not open Xcode on the Mac: \(error)"
            Haptics.error()
        }
    }

    private var isBridgeConnected: Bool {
        if case .connected = bridge.status { return true }
        return false
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
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(body)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
            }
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
}
