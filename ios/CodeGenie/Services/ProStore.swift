import Foundation
import StoreKit

/// CodeGenie Pro — the app's single monetization path, sold through
/// StoreKit so it is App-Store-compliant (Apple's rules require any
/// in-app charge for a digital service to go through their billing).
///
/// **What's free, always.** Downloading the app, describing apps, and
/// building them on your *own* Anthropic / OpenAI key (BYOK). CodeGenie
/// adds no markup on AI usage and never resells provider access — that
/// keeps us inside both Apple's and the AI vendors' terms.
///
/// **What Pro unlocks.** The performance + power tier: Maximum Speed
/// (overlapped/parallel review), per-agent model routing, and custom
/// swarm agents. Sold as an auto-renewing subscription — monthly or a
/// discounted yearly.
///
/// The manager degrades gracefully: if StoreKit has no products
/// configured yet (dev builds without a `.storekit` file or before the
/// products exist in App Store Connect), `isPro` is simply `false` and
/// the rest of the app keeps working on the free tier.
@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    /// App Store Connect product identifiers. Create these as an
    /// auto-renewing subscription group ("CodeGenie Pro") in ASC and
    /// mirror a local `Products.storekit` file for development.
    enum ProductID {
        static let monthly = "com.codegenie.pro.monthly"
        static let yearly  = "com.codegenie.pro.yearly"
        static var all: [String] { [monthly, yearly] }
    }

    @Published private(set) var isPro: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Listen for transactions that arrive outside an explicit
        // purchase (renewals, Ask-to-Buy approvals, restores on another
        // device) for the whole app lifetime.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let txn = await self.verified(update) {
                    await txn.finish()
                    await self.refreshEntitlement()
                }
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit { updatesTask?.cancel() }

    var monthly: Product? { products.first { $0.id == ProductID.monthly } }
    var yearly: Product? { products.first { $0.id == ProductID.yearly } }

    /// Fetch the storefront-localized products. Safe to call repeatedly.
    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.all)
            // Stable order: monthly first, then yearly.
            products = loaded.sorted { ($0.id == ProductID.monthly ? 0 : 1) < ($1.id == ProductID.monthly ? 0 : 1) }
        } catch {
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    /// Recompute `isPro` from the user's current entitlements. A Pro
    /// entitlement counts only if it's cryptographically verified and
    /// not revoked.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let txn = await verified(result) else { continue }
            if ProductID.all.contains(txn.productID), txn.revocationDate == nil {
                active = true
            }
        }
        isPro = active
    }

    /// Purchase a Pro product. Returns `true` if the user is now Pro.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        lastError = nil
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let txn = await verified(verification) else {
                    lastError = "That purchase couldn't be verified by the App Store."
                    return false
                }
                await txn.finish()
                await refreshEntitlement()
                return isPro
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-Buy / SCA — entitlement arrives later via the updates stream.
                lastError = "Your purchase is pending approval. Pro unlocks automatically once it's approved."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = "The purchase didn't go through. You weren't charged."
            return false
        }
    }

    /// Restore purchases (e.g. after reinstalling or on a new device).
    func restore() async {
        lastError = nil
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        try? await AppStore.sync()
        await refreshEntitlement()
        if !isPro {
            lastError = "No active CodeGenie Pro subscription was found on this Apple ID."
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) async -> T? {
        switch result {
        case .verified(let safe):   return safe
        case .unverified:           return nil
        }
    }
}
