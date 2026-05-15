import SwiftUI

/// One-screen primer shown the first time a user is about to send a
/// build off their phone. The whole point: someone who has never
/// shipped to the App Store should leave this screen knowing the
/// difference between TestFlight (private beta) and the App Store
/// (everyone). Two clear CTAs at the bottom map the choice onto the
/// real decision they're about to make.
///
/// Wire pattern: present this as a sheet from the build screen the
/// first time the user taps Submit. Pass `onChoose` so the parent can
/// fork to the upload flow.
struct ReleaseStageExplainer: View {
    enum Choice { case testflight, appStore, learnMore }

    var onChoose: (Choice) -> Void
    var onCancel: () -> Void

    @State private var dontShowAgain: Bool = false

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    sideBySide
                    recommendation
                    actionButtons
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
            Text("Where should this go?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Apple gives you two doors. Same build — different audience.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sideBySide: some View {
        VStack(spacing: 14) {
            stageCard(
                tint: LiquidGlass.accent,
                badge: "Door 1",
                icon: "paperplane.fill",
                title: "TestFlight",
                tagline: "Your private beta.",
                bullets: [
                    "Up to 100 friends or testers, by email invite.",
                    "Apple reviews lightly — usually approved in under 24 hours.",
                    "You can update the build anytime, no resubmission.",
                    "Nobody else on the App Store can find it."
                ]
            )
            stageCard(
                tint: LiquidGlass.success,
                badge: "Door 2",
                icon: "globe",
                title: "App Store",
                tagline: "The whole world can find it.",
                bullets: [
                    "Anyone can search and download it.",
                    "Apple's full App Review — typically 1–3 days, sometimes longer.",
                    "Needs screenshots, description, age rating, privacy answers, pricing.",
                    "Once live, you can offer paid downloads or in-app purchases."
                ]
            )
        }
    }

    private var recommendation: some View {
        GlassCard(title: "We recommend TestFlight first", icon: "lightbulb.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Almost every successful App Store launch starts with a TestFlight round. You catch real-device bugs CodeGenie's simulator can miss, get feedback from a few real users, then ship to the App Store with confidence.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Text("You can always promote a TestFlight build to the App Store later — same build, no rebuild needed.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.success)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Send to TestFlight", systemImage: "paperplane.fill", style: .filled) {
                Haptics.success()
                onChoose(.testflight)
            }
            PrimaryButton(title: "Submit to the App Store", systemImage: "globe", style: .glass) {
                Haptics.selection()
                onChoose(.appStore)
            }
            HStack {
                Button("Tell me more about App Review") {
                    Haptics.selection()
                    onChoose(.learnMore)
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
                Spacer()
                Button("Not yet — go back") {
                    Haptics.selection()
                    onCancel()
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }
            .padding(.top, 4)
        }
    }

    private func stageCard(tint: Color, badge: String, icon: String, title: String, tagline: String, bullets: [String]) -> some View {
        GlassSurface(tier: .raised, corner: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(tagline)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    }
                    Spacer()
                }
                Divider().background(.white.opacity(0.08))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(tint.opacity(0.85))
                                .padding(.top, 3)
                            Text(line)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(tagline)")
    }
}
