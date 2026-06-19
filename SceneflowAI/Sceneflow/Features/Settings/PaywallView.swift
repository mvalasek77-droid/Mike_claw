import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundStyle(Palette.marqueeGradient)
                        .padding(.top, 12)

                    Text("Sceneflow Pro")
                        .font(.displayMedium)
                        .foregroundStyle(Palette.primaryText)

                    Text("Pro screenwriting tools and unlimited AI — for about a quarter of what comparable apps charge.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 24)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Pricing.pro.priceText).font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.primaryText)
                        Text("/ year").foregroundStyle(Palette.secondaryText)
                    }

                    HStack(spacing: 6) {
                        Text("≈ $\(Int(Pricing.competitorAnnualUSD))/yr elsewhere")
                            .strikethrough()
                            .foregroundStyle(Palette.secondaryText)
                        Pill(text: "Save \(Pricing.savingsPercent)%", color: Palette.success)
                    }
                    .font(.caption)

                    GlassCard(tier: .raised) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Pricing.pro.highlights, id: \.self) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Palette.accent)
                                    Text(item).foregroundStyle(Palette.primaryText)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    PrimaryButton(title: "Start free, upgrade anytime", systemImage: "lock.open.fill") {
                        // In production this calls StoreKit 2 purchase. Here it
                        // unlocks the entitlement so the flow is testable.
                        entitlements.unlockPro()
                        dismiss()
                    }
                    .padding(.horizontal, 4)

                    Text("Auto-renews yearly. Cancel anytime in Settings. Restores on this Apple ID.")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(AmbientBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
