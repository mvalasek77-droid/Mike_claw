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
///   4. Every purchase carries an `appAccountToken` (a per-user UUID) so Apple's
///      server notifications can route refunds to the correct wallet.
@MainActor
final class StoreKitService: ObservableObject {
    @Published private(set) var gavelPacks: [Product] = []
    @Published private(set) var boostProduct: Product?
    @Published private(set) var subscriptions: [Product] = []
    @Published private(set) var entitledSubscriptionIDs: Set<String> = []
    /// Status archetypes bought with real money (non-consumables).
    @Published private(set) var statusProducts: [Product] = []
    /// Archetype product ids the user owns. Non-consumables are owned
    /// forever, so re-wearing a badge you already bought is free.
    @Published private(set) var ownedStatusIDs: Set<String> = []
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

    /// A consumable Spotlight Boost — 30 minutes at the top of the floor.
    nonisolated static let boostProductID = "com.valasek.auctionbaby.boost.spotlight"
    static let boostMinutes = 30

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
            case .reserve: return ["Everything in Paddle", "Reveal her reserve price", "Auto-rebid to stay on top", "Rewind your last bid"]
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
    /// Called when a previously-granted Gavel pack is refunded. Second arg
    /// is the StoreKit transaction id when the revocation came from Apple
    /// (the `checkRevocation` path); nil when the caller synthesises a
    /// revocation locally without one. AuctionStore uses the id to record
    /// how much was actually clawed under `clawed[txID]` so a later
    /// REFUND_REVERSED restores exactly that.
    var onRevoke: ((Int, String?) -> Void)?
    /// Called when a Spotlight Boost is purchased.
    var onBoost: (() -> Void)?
    /// Called when a status archetype is bought with real money, so the
    /// store can equip it. Wired once at app root.
    var onStatusPurchased: ((Archetype) -> Void)?
    /// Called when a status archetype purchase is refunded/revoked, so the
    /// store can drop the badge back to the best tier still owned.
    var onStatusRevoked: ((Archetype) -> Void)?

    // MARK: Internals

    private var updates: Task<Void, Never>?
    private let processedKey = "auctionbaby.storekit.processed.v1"
    private let revokedKey = "auctionbaby.storekit.revoked.v1"
    private var processed: Set<UInt64>

    #if DEBUG
    var suspendListenerForTesting = false
    var didProcessUpdateForTesting: ((Transaction) -> Void)?
    #endif

    init() {
        let raw = UserDefaults.standard.array(forKey: processedKey) as? [NSNumber] ?? []
        processed = Set(raw.map { $0.uint64Value })
        demoTier = UserDefaults.standard.string(forKey: demoTierKey).flatMap(PassTier.init)
        updates = listenForTransactions()
        Task { await drainPending() }
    }

    deinit { updates?.cancel() }

    // MARK: Loading

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await Product.products(
                for: Self.gavelIDs + [Self.boostProductID] + Self.subscriptionIDs + Archetype.productIDs)
            gavelPacks = all.filter { Self.gavelIDs.contains($0.id) }.sorted { $0.price < $1.price }
            boostProduct = all.first { $0.id == Self.boostProductID }
            subscriptions = all.filter { Self.subscriptionIDs.contains($0.id) }.sorted { $0.price < $1.price }
            statusProducts = all.filter { Archetype.productIDs.contains($0.id) }.sorted { $0.price < $1.price }
            await updateEntitlements()
            ErrorMonitor.shared.record(category: "StoreKit",
                                       message: "Products loaded: \(all.count) items")
        } catch {
            errorMessage = error.localizedDescription
            ErrorMonitor.shared.record(category: "StoreKit",
                                       message: "Product load failed", error: error)
        }
    }

    // MARK: Purchase

    enum PurchaseOutcome { case success, cancelled, pending, failed }

    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID? = nil) async -> PurchaseOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            var options: Set<Product.PurchaseOption> = []
            if let token = appAccountToken {
                options.insert(.appAccountToken(token))
            }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                let handled = await grant(for: transaction)
                await checkRevocation(for: transaction)
                await updateEntitlements()
                if handled { await transaction.finish() }
                ErrorMonitor.shared.record(category: "StoreKit",
                                           message: "Purchase succeeded: \(product.id)")
                return .success
            case .userCancelled:
                ErrorMonitor.shared.record(category: "StoreKit",
                                           message: "Purchase cancelled: \(product.id)")
                return .cancelled
            case .pending:
                ErrorMonitor.shared.record(category: "StoreKit",
                                           message: "Purchase pending: \(product.id)")
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            errorMessage = error.localizedDescription
            ErrorMonitor.shared.record(category: "StoreKit",
                                       message: "Purchase failed: \(product.id)", error: error)
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

    /// Demo Mode Pass (App Review): a tier granted locally, no IAP. Set from
    /// the paywall's demo button when `AuctionStore.demoMode` is active.
    /// Persisted so the reviewer keeps their Pass across launches.
    @Published var demoTier: PassTier? {
        didSet { UserDefaults.standard.set(demoTier?.rawValue, forKey: demoTierKey) }
    }
    private let demoTierKey = "auctionbaby.storekit.demotier.v1"

    func isSubscribed(to tier: PassTier) -> Bool {
        entitledSubscriptionIDs.contains(tier.productID) || demoTier == tier
    }
    var hasPass: Bool { !entitledSubscriptionIDs.isEmpty || demoTier != nil }
    /// Highest active tier, if any.
    var activeTier: PassTier? {
        PassTier.allCases.last {
            entitledSubscriptionIDs.contains($0.productID) || demoTier == $0
        }
    }

    private func updateEntitlements() async {
        var active: Set<String> = []
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productType {
            case .autoRenewable: active.insert(transaction.productID)
            case .nonConsumable where Archetype.productIDs.contains(transaction.productID):
                owned.insert(transaction.productID)
            default: break
            }
        }
        entitledSubscriptionIDs = active
        ownedStatusIDs = owned
    }

    /// True when the user has bought this tier outright (or it's a Gavel/free
    /// tier, which ownership doesn't apply to). Demo Mode owns everything so
    /// a reviewer can exercise the top of the ladder without a $9,999 charge.
    func owns(_ archetype: Archetype) -> Bool {
        guard let id = archetype.productID else { return true }
        return ownedStatusIDs.contains(id) || demoOwnsAllStatus
    }

    /// Demo Mode (App Review) grants every status tier. Set from the app
    /// root when `AuctionStore.demoMode` is active.
    @Published var demoOwnsAllStatus = false

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
        // Status archetypes are non-consumables: ownership comes from
        // updateEntitlements, but a *fresh* purchase should also equip the
        // badge immediately. Keyed by transaction.id like the consumables so
        // a replayed transaction can't re-equip over a later downgrade.
        if transaction.productType == .nonConsumable,
           let tier = Archetype.tier(forProductID: transaction.productID) {
            guard !processed.contains(transaction.id) else { return true }
            guard let onStatusPurchased else { return false }   // retry after wiring
            onStatusPurchased(tier)
            markProcessed(transaction.id)
            return true
        }
        // Subscriptions are entitlement-based; nothing to credit here.
        guard transaction.productType == .consumable else { return true }
        guard !processed.contains(transaction.id) else { return true }
        // Spotlight Boost: a consumable that grants time, not Gavels.
        if transaction.productID == Self.boostProductID {
            guard let onBoost else { return false }
            onBoost()
            markProcessed(transaction.id)
            return true
        }
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

        if transaction.productType == .nonConsumable,
           let tier = Archetype.tier(forProductID: transaction.productID) {
            guard let onStatusRevoked else { return }
            onStatusRevoked(tier)
            ErrorMonitor.shared.record(category: "StoreKit",
                                       message: "Refund clawback: \(tier.title) status",
                                       detail: "txn \(transaction.id), product \(transaction.productID)")
        } else if transaction.productType == .consumable {
            let gavels = Self.gavels(for: transaction.productID)
            if gavels > 0 {
                guard let onRevoke else { return }
                // Pass the tx id so the store can record the ACTUAL amount
                // clawed (floored at zero) under `clawed[txID]`; a later
                // REFUND_REVERSED from the Worker restores exactly that,
                // not the full pack price.
                onRevoke(gavels, "\(transaction.id)")
                ErrorMonitor.shared.record(category: "StoreKit",
                                           message: "Refund clawback: \(gavels) Gavels",
                                           detail: "txn \(transaction.id), product \(transaction.productID)")
            }
        }
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
                #if DEBUG
                if await self.suspendListenerForTesting { continue }
                #endif
                guard let transaction = try? Self.checkVerified(update) else { continue }
                let handled = await self.grant(for: transaction)
                await self.checkRevocation(for: transaction)
                await self.updateEntitlements()
                if handled { await transaction.finish() }
                #if DEBUG
                await self.didProcessUpdateForTesting?(transaction)
                #endif
            }
        }
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }

    // MARK: - Testing

    #if DEBUG
    func resetForTesting() {
        processed.removeAll()
        UserDefaults.standard.removeObject(forKey: processedKey)
        UserDefaults.standard.removeObject(forKey: revokedKey)
        entitledSubscriptionIDs = []
    }

    func drainPendingForTesting() async {
        await drainPending()
    }

    func simulateRefundForTesting(productID: String) {
        let gavels = Self.gavels(for: productID)
        guard gavels > 0 else { return }
        onRevoke?(gavels, nil)
        ErrorMonitor.shared.record(category: "StoreKit",
                                   message: "[TEST] Simulated refund: \(gavels) Gavels")
    }
    #endif
}
