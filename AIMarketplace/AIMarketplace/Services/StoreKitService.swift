import StoreKit
import Combine
import Foundation

/// StoreKit 2 integration for **wallet credit** purchases.
///
/// A user-generated marketplace can't pre-register a non-consumable IAP product
/// for every creator title, and Apple requires digital purchases to use IAP
/// (not Apple Pay). The compliant pattern used here: sell **consumable credit
/// packs** via StoreKit, top up the in-app wallet, then unlock titles by
/// spending that balance. Real money therefore always flows through Apple's IAP.
///
/// Hardening invariants — guard real money:
///   1. Every grant is keyed by `transaction.id`; the set is persisted, so the
///      same Apple transaction is never granted twice across launches.
///   2. On init we drain `Transaction.unfinished` AND iterate
///      `currentEntitlements` so a kill-before-finish never loses credit.
///   3. `onCredit` is wired by the app root, not by a transient sheet, so
///      transactions that land while no sheet is open still credit the wallet.
///   4. `restorePurchases()` calls `AppStore.sync()` and re-drains, satisfying
///      App Review 3.1.1.
@MainActor
final class StoreKitService: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRestoring = false
    @Published var errorMessage: String?

    nonisolated static let products: [(id: String, credit: Double)] = [
        ("com.aimarketplace.credits.5",  5),
        ("com.aimarketplace.credits.10", 10),
        ("com.aimarketplace.credits.25", 25),
        ("com.aimarketplace.credits.50", 50),
    ]

    nonisolated static var creditProductIDs: [String] { products.map(\.id) }

    nonisolated static func credit(for productID: String) -> Double {
        products.first(where: { $0.id == productID })?.credit ?? 0
    }

    /// Invoked on the main actor whenever credit is successfully granted.
    /// Wire this **once at app launch**, never inside a transient sheet — a
    /// transaction can arrive at any time and dropping the closure means
    /// dropping money.
    var onCredit: ((Double) -> Void)?

    private var updates: Task<Void, Never>?
    private let processedKey = "storekit.processedTransactionIDs.v1"
    private var processed: Set<UInt64>

    init() {
        let raw = UserDefaults.standard.array(forKey: processedKey) as? [NSNumber] ?? []
        self.processed = Set(raw.map { $0.uint64Value })
        updates = listenForTransactions()
        Task { await drainPending() }
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

    /// Purchases a credit pack. The credit is granted via the transaction
    /// listener (single path) so we can't double-credit. Returns true on a
    /// successful, verified purchase; false on user-cancel; nil on pending.
    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await grant(for: transaction)
                await transaction.finish()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    enum PurchaseOutcome { case success, cancelled, pending, failed }

    /// App Review 3.1.1: every IAP-selling app must expose Restore. Also
    /// pulls down any unfinished transactions Apple has queued for this Apple ID.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await drainPending()
    }

    /// Walks both `Transaction.unfinished` (anything Apple still wants us to
    /// finish) and `Transaction.currentEntitlements` (verified history). New
    /// transactions are credited and finished; already-processed ones are
    /// skipped via the persisted ID set.
    private func drainPending() async {
        for await update in Transaction.unfinished {
            guard let transaction = try? Self.checkVerified(update) else { continue }
            await grant(for: transaction)
            await transaction.finish()
        }
        for await update in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(update) else { continue }
            await grant(for: transaction)
        }
    }

    private func grant(for transaction: Transaction) async {
        guard !processed.contains(transaction.id) else { return }
        processed.insert(transaction.id)
        UserDefaults.standard.set(processed.map { NSNumber(value: $0) }, forKey: processedKey)
        let credit = Self.credit(for: transaction.productID)
        guard credit > 0 else { return }
        onCredit?(credit)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                guard let transaction = try? Self.checkVerified(update) else { continue }
                await MainActor.run { Task { await self.grant(for: transaction) } }
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
