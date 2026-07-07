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
    @State private var legalDoc: LegalDoc?

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

                    // No Restore button. Wallet-credit packs are CONSUMABLES,
                    // which Apple does not "restore" via AppStore.sync() — the
                    // earlier Restore button triggered Apple's password prompt
                    // and got the app rejected under Guideline 3.1.1 (consumable
                    // IAPs cannot be restored that way). Unfinished or pending
                    // transactions are still drained silently on every app
                    // launch + scenePhase change via StoreKitService.drainPending,
                    // so any credit the buyer paid for and didn't receive lands
                    // automatically without user action. App Review's Restore
                    // affordance requirement applies to non-consumables and
                    // subscriptions only, neither of which the app ships.

                    Text("Purchases are processed by Apple's App Store. On every sale Apple takes its App Store commission first; of the net, creators keep 85% and AI Marketplace keeps 15%. Prices outside the US are set by Apple's regional pricing — local price may differ from the USD equivalent shown.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)

                    HStack(spacing: 16) {
                        Button("Terms of Use") { legalDoc = .terms }
                        Button("Privacy Policy") { legalDoc = .privacy }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground().ignoresSafeArea())
            .navigationTitle("Top Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $legalDoc) { LegalSheet(doc: $0) }
        .task {
            // Defensive silent drain on every Top Up open. Walks
            // Transaction.unfinished / .currentEntitlements / .all so any
            // credit the buyer paid for that didn't post (kill-before-
            // finish, slow Ask-to-Buy approve, etc.) lands automatically.
            // Critically: NOT restorePurchases() — that calls AppStore.sync()
            // which prompts for the Apple ID password. Consumables can't
            // be restored that way; Apple rejected the previous build for
            // exactly that prompt under Guideline 3.1.1.
            await storeKit.drainPending()
            await storeKit.loadProducts()
        }
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
                    // Always show the USD-equivalent wallet credit so non-USD
                    // buyers see exactly what they get. Apple's price tiers
                    // are set per-region (Tier 5 is €5.99 in eurozone, £4.99
                    // in UK, etc.) and are NOT direct FX conversions, so
                    // what the buyer pays locally is not the same as what
                    // the wallet credits. This line closes that gap.
                    Text(String(format: "= $%.2f USD wallet credit",
                                StoreKitService.credit(for: product.id)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
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

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(Theme.warning)
            Text("Credit packs unavailable right now")
                .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)

            // Show diagnostic detail so TestFlight testers can report WHY
            // products failed to load instead of just seeing "unavailable".
            if let err = storeKit.errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            if let last = ErrorMonitor.shared.entries.filter({ $0.category == "StoreKit" }).last {
                VStack(spacing: 4) {
                    Text("Last StoreKit diagnostic:")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkSoft)
                    Text(last.message)
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.inkSoft)
                    if let detail = last.detail {
                        Text(detail)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(Theme.inkFaint)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 12)
            }
            // Show which product IDs were requested (mismatch is a common cause)
            Text("Requested product IDs:\n\(StoreKitService.creditProductIDs.joined(separator: "\n"))")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)

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
