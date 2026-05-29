import SwiftUI
import StoreKit

/// Wallet top-up via StoreKit consumable credit packs — the App Store-compliant
/// way to take real money for digital purchases on iOS. Apple processes every
/// charge; the credit then lands in the in-app wallet to spend on titles.
struct TopUpView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKit = StoreKitService()
    @State private var purchasing: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard(title: "Wallet balance", icon: "creditcard.fill", tint: Theme.accent) {
                        Text(String(format: "$%.2f", store.walletBalance))
                            .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    }

                    // ── StoreKit credit packs ──
                    SectionHeader(title: "Add credit")

                    if storeKit.isLoading && storeKit.products.isEmpty {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if storeKit.products.isEmpty {
                        unavailable
                    } else {
                        ForEach(storeKit.products, id: \.id) { product in
                            packRow(product)
                        }
                    }

                    Text("Purchases are processed by Apple's App Store. Of each sale, creators keep 85% and AI Marketplace keeps 15%.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Top Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            storeKit.onCredit = { credit in store.walletBalance += credit }
            await storeKit.loadProducts()
        }
    }

    private func packRow(_ product: Product) -> some View {
        Button {
            purchasing = product.id
            Task {
                if await storeKit.purchase(product) != nil { Haptics.success() }
                purchasing = nil
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text(product.description).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                if purchasing == product.id {
                    ProgressView().tint(Theme.accent)
                } else {
                    Text(product.displayPrice)
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(purchasing != nil)
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(Theme.warning)
            Text("Credit packs unavailable")
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Run with the Products.storekit configuration enabled in your scheme, or check App Store Connect setup.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}