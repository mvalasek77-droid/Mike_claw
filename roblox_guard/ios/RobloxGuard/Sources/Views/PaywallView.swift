import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    // Must match the "Privacy Policy URL" field in App Store Connect's App Privacy section.
    static let privacyPolicyURL = URL(string: "https://mvalasek77-droid.github.io/Mike_claw/robloxguard-privacy.html")!

    var reason = "Subscribe to start protecting your child on Roblox."

    @State private var selectedDemoProduct: DemoProduct?
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if purchases.isUsingDemoProducts {
                        demoPlans
                    } else if purchases.products.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else {
                        realPlans
                    }

                    if let message = purchases.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    subscribeButton

                    Button("Restore purchases") {
                        Task { await purchases.restore() }
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity)

                    Text("Auto-renewing subscription billed to your Apple ID. Cancel anytime in Settings → Apple ID → Subscriptions. This app is a monitoring aid, not a complete safety strategy — see Settings for full limitations.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Required by App Store guideline 3.1.2(b): functional links to
                    // Terms of Use and Privacy Policy must be visible at the point of
                    // purchase. PRIVACY_POLICY_URL is a placeholder — see docs/PRIVACY_POLICY.md.
                    HStack(spacing: 16) {
                        Link("Terms of Use (EULA)",
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy Policy", destination: PaywallView.privacyPolicyURL)
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Choose your plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
            .task {
                await purchases.start()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Protect your child on Roblox")
                .font(.title2.bold())
            Text(reason)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Real StoreKit products

    @ViewBuilder
    private var realPlans: some View {
        VStack(spacing: 12) {
            PlanCard(
                title: "Single Child",
                subtitle: "Monitor one Roblox account, full alerts and evidence vault",
                monthly: purchases.products.first { $0.id == ProductID.singleMonthly },
                annual: purchases.products.first { $0.id == ProductID.singleAnnual },
                selectedProductID: selectedRealBinding
            )
            PlanCard(
                title: "Family",
                subtitle: "Up to 5 children, incident reports, priority protection updates",
                monthly: purchases.products.first { $0.id == ProductID.familyMonthly },
                annual: purchases.products.first { $0.id == ProductID.familyAnnual },
                selectedProductID: selectedRealBinding
            )
        }
    }

    private var selectedRealBinding: Binding<String?> {
        Binding(
            get: { purchases.products.first { _ in true }?.id },
            set: { _ in }
        )
    }

    // MARK: - Demo products (Simulator / App Review)

    @ViewBuilder
    private var demoPlans: some View {
        VStack(spacing: 12) {
            DemoPlanCard(
                title: "Single Child",
                subtitle: "Monitor one Roblox account, full alerts and evidence vault",
                annual: purchases.demoProducts.first { $0.id == ProductID.singleAnnual },
                monthly: purchases.demoProducts.first { $0.id == ProductID.singleMonthly },
                selected: $selectedDemoProduct
            )
            DemoPlanCard(
                title: "Family",
                subtitle: "Up to 5 children, incident reports, priority protection updates",
                annual: purchases.demoProducts.first { $0.id == ProductID.familyAnnual },
                monthly: purchases.demoProducts.first { $0.id == ProductID.familyMonthly },
                selected: $selectedDemoProduct
            )
        }
    }

    @ViewBuilder
    private var subscribeButton: some View {
        Button {
            if purchases.isUsingDemoProducts {
                guard let product = selectedDemoProduct else { return }
                Task {
                    isPurchasing = true
                    await purchases.purchaseDemo(product)
                    isPurchasing = false
                    if purchases.activeTier != .none { dismiss() }
                }
            } else {
                // Real StoreKit purchase
                let id = purchases.products.sorted { $0.price < $1.price }.first?.id
                guard let id,
                      let product = purchases.products.first(where: { $0.id == id }) else { return }
                Task {
                    isPurchasing = true
                    await purchases.purchase(product)
                    isPurchasing = false
                    if purchases.activeTier != .none { dismiss() }
                }
            }
        } label: {
            if isPurchasing {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Subscribe").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(purchases.isUsingDemoProducts ? selectedDemoProduct == nil : false)
    }
}

// MARK: - Demo Plan Card

private struct DemoPlanCard: View {
    let title: String
    let subtitle: String
    let annual: DemoProduct?
    let monthly: DemoProduct?
    @Binding var selected: DemoProduct?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let annual {
                    priceOption(annual, badge: "Best value")
                }
                if let monthly {
                    priceOption(monthly, badge: nil)
                }
            }
        }
        .padding()
        .glassCard()
    }

    private func priceOption(_ product: DemoProduct, badge: String?) -> some View {
        let isSelected = selected?.id == product.id
        return Button {
            selected = product
            Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Color.clear.frame(height: 15)
                }
                Text(product.displayPrice)
                    .font(.subheadline.bold())
                Text(product.isAnnual ? "per year" : "per month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.displayPrice) \(product.isAnnual ? "per year" : "per month")\(badge.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Real Plan Card (StoreKit)

private struct PlanCard: View {
    let title: String
    let subtitle: String
    let monthly: Product?
    let annual: Product?
    @Binding var selectedProductID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let annual {
                    priceOption(annual, badge: "Best value")
                }
                if let monthly {
                    priceOption(monthly, badge: nil)
                }
            }
        }
        .padding()
        .glassCard()
    }

    private func priceOption(_ product: Product, badge: String?) -> some View {
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
            Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Color.clear.frame(height: 15)
                }
                Text(product.displayPrice)
                    .font(.subheadline.bold())
                Text(periodLabel(product))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.displayPrice) \(periodLabel(product))\(badge.map { ", \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func periodLabel(_ product: Product) -> String {
        product.subscription?.subscriptionPeriod.unit == .year ? "per year" : "per month"
    }
}