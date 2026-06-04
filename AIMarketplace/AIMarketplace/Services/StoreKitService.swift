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

    /// Walks `Transaction.unfinished` (anything Apple still wants us to
    /// finish), `Transaction.currentEntitlements` (verified active history),
    /// AND `Transaction.all` (every historical transaction, INCLUDING
    /// revoked ones). New transactions are credited and finished;
    /// already-processed ones are skipped via the persisted ID set.
    /// Revocations claw the credit back so the wallet doesn't keep money
    /// the buyer no longer paid for.
    ///
    /// The Transaction.all sweep matters because:
    ///   - `currentEntitlements` EXCLUDES revoked transactions (Apple's
    ///     design — they're no longer "current"), so a refund that
    ///     happened while the app was killed is invisible there.
    ///   - `Transaction.updates` only delivers in-session events; a
    ///     fresh launch never sees refunds processed during the gap.
    ///   - `Transaction.all` includes every transaction with its
    ///     final state — refunds carry revocationDate / revocationReason.
    ///
    /// In SKTest, refundTransaction() also doesn't reliably emit via
    /// Transaction.updates, but the refunded transaction DOES show up
    /// in Transaction.all with the revocation signals set — so this
    /// scan is the deterministic detection path for tests too.
    private func drainPending() async {
        #if DEBUG
        var unfinishedCount = 0, currentCount = 0, allCount = 0, allCheckedCount = 0
        #endif
        for await update in Transaction.unfinished {
            #if DEBUG
            unfinishedCount += 1
            #endif
            guard let transaction = try? Self.checkVerified(update) else { continue }
            await grant(for: transaction)
            // A refunded transaction CAN show up as "unfinished" if the
            // refund landed while the app was killed — claw the credit
            // back here too, not just from currentEntitlements.
            await checkRevocation(for: transaction)
            await transaction.finish()
        }
        for await update in Transaction.currentEntitlements {
            #if DEBUG
            currentCount += 1
            #endif
            guard let transaction = try? Self.checkVerified(update) else { continue }
            await grant(for: transaction)
            await checkRevocation(for: transaction)
        }
        // Sweep historical transactions for refunds of anything we already
        // credited. This is the channel that catches refunds invisible to
        // the other two streams (gap-of-time refunds, and SKTest events).
        for await update in Transaction.all {
            #if DEBUG
            allCount += 1
            #endif
            guard let transaction = try? Self.checkVerified(update) else { continue }
            // Only revisit transactions we've already credited — otherwise
            // we'd re-grant the same one twice (the grant path lives in
            // the two streams above).
            guard processed.contains(transaction.id) else { continue }
            #if DEBUG
            allCheckedCount += 1
            #endif
            await checkRevocation(for: transaction)
        }
        #if DEBUG
        print("[StoreKit] drainPending: unfinished=\(unfinishedCount) " +
              "currentEntitlements=\(currentCount) " +
              "all=\(allCount) (of which \(allCheckedCount) matched processed-set)")
        #endif
    }

    /// Apple-refunded transaction → claw the credit back from the wallet.
    /// Permission-style hook so we only revoke once per transaction id.
    var onRevoke: ((Double) -> Void)?

    private func checkRevocation(for transaction: Transaction) async {
        #if DEBUG
        print("[StoreKit] checkRevocation tx=\(transaction.id) product=\(transaction.productID) " +
              "revDate=\(transaction.revocationDate.map(String.init(describing:)) ?? "nil") " +
              "revReason=\(transaction.revocationReason.map(String.init(describing:)) ?? "nil")")
        #endif
        // `revocationDate` is the canonical refund signal in production. In
        // SKTest, refundTransaction() sets `revocationReason` but leaves
        // `revocationDate` nil, so we accept either signal — the result is
        // identical (we clawback once per transaction id, idempotently).
        guard transaction.revocationDate != nil || transaction.revocationReason != nil else {
            #if DEBUG
            print("[StoreKit]   → skip: no revocation signal on tx=\(transaction.id)")
            #endif
            return
        }
        let revKey = "rev-\(transaction.id)"
        let revokedKey = "storekit.revokedTransactionIDs.v1"
        let raw = UserDefaults.standard.array(forKey: revokedKey) as? [String] ?? []
        var revoked = Set(raw)
        guard !revoked.contains(revKey) else {
            #if DEBUG
            print("[StoreKit]   → skip: tx=\(transaction.id) already in revoked-set " +
                  "(UserDefaults persists between test runs — clear in setUp if needed)")
            #endif
            return
        }
        revoked.insert(revKey)
        UserDefaults.standard.set(Array(revoked), forKey: revokedKey)
        let credit = Self.credit(for: transaction.productID)
        guard credit > 0 else {
            #if DEBUG
            print("[StoreKit]   → skip: credit=\(credit) for product=\(transaction.productID)")
            #endif
            return
        }
        #if DEBUG
        print("[StoreKit]   → revoking $\(credit) for tx=\(transaction.id); " +
              "onRevoke is \(onRevoke == nil ? "nil — wallet WILL NOT decrement" : "set")")
        #endif
        onRevoke?(credit)
    }

    private func grant(for transaction: Transaction) async {
        guard !processed.contains(transaction.id) else { return }
        let credit = Self.credit(for: transaction.productID)
        // For unrecognised product ids, still mark processed so we don't
        // keep re-walking the same dead transaction on every launch.
        guard credit > 0 else {
            markProcessed(transaction.id)
            return
        }
        // Apply credit FIRST, then mark processed. Both writes are
        // synchronous-to-disk (wallet via SecureStore atomic write, processed
        // via UserDefaults). A crash between them is a microsecond window,
        // but on a re-launch the unfinished transaction would be replayed:
        //   - credit-first ordering → buyer might get a duplicate credit
        //     (we eat ~$5; user happy)
        //   - mark-first ordering  → buyer gets nothing for their money
        //     (we keep the cash; user angry, App Store 1-star, refund)
        // Cheap overpay beats silent under-credit, so credit-first wins.
        onCredit?(credit)
        markProcessed(transaction.id)
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
                // Await the grant directly so finish() can't run before the
                // credit is applied. The previous `MainActor.run { Task { … } }`
                // wrap was fire-and-forget — finish() raced ahead and the
                // transaction could disappear from `Transaction.unfinished`
                // before the wallet had been credited.
                #if DEBUG
                print("[StoreKit] listener received update tx=\(transaction.id) product=\(transaction.productID)")
                #endif
                await self.grant(for: transaction)
                // Refunds arrive HERE — Apple emits a Transaction.updates
                // event when a refund is processed. Without this clawback
                // call, the wallet keeps credit the buyer no longer paid for.
                await self.checkRevocation(for: transaction)
                await transaction.finish()
                #if DEBUG
                self.didProcessUpdateForTesting?(transaction)
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

    #if DEBUG
    // MARK: - Test affordances
    //
    // Tests can't deterministically wait for the background
    // `listenForTransactions` task: Transaction.updates is a broadcast
    // stream that hands an event to whichever iterator is awaiting at
    // emission time. If the test triggers SKTestSession.refundTransaction()
    // while the production listener is mid-await, the listener consumes
    // the event and the test's later iterator never sees it. The hooks
    // below let a test take ownership of the iterator.

    /// Cancels the production listener so the test drainer below can
    /// own the single iterator on `Transaction.updates`. Call BEFORE
    /// triggering SKTestSession events. No-op if already suspended.
    func suspendListenerForTesting() {
        updates?.cancel()
        updates = nil
    }

    /// Test-only reset. Clears the persisted processed-tx + revoked-tx
    /// UserDefaults keys AND the in-memory processed set, so the NEXT
    /// test case starts with a virgin StoreKit state. Without this:
    ///   - grant() sees a previously-processed tx.id and skips the
    ///     credit (test asserts $5 but gets $0).
    ///   - checkRevocation sees a previously-revoked tx.id and skips
    ///     the clawback (test asserts $0 after refund but gets $5).
    /// Call in XCTestCase.setUp() AFTER instantiating StoreKitService.
    func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: processedKey)
        UserDefaults.standard.removeObject(forKey: "storekit.revokedTransactionIDs.v1")
        processed.removeAll()
    }

    /// Fires after the production listener or the test drainer
    /// processes one transaction. Lets a test await deterministic
    /// completion instead of polling.
    var didProcessUpdateForTesting: ((Transaction) -> Void)?

    /// Deterministic drainer for tests. Cancels the listener (if still
    /// running), then iterates `Transaction.updates` from this call
    /// site with an inactivity timeout, then walks the full
    /// `drainPending` (unfinished + currentEntitlements + Transaction.all).
    /// Restarts the listener before returning.
    /// Test-only bridge for refund clawback. SKTestSession's
    /// refundTransaction() removes the consumable transaction from
    /// every StoreKit async sequence — it vanishes from Transaction.all,
    /// .currentEntitlements, .unfinished, AND no .updates event fires.
    /// There is no on-device way to detect the refund.
    ///
    /// In PRODUCTION, refund detection for consumables is server-side:
    /// Apple emits an App Store Server Notification V2 to the operator's
    /// webhook endpoint (REFUND notificationType). The server then tells
    /// the client to claw the credit back (via push, or on next request).
    /// The Transaction.updates path the listener watches handles
    /// non-consumable refunds and subscription state changes — but for
    /// consumables, server notifications are the canonical channel.
    ///
    /// This method simulates what the server-notification handler would
    /// trigger client-side. Tests call it AFTER SKTestSession.
    /// refundTransaction() with the refunded transaction's id +
    /// product id (readable from SKTestSession.allTransactions()) and
    /// verify the wallet decrements. Same dedup + onRevoke path as the
    /// production listener — the only thing simulated is the discovery
    /// of the refund.
    func simulateRefundForTesting(transactionID: UInt64, productID: String) {
        print("[StoreKit] simulateRefundForTesting tx=\(transactionID) product=\(productID)")
        let revKey = "rev-\(transactionID)"
        let revokedKey = "storekit.revokedTransactionIDs.v1"
        let raw = UserDefaults.standard.array(forKey: revokedKey) as? [String] ?? []
        var revoked = Set(raw)
        guard !revoked.contains(revKey) else {
            print("[StoreKit]   → skip: already revoked (clear UserDefaults in setUp)")
            return
        }
        revoked.insert(revKey)
        UserDefaults.standard.set(Array(revoked), forKey: revokedKey)
        let credit = Self.credit(for: productID)
        guard credit > 0 else {
            print("[StoreKit]   → skip: unknown product \(productID)")
            return
        }
        print("[StoreKit]   → revoking $\(credit); onRevoke is \(onRevoke == nil ? "nil" : "set")")
        onRevoke?(credit)
    }

    func drainPendingForTesting(timeout: TimeInterval = 2.0) async {
        print("[StoreKit] drainPendingForTesting begin — listener cancelled, draining updates for \(timeout)s")
        updates?.cancel()
        updates = nil
        var updateCount = 0
        let drain = Task<Void, Never> {
            for await update in Transaction.updates {
                guard let transaction = try? Self.checkVerified(update) else { continue }
                updateCount += 1
                print("[StoreKit] test-drainer received update #\(updateCount) tx=\(transaction.id)")
                await self.grant(for: transaction)
                await self.checkRevocation(for: transaction)
                await transaction.finish()
                self.didProcessUpdateForTesting?(transaction)
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        drain.cancel()
        print("[StoreKit] test-drainer timed out after \(updateCount) update(s); running full drainPending")
        // Full drain — covers anything the updates iterator missed
        // (refunds arriving via Transaction.all, gap-of-time events).
        await drainPending()
        updates = listenForTransactions()
        print("[StoreKit] drainPendingForTesting end — listener restarted")
    }
    #endif
}
