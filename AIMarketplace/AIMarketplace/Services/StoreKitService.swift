import StoreKit
import Combine

/// StoreKit 2 integration for **wallet credit** purchases.
///
/// A user-generated marketplace can't pre-register a non-consumable IAP product
/// for every creator title, and Apple requires digital purchases to use IAP
/// (not Apple Pay). The compliant pattern used here: sell **consumable credit
/// packs** via StoreKit, top up the in-app wallet, then unlock titles by
/// spending that balance. Real money therefore always flows through Apple's IAP.
///
/// Products are defined in `Products.storekit` for local StoreKit testing and
/// must be mirrored in App Store Connect before release.
@MainActor
final class StoreKitService: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    static let creditProductIDs = [
        "com.aimarketplace.credits.5",
        "com.aimarketplace.credits.10",
        "com.aimarketplace.credits.25",
        "com.aimarketplace.credits.50"
    ]

    /// Wallet credit (USD) granted by each consumable product.
    static func credit(for productID: String) -> Double {
        switch productID {
        case "com.aimarketplace.credits.5": return 5
        case "com.aimarketplace.credits.10": return 10
        case "com.aimarketplace.credits.25": return 25
        case "com.aimarketplace.credits.50": return 50
        default: return 0
        }
    }

    /// Invoked on the main actor whenever credit is successfully granted.
    var onCredit: ((Double) -> Void)?

    private var updates: Task<Void, Never>?

    init() {
        updates = listenForTransactions()
    }

    deinit { updates?.cancel() }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.creditProductIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Purchases a credit pack. Returns the credit granted, or nil if the user
    /// cancelled / it's pending / it failed.
    @discardableResult
    func purchase(_ product: Product) async -> Double? {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                let credit = Self.credit(for: transaction.productID)
                onCredit?(credit)
                await transaction.finish()
                return credit
            case .userCancelled, .pending:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                guard let transaction = try? Self.checkVerified(update) else { continue }
                let credit = Self.credit(for: transaction.productID)
                await MainActor.run { self.onCredit?(credit) }
                await transaction.finish()
            }
        }
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}
