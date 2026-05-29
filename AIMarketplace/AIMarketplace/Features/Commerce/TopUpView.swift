import SwiftUI
import StoreKit
import PassKit

/// Wallet top-up via StoreKit consumable credit packs or Apple Pay — the
/// compliant way to take real money for digital purchases on iOS.
struct TopUpView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKit = StoreKitService()
    @StateObject private var applePay = ApplePayService()
    @State private var purchasing: String?
    /// Strong reference keeping the Apple Pay delegate alive through the async flow.
    @State private var topUpDelegate: TopUpDelegate?

    /// Preset top-up amounts for the Apple Pay shortcut.
    private let topUpAmounts: [(label: String, amount: Double)] = [
        ("$5", 5), ("$10", 10), ("$25", 25), ("$50", 50)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard(title: "Wallet balance", icon: "creditcard.fill", tint: Theme.accent) {
                        Text(String(format: "$%.2f", store.walletBalance))
                            .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    }

                    // ── Apple Pay quick top-up ──
                    if applePay.canMakePayments {
                        SectionHeader(title: "Quick top-up with Apple Pay")
                        HStack(spacing: 10) {
                            ForEach(topUpAmounts, id: \.amount) { preset in
                                Button {
                                    presentApplePayTopUp(amount: preset.amount)
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(preset.label)
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .foregroundStyle(Theme.ink)
                                        Text("Apple Pay")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Theme.inkSoft)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Charges your card directly. Credit lands in your wallet instantly.")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                    }

                    // ── StoreKit credit packs ──
                    SectionHeader(title: applePay.canMakePayments ? "Or add credit via App Store" : "Add credit")

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

    // MARK: - Apple Pay top-up

    /// Presents the native Apple Pay sheet for a wallet top-up.
    private func presentApplePayTopUp(amount: Double) {
        let request = applePay.topUpRequest(amount: amount)
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        let delegate = TopUpDelegate(store: store, amount: amount)
        controller.delegate = delegate
        topUpDelegate = delegate           // hold strong reference
        controller.present()
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

/// Handles Apple Pay top-up authorization — adds credit to wallet on success.
/// Held strongly by TopUpView so it survives through the async payment flow.
class TopUpDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {
    let store: MarketplaceStore
    let amount: Double

    init(store: MarketplaceStore, amount: Double) {
        self.store = store
        self.amount = amount
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        store.walletBalance += amount
        Haptics.success()
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        // Controller dismisses itself after this callback.
    }
}