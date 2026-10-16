import SwiftUI
import StoreKit

/// Full-screen paywall showing CodeGenie's subscription tiers.
///
/// Matches the Liquid Glass visual language used across the Settings
/// screens (see `AppleDevSetupView` for a sibling). Each tier is
/// presented in a `GlassCard` with purchase buttons that route through
/// `SubscriptionService`.
struct PaywallView: View {
    @StateObject private var store = SubscriptionService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    usageCard
                    tierCards
                    restoreButton
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)

            if store.isLoading {
                loadingOverlay
            }
        }
        .task { await store.loadProducts() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose Your Plan")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Unlock more builds and ship faster with a Pro or Studio subscription.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Usage card

    private var usageCard: some View {
        GlassCard(
            title: "This month",
            icon: "hammer.fill",
            tint: usageTint
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(usageLabel)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                    Spacer()
                    Text(store.currentTier.displayName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(tierBadgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tierBadgeColor.opacity(0.18), in: Capsule())
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.10))
                            .frame(height: 8)
                        Capsule()
                            .fill(usageGradient)
                            .frame(width: geo.size.width * progressFraction, height: 8)
                    }
                }
                .frame(height: 8)
                .accessibilityValue("\(store.buildsThisMonth) of \(store.currentTier.monthlyBuilds) builds used")
            }
        }
    }

    private var usageLabel: String {
        if store.currentTier == .studio {
            return "\(store.buildsThisMonth) builds used — unlimited"
        }
        return "\(store.buildsThisMonth) of \(store.currentTier.monthlyBuilds) builds used"
    }

    private var progressFraction: CGFloat {
        guard store.currentTier.monthlyBuilds > 0 else { return 0 }
        return min(CGFloat(store.buildsThisMonth) / CGFloat(store.currentTier.monthlyBuilds), 1.0)
    }

    private var usageTint: Color {
        if progressFraction >= 1.0 { return LiquidGlass.error }
        if progressFraction >= 0.8 { return LiquidGlass.warning }
        return LiquidGlass.accent
    }

    private var usageGradient: LinearGradient {
        LinearGradient(
            colors: [usageTint, usageTint.opacity(0.7)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var tierBadgeColor: Color {
        switch store.currentTier {
        case .free:   return LiquidGlass.primaryText.opacity(0.7)
        case .pro:    return LiquidGlass.accent
        case .studio: return LiquidGlass.accentSecondary
        }
    }

    // MARK: - Tier cards

    private var tierCards: some View {
        VStack(spacing: 14) {
            ForEach(SubscriptionService.Tier.allCases, id: \.rawValue) { tier in
                tierCard(for: tier)
            }
        }
    }

    @ViewBuilder
    private func tierCard(for tier: SubscriptionService.Tier) -> some View {
        let isCurrent = store.currentTier == tier

        GlassCard(
            title: tier.displayName,
            icon: tierIcon(for: tier),
            tint: tierTint(for: tier)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Price + builds
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(displayPrice(for: tier))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    if tier != .free {
                        Text("/ month")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }
                }

                Text(buildsDescription(for: tier))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))

                // Features
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(features(for: tier), id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(tierTint(for: tier))
                            Text(feature)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        }
                    }
                }

                // Action
                if isCurrent {
                    currentTierBadge
                } else if tier == .free {
                    // No purchase button for free — it's the default.
                    EmptyView()
                } else {
                    purchaseButton(for: tier)
                }

                // Error
                if let error = store.purchaseError, isCurrent == false {
                    Text(error)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var currentTierBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
            Text("Current plan")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(LiquidGlass.success)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func purchaseButton(for tier: SubscriptionService.Tier) -> some View {
        if let product = store.products.first(where: { $0.id == tier.rawValue }) {
            PrimaryButton(
                title: "Subscribe — \(product.displayPrice)",
                systemImage: "cart.fill",
                style: tier == .studio ? .filled : .glass
            ) {
                Task { await store.purchase(product) }
            }
            .disabled(store.isLoading)
            .opacity(store.isLoading ? 0.5 : 1)
        } else {
            // Products haven't loaded yet — show a placeholder.
            PrimaryButton(
                title: "Subscribe — \(tier.price)/mo",
                systemImage: "cart.fill",
                style: .ghost
            ) { /* no-op until products load */ }
            .disabled(true)
            .opacity(0.4)
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task { await store.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .disabled(store.isLoading)
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
            .allowsHitTesting(true)
    }

    // MARK: - Data helpers

    private func tierIcon(for tier: SubscriptionService.Tier) -> String {
        switch tier {
        case .free:   return "gift.fill"
        case .pro:    return "bolt.fill"
        case .studio: return "star.fill"
        }
    }

    private func tierTint(for tier: SubscriptionService.Tier) -> Color {
        switch tier {
        case .free:   return LiquidGlass.primaryText.opacity(0.7)
        case .pro:    return LiquidGlass.accent
        case .studio: return LiquidGlass.accentSecondary
        }
    }

    private func displayPrice(for tier: SubscriptionService.Tier) -> String {
        if let product = store.products.first(where: { $0.id == tier.rawValue }) {
            return product.displayPrice
        }
        return tier.price
    }

    private func buildsDescription(for tier: SubscriptionService.Tier) -> String {
        switch tier {
        case .free:   return "3 builds per month"
        case .pro:    return "30 builds per month"
        case .studio: return "Unlimited builds"
        }
    }

    private func features(for tier: SubscriptionService.Tier) -> [String] {
        switch tier {
        case .free:
            return [
                "AI-powered code generation",
                "3 builds per month",
            ]
        case .pro:
            return [
                "Everything in Free",
                "30 builds per month",
                "Priority build queue",
            ]
        case .studio:
            return [
                "Everything in Pro",
                "Unlimited builds",
                "Priority support",
                "Early access to new features",
            ]
        }
    }
}
