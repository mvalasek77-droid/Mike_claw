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

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var activeTier: SubscriptionTier = .none
    @Published var errorMessage: String?

    /// Demo mode for Apple App Review. When enabled via Settings or launch
    /// argument, the app auto-links a demo child with sample alerts and
    /// grants access only to that local sample data. It never creates a
    /// StoreKit entitlement and cannot monitor a real Roblox account.
    @Published private(set) var demoMode: Bool

    private var transactionListener: Task<Void, Never>?
    private var didStart = false

    init() {
        demoMode = UserDefaults.standard.bool(forKey: "demoMode")
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    /// Idempotent — safe to call from `.task` on every appearance.
    func start() async {
        guard !didStart else {
            await refreshEntitlements()
            return
        }
        didStart = true
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        errorMessage = nil
        do {
            let real = try await Product.products(for: ProductID.all)
                .sorted { $0.price < $1.price }
            if real.isEmpty {
                products = []
                errorMessage = "Subscription options are temporarily unavailable. Please try again."
            } else {
                products = real
            }
        } catch {
            products = []
            errorMessage = "Couldn't load subscription options: \(error.localizedDescription)"
        }
    }

    /// Enables the sample-data-only App Review path. This deliberately does
    /// not call StoreKit or persist a paid entitlement.
    func setDemoMode(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "demoMode")
        demoMode = enabled
        errorMessage = nil
        await refreshEntitlements()
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

    func restore() async {
        errorMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Highest active, non-revoked entitlement wins (family > single).
    func refreshEntitlements() async {
        if demoMode {
            activeTier = .family
            return
        }

        var highest: SubscriptionTier = .none
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            let tier = ProductID.tier(for: transaction.productID)
            if tier > highest { highest = tier }
        }
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
