import Foundation
import StoreKit
import SwiftUI

/// Pricing: undercuts the leading competitor (Bark) by roughly 20-35% while
/// keeping healthy margin, since marginal cost per subscriber is near zero
/// (Roblox's API is free; the daily threat-intel run is a shared fixed cost,
/// not per-seat). See README "Pricing" for the full rationale.
enum SubscriptionTier: Int, Comparable {
    case none = 0
    case single = 1
    case family = 2

    var maxChildren: Int {
        switch self {
        case .none: return 0
        case .single: return 1
        case .family: return 5
        }
    }

    var displayName: String {
        switch self {
        case .none: return "No active plan"
        case .single: return "Single Child"
        case .family: return "Family"
        }
    }

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ProductID {
    static let singleMonthly = "com.mikeclaw.robloxguard.single.monthly"
    static let singleAnnual = "com.mikeclaw.robloxguard.single.annual"
    static let familyMonthly = "com.mikeclaw.robloxguard.family.monthly"
    static let familyAnnual = "com.mikeclaw.robloxguard.family.annual"

    static let all = [singleMonthly, singleAnnual, familyMonthly, familyAnnual]

    static func tier(for productID: String) -> SubscriptionTier {
        switch productID {
        case singleMonthly, singleAnnual: return .single
        case familyMonthly, familyAnnual: return .family
        default: return .none
        }
    }
}

/// A demo product used when StoreKit isn't configured (Simulator without
/// .storekit scheme, or App Review before ASC products are approved).
/// Has the same display properties as StoreKit's `Product` so the paywall
/// looks identical to production.
struct DemoProduct: Identifiable, Hashable {
    let id: String
    let displayName: String
    let displayPrice: String
    let tier: SubscriptionTier
    let isAnnual: Bool

    static let all: [DemoProduct] = [
        DemoProduct(id: ProductID.singleAnnual, displayName: "Single Child (Annual)",
                    displayPrice: "$34.00", tier: .single, isAnnual: true),
        DemoProduct(id: ProductID.singleMonthly, displayName: "Single Child (Monthly)",
                    displayPrice: "$3.99", tier: .single, isAnnual: false),
        DemoProduct(id: ProductID.familyAnnual, displayName: "Family (Annual)",
                    displayPrice: "$69.00", tier: .family, isAnnual: true),
        DemoProduct(id: ProductID.familyMonthly, displayName: "Family (Monthly)",
                    displayPrice: "$8.99", tier: .family, isAnnual: false),
    ]
}

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published var demoProducts: [DemoProduct] = []
    @Published private(set) var activeTier: SubscriptionTier = .none
    @Published var errorMessage: String?

    /// True when using demo products instead of real StoreKit products.
    /// Happens on Simulator without .storekit scheme config, or in App
    /// Review before ASC products are approved.
    private(set) var isUsingDemoProducts = false

    /// Demo mode for Apple App Review. When enabled via Settings or launch
    /// argument, the app auto-links a demo child with sample alerts and
    /// bypasses the paywall so the reviewer can test every flow.
    #if DEBUG
    @AppStorage("demoMode") var demoMode = false
    #else
    let demoMode = false
    #endif

    private var transactionListener: Task<Void, Never>?
    private var didStart = false

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Idempotent — safe to call from `.task` on every appearance.
    func start() async {
        guard !didStart else { return await refreshEntitlements() }
        didStart = true
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        #if DEBUG
        if demoMode {
            demoProducts = DemoProduct.all
            isUsingDemoProducts = true
            if activeTier == .none { activeTier = .single }
            return
        }
        #endif

        do {
            let real = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
            if real.isEmpty {
                // StoreKit returned no products — fall back to demo products
                // so the paywall still shows prices and is tappable.
                demoProducts = DemoProduct.all
                isUsingDemoProducts = true
            } else {
                products = real
                isUsingDemoProducts = false
            }
        } catch {
            errorMessage = "Couldn't load subscription options: \(error.localizedDescription)"
            demoProducts = DemoProduct.all
            isUsingDemoProducts = true
        }
    }

    /// Purchase a real StoreKit product.
    func purchase(_ product: Product) async {
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    errorMessage = "Purchase could not be verified. Please try again."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Purchase a demo product (Simulator / App Review fallback).
    func purchaseDemo(_ product: DemoProduct) async {
        errorMessage = nil
        activeTier = product.tier
    }

    func restore() async {
        errorMessage = nil

        #if DEBUG
        if demoMode {
            activeTier = .single
            return
        }
        #endif

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Highest active, non-revoked entitlement wins (family > single).
    func refreshEntitlements() async {
        #if DEBUG
        if demoMode && activeTier != .none { return }
        #endif

        var highest: SubscriptionTier = .none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            let tier = ProductID.tier(for: transaction.productID)
            if tier > highest { highest = tier }
        }
        // Don't overwrite a demo-mode entitlement with .none
        #if DEBUG
        if demoMode && highest == .none && activeTier != .none { return }
        #endif
        activeTier = highest
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlements()
            }
        }
    }
}