import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?

    let productIDs: [String]

    private var updatesTask: Task<Void, Never>?

    init(productIDs: [String]? = nil) {
        self.productIDs = productIDs ?? SubscriptionStore.configuredProductIDs()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.refreshPurchasedProducts()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var isSubscribed: Bool {
        !activeProductIDs.isDisjoint(with: Set(productIDs))
    }

    func loadProducts() async {
        guard products.isEmpty else { return }

        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let loadedProducts = try await Product.products(for: productIDs)
            products = loadedProducts.sorted { first, second in
                (productIDs.firstIndex(of: first.id) ?? Int.max) < (productIDs.firstIndex(of: second.id) ?? Int.max)
            }
            if products.isEmpty {
                statusMessage = "No subscriptions returned. Check the product IDs and App Store Connect status."
            }
        } catch {
            statusMessage = "Could not load subscriptions: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshPurchasedProducts()
                statusMessage = "Subscription active."
            case .pending:
                statusMessage = "Purchase pending approval."
            case .userCancelled:
                statusMessage = nil
            @unknown default:
                statusMessage = "Purchase did not complete."
            }
        } catch {
            statusMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
            statusMessage = isSubscribed ? "Subscription restored." : "No active ChadDrop subscription found."
        } catch {
            statusMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshPurchasedProducts() async {
        var purchasedIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            purchasedIDs.insert(transaction.productID)
        }

        activeProductIDs = purchasedIDs
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private static func configuredProductIDs() -> [String] {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "CHADDROP_SUBSCRIPTION_PRODUCT_IDS") as? String else {
            return defaultProductIDs
        }

        let configuredIDs = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return configuredIDs.isEmpty ? defaultProductIDs : configuredIDs
    }

    private static let defaultProductIDs = [
        "com.valasek.chaddrop.premium.weekly",
        "com.valasek.chaddrop.premium.annual"
    ]

    enum StoreError: LocalizedError {
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return "Apple could not verify this transaction."
            }
        }
    }
}

extension Product.SubscriptionPeriod {
    var chadDropDisplayText: String {
        let unitName: String
        switch unit {
        case .day:
            unitName = "day"
        case .week:
            unitName = "week"
        case .month:
            unitName = "month"
        case .year:
            unitName = "year"
        @unknown default:
            unitName = "period"
        }

        return value == 1 ? unitName : "\(value) \(unitName)s"
    }
}
