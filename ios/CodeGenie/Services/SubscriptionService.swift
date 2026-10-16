import Foundation
import StoreKit

/// Manages StoreKit 2 subscriptions for CodeGenie's tiered pricing.
///
/// Tiers:
///   - **Free** — 3 builds / calendar month, $0.
///   - **Pro**  — 30 builds / month, $9.99.
///   - **Studio** — unlimited builds, $29 / month.
///
/// On launch the service checks `Transaction.currentEntitlements` to
/// restore the active tier, and listens for `Transaction.updates` so
/// upgrades / downgrades / cancellations take effect immediately.
///
/// Monthly build counts are persisted in `UserDefaults` with a key that
/// encodes the calendar month (e.g. `"builds.2026-10"`), so the counter
/// auto-resets when the month rolls over.
@MainActor
final class SubscriptionService: ObservableObject {

    // MARK: - Tier

    enum Tier: String, CaseIterable, Comparable {
        case free   = "free"
        case pro    = "codegenie.pro.monthly"
        case studio = "codegenie.studio.monthly"

        var displayName: String {
            switch self {
            case .free:   return "Free"
            case .pro:    return "Pro"
            case .studio: return "Studio"
            }
        }

        /// Maximum builds allowed per calendar month.
        var monthlyBuilds: Int {
            switch self {
            case .free:   return 3
            case .pro:    return 30
            case .studio: return 999 // effectively unlimited
            }
        }

        var price: String {
            switch self {
            case .free:   return "$0"
            case .pro:    return "$9.99"
            case .studio: return "$29"
            }
        }

        // MARK: Comparable

        private var sortOrder: Int {
            switch self {
            case .free:   return 0
            case .pro:    return 1
            case .studio: return 2
            }
        }

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }

    // MARK: - Published state

    @Published private(set) var currentTier: Tier = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading = false

    /// Builds consumed during the current calendar month.
    @Published private(set) var buildsThisMonth: Int = 0

    // MARK: - Derived

    var buildsRemaining: Int {
        max(currentTier.monthlyBuilds - buildsThisMonth, 0)
    }

    var canBuild: Bool {
        buildsThisMonth < currentTier.monthlyBuilds
    }

    // MARK: - Private

    private var transactionListener: Task<Void, Never>?
    private let productIDs: Set<String> = Set(
        Tier.allCases.compactMap { $0 == .free ? nil : $0.rawValue }
    )

    private static let buildsKeyPrefix = "builds."
    private static let monthKeyName    = "builds.currentMonth"

    // MARK: - Singleton (optional — kept injectable for testing)

    static let shared = SubscriptionService()

    // MARK: - Lifecycle

    init() {
        loadBuildsCount()
        transactionListener = listenForTransactions()
        Task { await refreshStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    /// Fetches `Product` metadata from the App Store.
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: productIDs)
            // Sort ascending by price so Pro comes before Studio.
            products = storeProducts.sorted { ($0.price) < ($1.price) }
        } catch {
            purchaseError = "Unable to load products: \(error.localizedDescription)"
        }
    }

    /// Initiates a purchase flow for the given `Product`.
    func purchase(_ product: Product) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateTierFromEntitlements()

            case .userCancelled:
                break

            case .pending:
                purchaseError = "Purchase is pending approval."

            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Restores purchases by re-syncing entitlements from the App Store.
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updateTierFromEntitlements()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Increments the monthly build counter and persists it.
    func recordBuild() {
        buildsThisMonth += 1
        persistBuildsCount()
    }

    /// Re-reads `Transaction.currentEntitlements` and updates `currentTier`.
    func refreshStatus() async {
        await updateTierFromEntitlements()
    }

    // MARK: - Private helpers

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.updateTierFromEntitlements()
                }
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func updateTierFromEntitlements() async {
        var highest: Tier = .free

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if let tier = Tier(rawValue: transaction.productID), tier > highest {
                highest = tier
            }
        }

        currentTier = highest
    }

    // MARK: - Build-count persistence

    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func loadBuildsCount() {
        let stored = UserDefaults.standard.string(forKey: Self.monthKeyName) ?? ""
        if stored == currentMonthKey {
            buildsThisMonth = UserDefaults.standard.integer(
                forKey: Self.buildsKeyPrefix + currentMonthKey
            )
        } else {
            // New month — reset counter.
            buildsThisMonth = 0
            UserDefaults.standard.set(currentMonthKey, forKey: Self.monthKeyName)
            UserDefaults.standard.set(0, forKey: Self.buildsKeyPrefix + currentMonthKey)
        }
    }

    private func persistBuildsCount() {
        UserDefaults.standard.set(currentMonthKey, forKey: Self.monthKeyName)
        UserDefaults.standard.set(buildsThisMonth,  forKey: Self.buildsKeyPrefix + currentMonthKey)
    }
}
