import StoreKit
import Combine
import Foundation

/// StoreKit 2 integration for Auction Baby.
///
/// Two kinds of real-money product, and only these two:
///   • **Gavels** — consumable currency packs. Real money tops up the in-app
///     Gavel balance, which is then spent on status archetypes. (Bids cost
///     nothing — they're letters of intent — so Gavels exist purely for status.)
///   • **Auction Baby Pass** — auto-renewable subscriptions that unlock premium
///     bidder features (rank reveal, auto-rebid, priority placement).
///
/// Money-safety invariants (mirrors the hardened pattern used elsewhere in this
/// repo):
///   1. Every consumable grant is keyed by `transaction.id`; the set is
///      persisted, so the same Apple transaction never double-credits.
///   2. On launch we drain `Transaction.unfinished`, `currentEntitlements` and
///      `Transaction.all`, so a kill-before-finish never loses Gavels and a
///      refund processed while the app was closed is still clawed back.
///   3. `onCredit` is wired once at app root (never in a transient sheet), so a
///      transaction that lands while no store sheet is open still credits.
@MainActor
final class StoreKitService: ObservableObject {
    @Published private(set) var gavelPacks: [Product] = []
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var entitledSubscriptionIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published var isWorking = false
    @Published var errorMessage: String?

    // MARK: Catalog

    nonisolated static let gavelCatalog: [(id: String, gavels: Int)] = [
        ("com.valasek.auctionbaby.gavels.handful", 1_000),
        ("com.valasek.auctionbaby.gavels.stack",   5_000),
        ("com.valasek.auctionbaby.gavels.chest",   14_000),
        ("com.valasek.auctionbaby.gavels.vault",   30_000),
    ]

    nonisolated static var gavelIDs: [String] { gavelCatalog.map(\.id) }
    nonisolated static func gavels(for id: String) -> Int {
        gavelCatalog.first { $0.id == id }?.gavels ?? 0
    }

    /// Subscription tiers, low → high.
    enum PassTier: String, CaseIterable, Identifiable {
        case paddle, reserve, blackcard
        var id: String { rawValue }
        var productID: String { "com.valasek.auctionbaby.sub.\(rawValue)" }
        var title: String {
            switch self {
            case .paddle: return "Paddle"
            case .reserve: return "Reserve"
            case .blackcard: return "Black Card"
            }
        }
        var perks: [String] {
            switch self {
            case .paddle: return ["Unlimited bids", "See if you're the top bid", "1 Boost / week"]
            case .reserve: return ["Everything in Paddle", "Reveal her reserve price", "Auto-rebid to stay on top"]
            case .blackcard: return ["Everything in Reserve", "Priority placement on every lot", "Read receipts"]
            }
        }
        var systemImage: String {
            switch self {
            case .paddle: return "hand.raised.fill"
            case .reserve: return "lock.open.fill"
            case .blackcard: return "creditcard.fill"
            }
        }
    }

    nonisolated static var subscriptionIDs: [String] { PassTier.allCases.map(\.productID) }

    // MARK: Grant hooks (wired once at app root)

    /// Called on the main actor when a consumable Gavel pack is granted.
    var onCredit: ((Int) -> Void)? {
        didSet { if onCredit != nil { Task { await drainPending() } } }
    }
    /// Called when a previously-granted Gavel pack is refunded.
    var onRevoke: ((Int) -> Void)?

    // MARK: Internals

    private var updates: Task<Void, Never>?
    private let processedKey = "auctionbaby.storekit.processed.v1"
    private let revokedKey = "auctionbaby.storekit.revoked.v1"
    private var processed: Set<UInt64>

    init() {
        let raw = UserDefaults.standard.array(forKey: processedKey) as? [NSNumber] ?? []
        processed = Set(raw.map { $0.uint64Value })
        updates = listenForTransactions()
        Task { await drainPending() }
    }

    deinit { updates?.cancel() }

    // MARK: Loading

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await Product.products(for: Self.gavelIDs + Self.subscriptionIDs)
            gavelPacks = all.filter { Self.gavelIDs.contains($0.id) }.sorted { $0.price < $1.price }
            subscriptions = all.filter { Self.subscriptionIDs.contains($0.id) }.sorted { $0.price < $1.price }
            await updateEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Purchase

    enum PurchaseOutcome { case success, cancelled, pending, failed }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                let handled = await grant(for: transaction)
                await checkRevocation(for: transaction)
                await updateEntitlements()
                if handled { await transaction.finish() }
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

    /// Restores subscription/non-consumable entitlements. Required by Apple when
    /// an app sells subscriptions. Prompts for the Apple ID password.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await drainPending()
    }

    // MARK: Subscription state

    func isSubscribed(to tier: PassTier) -> Bool { entitledSubscriptionIDs.contains(tier.productID) }
    var hasPass: Bool { !entitledSubscriptionIDs.isEmpty }
    /// Highest active tier, if any.
    var activeTier: PassTier? {
        PassTier.allCases.last { entitledSubscriptionIDs.contains($0.productID) }
    }

    private func updateEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            if transaction.productType == .autoRenewable, transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        entitledSubscriptionIDs = active
    }

    // MARK: Transaction handling

    /// Drains every channel: unfinished (kill-before-finish), current
    /// entitlements (subscriptions), and all history (gap-of-time refunds).
    func drainPending() async {
        for await update in Transaction.unfinished {
            guard let transaction = try? Self.checkVerified(update) else { continue }
            let handled = await grant(for: transaction)
            await checkRevocation(for: transaction)
            if handled { await transaction.finish() }
        }
        for await update in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(update) else { continue }
            await grant(for: transaction)
            await checkRevocation(for: transaction)
        }
        for await update in Transaction.all {
            guard let transaction = try? Self.checkVerified(update) else { continue }
            guard processed.contains(transaction.id) else { continue }
            await checkRevocation(for: transaction)
        }
        await updateEntitlements()
    }

    /// Returns true when the transaction's value is fully handled and it's safe
    /// to `finish()`. Returns false only when a consumable can't be credited yet
    /// (wallet hook not attached) — so a later drain retries.
    @discardableResult
    private func grant(for transaction: Transaction) async -> Bool {
        // Subscriptions / non-consumables are entitlement-based; nothing to
        // credit here (handled by updateEntitlements).
        guard transaction.productType == .consumable else { return true }
        guard !processed.contains(transaction.id) else { return true }
        let gavels = Self.gavels(for: transaction.productID)
        guard gavels > 0 else { markProcessed(transaction.id); return true }
        // No wallet hook yet (init drains before the app root wires it). Leave
        // it unprocessed AND unfinished so the post-wiring drain replays it —
        // marking processed here would silently eat the buyer's money.
        guard let onCredit else { return false }
        onCredit(gavels)          // credit first…
        markProcessed(transaction.id)  // …then mark, so a crash overpays, never under-credits
        return true
    }

    private func checkRevocation(for transaction: Transaction) async {
        guard transaction.revocationDate != nil || transaction.revocationReason != nil else { return }
        let key = "rev-\(transaction.id)"
        var revoked = Set(UserDefaults.standard.array(forKey: revokedKey) as? [String] ?? [])
        guard !revoked.contains(key) else { return }

        if transaction.productType == .consumable {
            let gavels = Self.gavels(for: transaction.productID)
            if gavels > 0 {
                guard let onRevoke else { return } // retry on next drain once wired
                onRevoke(gavels)
            }
        }
        // Subscriptions are reflected by updateEntitlements (revoked → dropped).
        revoked.insert(key)
        UserDefaults.standard.set(Array(revoked), forKey: revokedKey)
    }

    private func markProcessed(_ id: UInt64) {
        processed.insert(id)
        UserDefaults.standard.set(processed.map { NSNumber(value: $0) }, forKey: processedKey)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                guard let transaction = try? Self.checkVerified(update) else { continue }
                let handled = await self.grant(for: transaction)
                await self.checkRevocation(for: transaction)
                await self.updateEntitlements()
                if handled { await transaction.finish() }
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
