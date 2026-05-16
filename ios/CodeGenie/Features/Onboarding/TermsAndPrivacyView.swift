import SwiftUI

/// Legal gate shown after onboarding, before the user reaches the main
/// app. They must scroll through the Terms summary + Privacy summary
/// and explicitly tap "Agree & continue" before `hasAcceptedTerms`
/// flips. Apple's review explicitly checks that paid / billable apps
/// surface this — and CodeGenie's hosted plan + Apple Developer fees
/// make us very much a paid app.
///
/// Wire pattern: `RootView` shows this whenever `hasFinishedOnboarding`
/// is true AND `hasAcceptedTerms` is false. Once accepted, we don't
/// re-show it on subsequent launches.
struct TermsAndPrivacyView: View {
    var onAccept: () -> Void

    @State private var scrolledToBottom: Bool = false
    @State private var agreed: Bool = false

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        termsCard
                        privacyCard
                        costsCard
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .onAppear { scrolledToBottom = true }
                        Color.clear.frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                }
                .scrollIndicators(.visible)

                acceptBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Before we start")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Three things to read. Plain-English summary first, full versions linked.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var termsCard: some View {
        GlassCard(title: "Terms of use", icon: "doc.text.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 8) {
                bullet("You own the apps you create with CodeGenie. We don't claim any rights to your code or your business.")
                bullet("CodeGenie is a tool, not a guarantee. We don't promise Apple will approve every build — App Review is Apple's call.")
                bullet("Don't use CodeGenie to build apps that violate Apple's App Store Review Guidelines (no harassment, no scraping, no malware, no copycats).")
                bullet("If you cancel a paid plan, you keep access until the period ends. No refunds for partial months.")
                bullet("CodeGenie is provided 'as is'. Bugs happen — back up your code with GitHub (we'll help you set that up).")
                Link(destination: URL(string: "https://codegenie.app/terms")!) {
                    Label("Read the full terms", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.accent)
                }
                .padding(.top, 4)
            }
        }
    }

    private var privacyCard: some View {
        GlassCard(title: "Privacy", icon: "lock.shield.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 8) {
                bullet("Your API keys, GitHub token, and Apple credentials are stored in the iOS Keychain. CodeGenie sends them only to the build runner or upload/sync endpoint when you explicitly start that action.")
                bullet("Your app descriptions go to the AI provider you chose (Anthropic, OpenAI) so they can generate code. They have their own privacy policies — we don't store the prompts.")
                bullet("Build logs and decisions are kept on the runner handling that build. You can delete archived workspaces anytime from Settings → Admin.")
                bullet("Telemetry (build success rate, average time) is on-device only — toggleable in Settings → Build telemetry.")
                bullet("We don't sell data. We don't track you across apps. There are no third-party analytics SDKs.")
                Link(destination: URL(string: "https://codegenie.app/privacy")!) {
                    Label("Read the full privacy policy", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.success)
                }
                .padding(.top, 4)
            }
        }
    }

    private var costsCard: some View {
        GlassCard(title: "Costs you should know about", icon: "dollarsign.circle.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 8) {
                bullet("**CodeGenie**: free for your first 3 hosted builds each month. Pro is $9.99/month for hosted Sonnet builds plus 20 Opus runs. Studio is $29/month for team-ready GitHub sync and TestFlight priority. Or bring your own Anthropic/OpenAI key and pay that provider directly.")
                bullet("**Apple Developer Program**: $99 USD per year. Required only if you want to ship your app to the App Store or TestFlight. Optional for previewing on your own iPhone.")
                bullet("**The App Store itself**: free to publish to. Apple takes a 15-30% cut only if you charge users for the app or sell in-app purchases.")
                bullet("**GitHub**: free. We'll walk you through signup if you don't already have an account.")
                bullet("You can set a hard spending cap in Settings → Build cost cap. We default it to $5 to protect you from runaway bills.")
            }
        }
    }

    private var acceptBar: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(spacing: 12) {
                Toggle(isOn: $agreed) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("I've read and agree")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(scrolledToBottom ? "Tap the switch, then continue." : "Scroll to the bottom to enable.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    }
                }
                .tint(LiquidGlass.success)
                .disabled(!scrolledToBottom)

                PrimaryButton(title: "Agree & continue", systemImage: "checkmark.circle.fill", style: .filled) {
                    Haptics.success()
                    onAccept()
                }
                .disabled(!agreed)
                .opacity(agreed ? 1 : 0.5)
            }
            .padding(16)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(LiquidGlass.primaryText.opacity(0.45))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(.init(text))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
