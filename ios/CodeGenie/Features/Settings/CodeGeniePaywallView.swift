import SwiftUI
import StoreKit

/// The CodeGenie Pro upsell. Shown when a free user taps a Pro-gated
/// feature, or from Settings → pricing card. App Review requires a
/// paywall to state what's billed, show the price, and offer Restore +
/// links to Terms and Privacy — all present below.
struct CodeGeniePaywallView: View {
    @StateObject private var pro = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = ProStore.ProductID.yearly

    private struct Benefit: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let benefits: [Benefit] = [
        .init(icon: "bolt.fill", title: "Maximum Speed",
              detail: "Reviewer + Security run in parallel with testing instead of waiting their turn. Builds finish meaningfully sooner."),
        .init(icon: "arrow.triangle.branch", title: "Per-agent routing",
              detail: "Send each of the 8 swarm agents to its best model — Opus for architecture, Haiku for lint passes."),
        .init(icon: "person.crop.circle.badge.plus", title: "Custom agents",
              detail: "Add your own review or QA agents to the swarm with prompts you control."),
        .init(icon: "sparkles", title: "First access",
              detail: "New power features land in Pro first.")
    ]

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    benefitList
                    byokNote
                    planPicker
                    purchaseButton
                    restoreAndLegal
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .task { await pro.loadProducts() }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(LiquidGlass.accent)
                .padding(.top, 12)
            Text("CodeGenie Pro")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Unlock the full-speed build engine and advanced swarm controls.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                .padding(.horizontal, 12)
        }
    }

    private var benefitList: some View {
        GlassCard(title: "What you get", icon: "checkmark.seal.fill", tint: LiquidGlass.success) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(benefits) { b in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: b.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(LiquidGlass.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText)
                            Text(b.detail)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var byokNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LiquidGlass.accentSecondary)
                .padding(.top, 2)
            Text("AI compute still runs on your own Anthropic / OpenAI key, at cost — Pro adds no markup. Building apps stays free without Pro.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            if pro.products.isEmpty {
                planRowPlaceholder(title: "Yearly", price: "$79.99 / yr", badge: "Best value", id: ProStore.ProductID.yearly)
                planRowPlaceholder(title: "Monthly", price: "$9.99 / mo", badge: nil, id: ProStore.ProductID.monthly)
            } else {
                ForEach(pro.products, id: \.id) { product in
                    planRow(
                        title: product.id == ProStore.ProductID.yearly ? "Yearly" : "Monthly",
                        price: product.displayPrice + (product.id == ProStore.ProductID.yearly ? " / yr" : " / mo"),
                        badge: product.id == ProStore.ProductID.yearly ? "Save ~33%" : nil,
                        id: product.id
                    )
                }
            }
        }
    }

    private func planRow(title: String, price: String, badge: String?, id: String) -> some View {
        Button { selected = id; Haptics.selection() } label: { planRowContent(title: title, price: price, badge: badge, id: id) }
            .buttonStyle(.plain)
    }

    // Shown before StoreKit products load (or in previews); not tappable-to-buy.
    private func planRowPlaceholder(title: String, price: String, badge: String?, id: String) -> some View {
        Button { selected = id } label: { planRowContent(title: title, price: price, badge: badge, id: id) }
            .buttonStyle(.plain)
    }

    private func planRowContent(title: String, price: String, badge: String?, id: String) -> some View {
        let isSel = selected == id
        return GlassSurface(tier: .raised, corner: 18) {
            HStack(spacing: 12) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSel ? LiquidGlass.accent : LiquidGlass.primaryText.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(LiquidGlass.success, in: Capsule())
                        }
                    }
                    Text(price)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                }
                Spacer()
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isSel ? LiquidGlass.accent.opacity(0.9) : .clear, lineWidth: 2)
        )
    }

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                title: pro.purchaseInFlight ? "Processing…" : "Start CodeGenie Pro",
                systemImage: "sparkles",
                style: .filled
            ) {
                guard let product = pro.products.first(where: { $0.id == selected }) else { return }
                Task {
                    if await pro.purchase(product) { dismiss() }
                }
            }
            .disabled(pro.purchaseInFlight || pro.products.isEmpty)

            if let err = pro.lastError {
                Text(err)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Auto-renews until cancelled. Manage or cancel anytime in Settings → Apple ID → Subscriptions.")
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var restoreAndLegal: some View {
        HStack(spacing: 16) {
            Button("Restore") { Task { await pro.restore(); if pro.isPro { dismiss() } } }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.accent)
            Link("Terms", destination: URL(string: "https://codegenie.app/terms")!)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
            Link("Privacy", destination: URL(string: "https://codegenie.app/privacy")!)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .padding(.top, 4)
    }
}
