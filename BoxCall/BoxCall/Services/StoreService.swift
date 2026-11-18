import Foundation
import StoreKit
import Combine

/// StoreKit 2 wrapper. Loads the three subscription products, exposes
/// prices, drives the purchase flow, and listens for transaction updates
/// to activate / deactivate memberships.
///
/// Production builds fail closed when StoreKit products are unavailable.
/// Debug builds retain a local fallback so the paywall can be exercised
/// without an App Store Connect product configuration.
@MainActor
final class StoreService: ObservableObject {
    static let shared = StoreService()

    /// Outcome of the most recent product-load attempt. The paywall uses
    /// this to decide between a spinner, a working subscribe button, and
    /// a retry card — so a slow or unavailable App Store never leaves
    /// the user staring at a frozen sheet.
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded          // At least one product came back.
        case empty           // Fetch returned, nothing matched our ids.
        case failed(String)  // Fetch threw, or timed out.
    }

    @Published private(set) var products: [Membership: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var lastError: String?
    @Published var purchaseInFlight: Membership?

    private var updatesTask: Task<Void, Never>?
    private var activeLoad: Task<Void, Never>?
    private var activeLoadId: UUID?

    /// Hard ceiling for `Product.products(for:)`. On some networks and
    /// on brand-new iOS betas the call can stall far past any reasonable
    /// wait; a bounded timeout means the paywall surfaces a retry
    /// instead of appearing hung. Review device clock is ignored.
    private let loadTimeoutSeconds: UInt64 = 12

    private init() {
        updatesTask = Task { await listenForTransactions() }
    }

    // MARK: - Product loading

    /// Fetch the three subscription products from StoreKit. Idempotent:
    /// a repeat call while one is in flight joins that attempt, and a
    /// repeat call after a successful load is a no-op. A caller that
    /// wants to try again after a failure or empty result should call
    /// `reloadProducts()` instead.
    func loadProducts() async {
        if loadState == .loaded { return }
        if let active = activeLoad {
            await active.value
            return
        }
        await runLoad()
    }

    /// Force a fresh fetch — used by the paywall's "Retry" button after
    /// a failed or empty load.
    func reloadProducts() async {
        activeLoad?.cancel()
        activeLoad = nil
        await runLoad()
    }

    private func runLoad() async {
        // StoreService is a singleton, so capturing self is safe; the
        // explicit [weak self] + unwrap keeps the Task's Success as
        // Void (not Void?) so activeLoad's type matches.
        let loadId = UUID()
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(id: loadId)
        }
        activeLoad = task
        activeLoadId = loadId
        await task.value
        // Only clear `activeLoad` if it still points at the completed
        // task. A newer reload may have replaced it already.
        if activeLoadId == loadId {
            activeLoad = nil
            activeLoadId = nil
        }
    }

    private func performLoad(id: UUID) async {
        // If a newer reload has already replaced us, do nothing — that
        // call owns the state now.
        if activeLoadId != id { return }

        isLoadingProducts = true
        loadState = .loading
        lastError = nil

        let ids = Set(Membership.paidTiers.compactMap { $0.productId })

        do {
            let fetched = try await withThrowingTaskGroup(of: [Product].self) { group in
                group.addTask {
                    try await Product.products(for: ids)
                }
                group.addTask { [loadTimeoutSeconds] in
                    try await Task.sleep(nanoseconds: loadTimeoutSeconds * 1_000_000_000)
                    throw StoreLoadError.timedOut
                }
                guard let first = try await group.next() else {
                    throw StoreLoadError.timedOut
                }
                group.cancelAll()
                return first
            }

            // A reload may have replaced us after the fetch finished.
            // In that case the newer call owns the state; don't trample it.
            if activeLoadId != id { return }

            var map: [Membership: Product] = [:]
            for tier in Membership.paidTiers {
                if let pid = tier.productId,
                   let product = fetched.first(where: { $0.id == pid }) {
                    map[tier] = product
                }
            }
            products = map
            loadState = map.isEmpty ? .empty : .loaded
            isLoadingProducts = false
            if map.isEmpty {
                // Reviewers see this when the IAPs are still "Waiting
                // for Review" — without it, tapping Subscribe appears
                // to do nothing.
                lastError = "Subscriptions aren't available in this build yet. Please try again later."
            }
        } catch is CancellationError {
            // A newer call superseded this one; leave state for it to update.
            return
        } catch StoreLoadError.timedOut {
            if activeLoadId != id { return }
            lastError = "The App Store took too long to respond. Check your connection and tap Retry."
            loadState = .failed(lastError ?? "Timed out")
            isLoadingProducts = false
        } catch {
            if activeLoadId != id { return }
            lastError = error.localizedDescription
            loadState = .failed(error.localizedDescription)
            isLoadingProducts = false
        }
    }

    enum StoreLoadError: Error { case timedOut }

    /// Display price. Uses live StoreKit price if available; otherwise
    /// falls back to the hard-coded label from `Membership`.
    func displayPrice(for tier: Membership) -> String {
        if let p = products[tier] { return p.displayPrice + " / mo" }
        return tier.priceString
    }

    /// `true` once StoreKit has actually confirmed the product. Paywall
    /// uses this to disable Subscribe buttons that can't do anything.
    func canPurchase(_ tier: Membership) -> Bool {
        guard tier.isPaid else { return false }
        #if DEBUG
        return true
        #else
        return products[tier] != nil
        #endif
    }

    /// Clears the last surfaced error so the paywall's alert can be
    /// dismissed and immediately re-triggered on the next failure.
    func clearLastError() { lastError = nil }

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
                        PortfolioService.shared.activateMembership(tier, isNewPurchase: true)
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
            // No product means StoreKit never loaded this tier — no
            // network, products still "Waiting for Review", a mismatched
            // bundle id. Those are ordinary runtime conditions, so a
            // shipped build must fail closed here: granting the tier
            // anyway would unlock paid functionality outside In-App
            // Purchase, which is exactly what Guideline 3.1.1 forbids.
            #if DEBUG
            // Development only, so the tier flow stays testable without a
            // StoreKit configuration attached. Never compiled into a
            // Release build, and so never reachable by App Review.
            PortfolioService.shared.activateMembership(tier, isNewPurchase: true)
            #else
            lastError = "Subscriptions are unavailable right now. Please check your connection and try again."
            #endif
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            let best = await bestEntitlement()
            if best.isPaid {
                PortfolioService.shared.activateMembership(best)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Run at launch: the saved tier follows what the App Store says is
    /// active, so a lapsed subscription drops back to Free.
    func refreshEntitlements() async {
        let best = await bestEntitlement()
        let current = PortfolioService.shared.user.membership
        if best.isPaid {
            if best != current {
                PortfolioService.shared.activateMembership(best)
            }
        } else if current.isPaid {
            #if !DEBUG
            // Debug builds grant tiers without StoreKit, so there's nothing to check against.
            PortfolioService.shared.downgradeToFree()
            #endif
        }
    }

    /// The richest active subscription. Membership.paidTiers is ordered cheapest first.
    private func bestEntitlement() async -> Membership {
        var best: Membership = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  let tier = Membership.paidTiers.first(where: { $0.productId == tx.productID })
            else { continue }
            let bestIndex = Membership.paidTiers.firstIndex(of: best) ?? -1
            let thisIndex = Membership.paidTiers.firstIndex(of: tier) ?? -1
            if thisIndex > bestIndex { best = tier }
        }
        return best
    }

    // MARK: - Transaction stream

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let tx) = result else { continue }
            if let tier = Membership.paidTiers.first(where: { $0.productId == tx.productID }) {
                if tx.revocationDate != nil {
                    PortfolioService.shared.downgradeToFree()
                } else {
                    PortfolioService.shared.activateMembership(tier)
                }
            }
            await tx.finish()
        }
    }
}
