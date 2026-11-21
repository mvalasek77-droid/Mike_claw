import SwiftUI
import UIKit

/// Plain-English explainer for Xcode: what it is and how to get it.
///
/// First-timers don't know what Xcode is, why they need a Mac, or what
/// "command line tools" means. This screen says it once, plainly, and
/// says plainly that the user will open it themselves, guided.
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
            Text("The free Apple program that turns CodeGenie's output into a real iPhone app.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        GlassCard(
            title: "You'll use it yourself, briefly",
            icon: "hand.point.up.left.fill",
            tint: LiquidGlass.accent
        ) {
            Text("When your app is built, CodeGenie sends the project to your Mac and its guide tells you exactly what to click in Xcode: open it, sign in, press Run, press Archive. About six buttons in total. You never write or read code there.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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
                    body: "Apple won't let any other operating system build iOS apps, so this one part happens on a Mac. You'll open Xcode yourself and press a few buttons — CodeGenie's guide tells you exactly which ones."
                )
                explainerRow(
                    icon: "gift.fill",
                    title: "Free",
                    body: "Xcode is free from the Mac App Store. No subscription, no trial, no account beyond the Apple ID you already use."
                )
            }
        }
    }

    /// The App Store page for Xcode. Tapped on a Mac it opens the Mac
    /// App Store; it does nothing useful on the phone, which is the whole
    /// reason this card sends it to the Mac rather than opening it here.
    private let xcodeURL = URL(string: "https://apps.apple.com/app/xcode/id497799835")!

    private var installCard: some View {
        GlassCard(title: "Don't have Xcode yet?", icon: "arrow.down.circle.fill", tint: LiquidGlass.accentSecondary) {
            VStack(alignment: .leading, spacing: 12) {
                // Be honest: this can't be done from the phone. Xcode
                // installs onto the Mac, from the Mac.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "macbook")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                        .accessibilityHidden(true)
                    Text("This part is done on your Mac, not here. You can't install Xcode from an iPhone.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    walkRow(num: 1, body: "On your Mac, open the **App Store** app — the blue icon with a white **A** in the Dock, or press **⌘-Space** and type \"App Store\".")
                    walkRow(num: 2, body: "In the search box, top-left, type **Xcode** and press Return.")
                    walkRow(num: 3, body: "On the Xcode result, click **Get**, then **Install**. It's free; your Apple ID password may be asked for.")
                    walkRow(num: 4, body: "It's a 7–15 GB download, so give it around 30 minutes. You can keep using your phone while it finishes.")
                }

                Divider().background(.white.opacity(0.1))

                Text("To save typing, send yourself the link and open it on the Mac — it jumps straight to Xcode in the Mac App Store:")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(item: xcodeURL) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Send the Xcode link to my Mac")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(LiquidGlass.auroraGradient, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(LiquidGlass.primaryText)
                }
                .accessibilityHint("Opens the share sheet. Choose AirDrop or Messages to send the link to your Mac, then open it there.")

                Button {
                    UIPasteboard.general.string = xcodeURL.absoluteString
                    Haptics.success()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy the link")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(LiquidGlass.accent)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copies the Mac App Store link so you can paste it on your Mac")

                Text("Or, on your Mac, just open **developer.apple.com/xcode** in any browser.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signinCard: some View {
        GlassCard(title: "After it's installed", icon: "list.number", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 10) {
                walkRow(num: 1, body: "On the Mac, open Xcode once. Click **Agree** on the license — Apple won't let it build until you do. If it offers to install extra components, let it.")
                walkRow(num: 2, body: "Xcode → Settings → Accounts → tap **+** → sign in with the Apple ID enrolled in the Apple Developer Program.")
                walkRow(num: 3, body: "That's the setup done. When your app is built, CodeGenie's guide walks you through opening the project and the few buttons to press.")
                Text("Doing the license and sign-in now means the guide later just works, instead of stopping on a cryptic error.")
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
