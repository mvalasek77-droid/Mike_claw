import SwiftUI
import StoreKit

/// Wallet top-up via StoreKit consumable credit packs — the App Store-compliant
/// way to take real money for digital purchases on iOS. Apple processes every
/// charge; the credit then lands in the in-app wallet to spend on titles.
struct TopUpView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard(title: "Wallet balance", icon: "creditcard.fill", tint: Theme.accent) {
                        Text(String(format: "$%.2f", store.walletBalance))
                            .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    }

                    if store.demoMode {
                        demoPacks
                    }

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

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let err = storeKit.errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    restoreButton

                    Text("Purchases are processed by Apple's App Store. On every sale Apple takes its App Store commission first; of the net, creators keep 85% and AI Marketplace keeps 15%.")
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
        .task { await storeKit.loadProducts() }
    }

    private func packRow(_ product: Product) -> some View {
        Button {
            purchasing = product.id
            statusMessage = nil
            Task {
                // Attach the buyer's stable UUID so Apple includes it in the
                // App Store Server Notification — the Worker uses it to
                // route REFUND events back to this user's wallet.
                let token = store.ensureAppAccountToken()
                let outcome = await storeKit.purchase(product, appAccountToken: token)
                switch outcome {
                case .success:
                    Haptics.success()
                case .pending:
                    statusMessage = "Awaiting approval. The credit will appear once approved — you can close this screen."
                case .cancelled:
                    break
                case .failed:
                    Haptics.warning()
                }
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
        .disabled(purchasing != nil || storeKit.isRestoring)
    }

    /// Demo-mode credit packs. Visible only when `store.demoMode` is on
    /// (App Review path) — bypasses StoreKit entirely so reviewers can
    /// exercise the buy flow without spending real money or relying on
    /// the StoreKit sandbox. Real IAP packs still appear below for the
    /// reviewer to verify the production path too.
    @ViewBuilder
    private var demoPacks: some View {
        SectionHeader(title: "Demo top-ups (no charge)")
        VStack(spacing: 8) {
            ForEach([5.00, 10.00, 25.00, 50.00], id: \.self) { amount in
                Button {
                    store.addDemoCredit(amount: amount)
                    statusMessage = String(format: "Demo credit added: $%.2f", amount)
                    Haptics.success()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "wand.and.stars").font(.system(size: 18)).foregroundStyle(Theme.kdp)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.kdp.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "Demo · $%.0f credit", amount))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text("Bypasses Apple IAP — App Review use only.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                        Text("FREE")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.kdp))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.kdp.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerM).strokeBorder(Theme.kdp.opacity(0.4), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// App Review 3.1.1 requires every IAP-selling app to expose a Restore
    /// affordance. Consumable credit can't be "re-granted" once spent, but
    /// pending or unfinished transactions can — and Apple wants this button
    /// visible regardless.
    private var restoreButton: some View {
        Button {
            Task {
                statusMessage = nil
                let before = store.walletBalance
                await storeKit.restorePurchases()
                let added = store.walletBalance - before
                statusMessage = added > 0
                    ? String(format: "Restored $%.2f in credit.", added)
                    : "No pending purchases to restore."
            }
        } label: {
            HStack(spacing: 8) {
                if storeKit.isRestoring {
                    ProgressView().tint(Theme.inkSoft)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                }
                Text(storeKit.isRestoring ? "Restoring…" : "Restore previous purchases")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
        .disabled(storeKit.isRestoring)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(Theme.warning)
            Text("Credit packs unavailable right now")
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            Text("Please check your connection and try again. If the issue persists, contact support.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
            Button("Try again") {
                Task { await storeKit.loadProducts() }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}
