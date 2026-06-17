import SwiftUI
import StoreKit

/// The Pro upgrade screen. Leads with the annual and lifetime plans (the best
/// fit for an app used in bursts at each launch), with monthly as the anchor.
struct PaywallView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    /// The capability the user just reached for, for contextual copy.
    var highlight: ProFeature? = nil

    private let features: [(icon: String, text: String)] = [
        ("rectangle.on.rectangle.angled", "Export every iPhone & iPad size at once"),
        ("photo.stack", "Up to 10 screenshots per set"),
        ("globe", "Localized caption sets for every language"),
        ("character.bubble", "Text & sticker overlays"),
        ("photo.fill.on.rectangle.fill", "Photo backdrops, blur & custom gradients"),
        ("film", "App Preview video frames"),
        ("square.stack.3d.up.fill", "The full template gallery")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    featureList
                    plans
                    footer
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.4))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .interactiveDismissDisabled(store.isPurchasing)
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            StudioMark(size: 64)
            Text("Screenshot Studio Pro")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .auroraStyle()
            Text(highlight.map { "\($0.title) is a Pro feature. \($0.blurb)" }
                 ?? "Unlock every size, language and finishing touch for store-ready screenshots.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(features, id: \.text) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(width: 26)
                        Text(feature.text)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.9))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            GlassCard {
                VStack(spacing: 8) {
                    ProgressView().tint(LiquidGlass.accent)
                    Text("Loading plans…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        } else {
            VStack(spacing: 12) {
                planButton(store.product(ProductID.annual),
                           title: "Annual", subtitle: "7-day free trial, billed yearly",
                           badge: "Best value", featured: true)
                planButton(store.product(ProductID.lifetime),
                           title: "Lifetime", subtitle: "One-time purchase, yours forever",
                           badge: nil, featured: false)
                planButton(store.product(ProductID.monthly),
                           title: "Monthly", subtitle: "Billed monthly",
                           badge: nil, featured: false)
            }
        }
    }

    private func planButton(_ product: Product?, title: String, subtitle: String,
                            badge: String?, featured: Bool) -> some View {
        Button {
            guard let product else { return }
            Task { await store.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(LiquidGlass.auroraGradient, in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                Spacer(minLength: 0)
                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
            }
            .padding(16)
            .background(LiquidGlass.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(featured ? AnyShapeStyle(LiquidGlass.auroraGradient) : AnyShapeStyle(LiquidGlass.hairline),
                                  lineWidth: featured ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(product == nil || store.isPurchasing)
        .opacity(product == nil ? 0.5 : 1)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.restore() }
            } label: {
                Text("Restore purchases")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.accent)
            }
            .disabled(store.isPurchasing)

            Text("Plans renew automatically until cancelled. Cancel anytime in Settings. Lifetime is a one-time purchase.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
