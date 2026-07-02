import SwiftUI

/// First-run pricing chooser. Sits between TermsAndPrivacyView and
/// MainTabView in `RootView`. The user picks how they'll pay for
/// builds before they get into the app — pricing becomes a first-
/// class decision instead of a thing buried in Settings.
///
/// Two paths map to the two `Credentials.AuthMode` cases:
///   • **CodeGenie hosted** — 3 builds free / month, then Pro at
///     $9.99 unlocks more. No setup. Default for first-timers.
///   • **Bring your own key** — paste Anthropic or OpenAI API key.
///     CodeGenie takes no cut. Cheapest at scale.
///
/// The screen persists the choice via `Credentials.setAuthMode(...)`
/// and flips `@AppStorage("hasChosenPricing")` so RootView routes on.
struct PricingSetupView: View {
    var onChoose: () -> Void

    @StateObject private var creds = Credentials.shared
    @State private var pendingChoice: Credentials.AuthMode?

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    plans
                    laterEscape
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick how you'll pay")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text("Two paths. Neither requires a credit card right now — choose one, you can change it any time in Settings.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var plans: some View {
        VStack(spacing: 14) {
            planCard(
                mode: .codegenie,
                title: "CodeGenie Hosted",
                price: "Free for 3 builds / month",
                upsell: "Then $9.99 / mo Pro · unlimited Sonnet + 20 Opus",
                icon: "sparkles",
                tint: LiquidGlass.accent,
                bullets: [
                    "Zero setup — start your first build immediately.",
                    "We pay the AI provider; you pay us. No surprise API bills.",
                    "Includes the safety cap by default."
                ],
                ctaLabel: "Start with free hosted"
            )
            planCard(
                mode: .byok,
                title: "Bring your own key",
                price: "≈ $0.25–$1.80 per build · no CodeGenie cut",
                upsell: "Pay Anthropic or OpenAI directly.",
                icon: "key.fill",
                tint: LiquidGlass.success,
                bullets: [
                    "You paste an Anthropic or OpenAI API key once.",
                    "Key stays in the iOS Keychain — never sent to us.",
                    "Cheapest at scale; needs ~10 sec of setup."
                ],
                ctaLabel: "Use my own API key"
            )
        }
    }

    private var laterEscape: some View {
        Button {
            guard pendingChoice == nil else { return }
            Haptics.selection()
            // Pick the safest default (free hosted) silently. The
            // user can revisit Settings any time; no decision is
            // permanent.
            creds.setAuthMode(.codegenie)
            onChoose()
        } label: {
            Text("Decide later — start with free hosted")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Defaults to the free hosted plan and takes you to the app. You can change this in Settings.")
    }

    // MARK: Plan card

    private func planCard(
        mode: Credentials.AuthMode,
        title: String,
        price: String,
        upsell: String,
        icon: String,
        tint: Color,
        bullets: [String],
        ctaLabel: String
    ) -> some View {
        let selecting = pendingChoice == mode
        return GlassSurface(tier: .raised, corner: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text(price)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                    Spacer()
                }
                Text(upsell)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bullets, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.top, 4)
                            Text(line)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                PrimaryButton(
                    title: selecting ? "Selecting…" : ctaLabel,
                    systemImage: selecting ? "ellipsis" : "checkmark.circle.fill",
                    style: .filled
                ) {
                    choose(mode)
                }
                .disabled(selecting)
                .accessibilityHint("Picks the \(title) plan. You can change this any time in Settings.")
            }
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(price). \(upsell)")
    }

    private func choose(_ mode: Credentials.AuthMode) {
        // First tap wins — a second card tapped during the 250 ms
        // selection beat must not overwrite the choice or re-fire
        // the routing callback.
        guard pendingChoice == nil else { return }
        pendingChoice = mode
        Haptics.success()
        creds.setAuthMode(mode)
        // Brief delay so the user sees the selection state before
        // we route on — feels like the app responded, not skipped.
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                onChoose()
            }
        }
    }
}
