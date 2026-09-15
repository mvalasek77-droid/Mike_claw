import Foundation
import StoreKit
import Combine

/// StoreKit 2 wrapper. Loads the three subscription products, exposes
/// prices, drives the purchase flow, and listens for transaction updates
/// to activate / deactivate memberships.
///
/// Debug builds can fall back to a demo purchase when no StoreKit
/// Configuration is attached. Release builds never grant paid access
/// without a verified App Store transaction.
@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Membership: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var lastError: String?
    @Published var purchaseInFlight: Membership?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task { await listenForTransactions() }
    }

    // MARK: - Product loading

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        let ids = Set(Membership.paidTiers.compactMap { $0.productId })
        do {
            let fetched = try await Product.products(for: ids)
            var map: [Membership: Product] = [:]
            for tier in Membership.paidTiers {
                if let pid = tier.productId,
                   let product = fetched.first(where: { $0.id == pid }) {
                    map[tier] = product
                }
            }
            self.products = map
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Display price. Uses live StoreKit price if available; otherwise
    /// falls back to the hard-coded label from `Membership`.
    func displayPrice(for tier: Membership) -> String {
        if let p = products[tier] { return p.displayPrice + " / mo" }
        return tier.priceString
    }

    // MARK: - Purchase

    func buy(_ tier: Membership) async {
        guard tier.isPaid else { return }
        purchaseInFlight = tier
        defer { purchaseInFlight = nil }

        if let product = products[tier] {
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let tx) = verification {
                        PortfolioService.shared.activateMembership(tier)
                        await tx.finish()
                    } else {
                        lastError = "Purchase could not be verified."
                    }
                case .userCancelled:
                    break
                case .pending:
                    lastError = "Purchase is pending approval."
                @unknown default:
                    break
                }
            } catch {
                lastError = error.localizedDescription
            }
        } else {
            #if DEBUG
            // Keep local development testable without live App Store products.
            PortfolioService.shared.activateMembership(tier)
            #else
            lastError = "Subscriptions are temporarily unavailable. Please try again later."
            #endif
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            // Pick the RICHEST entitlement, not the longest-named one.
            // Membership.paidTiers is ordered ascending — cheapest first.
            var best: Membership = .free
            for await result in Transaction.currentEntitlements {
                guard case .verified(let tx) = result,
                      let tier = Membership.paidTiers.first(where: { $0.productId == tx.productID })
                else { continue }
                let bestIndex = Membership.paidTiers.firstIndex(of: best) ?? -1
                let thisIndex = Membership.paidTiers.firstIndex(of: tier) ?? -1
                if thisIndex > bestIndex { best = tier }
            }
            if best.isPaid {
                PortfolioService.shared.activateMembership(best, grantStartingBonus: false)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Transaction stream

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let tx) = result else { continue }
            if let tier = Membership.paidTiers.first(where: { $0.productId == tx.productID }) {
                if tx.revocationDate != nil {
                    PortfolioService.shared.downgradeToFree()
                } else {
                    PortfolioService.shared.activateMembership(tier, grantStartingBonus: false)
                }
            }
            await tx.finish()
        }
    }
}
