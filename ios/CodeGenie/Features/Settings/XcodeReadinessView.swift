import SwiftUI

/// Plain-English explainer + status check for Xcode on the paired Mac.
///
/// First-timers don't know what Xcode is, why they need a Mac, or what
/// "command line tools" means. This screen says it once, plainly, and
/// shows a live status pulled from the Mac companion if one is paired.
struct XcodeReadinessView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Xcode")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("The free Apple program that turns CodeGenie's output into a real iPhone app.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        // We treat "backend token in keychain" as the proxy for "Mac
        // companion is paired". Live reachability is checked at the
        // moment of build by SwarmClient; this screen is a primer, not
        // a probe.
        let paired = !creds.backendToken.isEmpty
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
                    title: "Mac-only — that's an Apple rule",
                    body: "Apple won't let any other operating system build iOS apps. CodeGenie hides this by running Xcode on your Mac in the background; you never have to open it."
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
                Link(destination: URL(string: "macappstores://apps.apple.com/app/xcode/id497799835")!) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                            .accessibilityHidden(true)
                        Text("Open in Mac App Store")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(LiquidGlass.primaryText)
                }
                .accessibilityLabel("Open Xcode in Mac App Store")
                .accessibilityHint("Opens the Mac App Store on your paired Mac")

                Link(destination: URL(string: "https://apps.apple.com/app/xcode/id497799835")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .accessibilityHidden(true)
                        Text("Or open in Safari")
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
                walkRow(num: 3, body: "Quit Xcode. CodeGenie takes it from there — you never have to open it again.")
                Text("Skipping any of these steps causes a cryptic build error later. Doing them once saves the headache.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .padding(.top, 6)
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
