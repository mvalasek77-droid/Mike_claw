import Foundation
import StoreKit

enum BillingPlan: String, CaseIterable, Identifiable, Codable {
    case free
    case pro
    case studio

    var id: String { rawValue }

    var productID: String? {
        switch self {
        case .free: nil
        case .pro: "com.codegenie.pro.monthly"
        case .studio: "com.codegenie.studio.monthly"
        }
    }

    var label: String {
        switch self {
        case .free: "Free"
        case .pro: "Pro"
        case .studio: "Studio"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .free: "$0"
        case .pro: "$9.99 / month"
        case .studio: "$29 / month"
        }
    }

    var summary: String {
        switch self {
        case .free: "3 hosted builds each month"
        case .pro: "Hosted Sonnet builds plus 20 Opus runs"
        case .studio: "Team seats, GitHub sync, and TestFlight priority"
        }
    }

    var features: [String] {
        switch self {
        case .free:
            ["3 hosted builds monthly", "Sample builds stay free", "Upgrade only when you need more"]
        case .pro:
            ["Unlimited hosted Sonnet builds", "20 Opus builds monthly", "Priority release checks"]
        case .studio:
            ["Everything in Pro", "Team-ready GitHub/TestFlight workflow", "Priority queue"]
        }
    }
}

@MainActor
final class BillingStore: ObservableObject {
    static let shared = BillingStore()

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInFlight: BillingPlan?
    @Published private(set) var lastMessage: String?
    @Published private(set) var freeBuildsUsed = 0

    private let freeBuildAllowance = 3
    private var updatesTask: Task<Void, Never>?

    private init() {
        refreshFreeBuildUsage()
        updatesTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    var activePlan: BillingPlan {
        if let studioID = BillingPlan.studio.productID,
           purchasedProductIDs.contains(studioID) {
            return .studio
        }
        if let proID = BillingPlan.pro.productID,
           purchasedProductIDs.contains(proID) {
            return .pro
        }
        return .free
    }

    var freeBuildsRemaining: Int {
        max(0, freeBuildAllowance - freeBuildsUsed)
    }

    var canStartHostedBuild: Bool {
        activePlan != .free || freeBuildsRemaining > 0
    }

    var hostedStatusText: String {
        switch activePlan {
        case .free:
            "\(freeBuildsRemaining) of \(freeBuildAllowance) free hosted builds left this month"
        case .pro:
            "Pro active"
        case .studio:
            "Studio active"
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        refreshFreeBuildUsage()
        await refreshProducts()
        await refreshEntitlements()
    }

    func displayPrice(for plan: BillingPlan) -> String {
        guard let productID = plan.productID,
              let product = products[productID] else {
            return plan.fallbackPrice
        }
        return "\(product.displayPrice) / month"
    }

    func isActive(_ plan: BillingPlan) -> Bool {
        plan == activePlan
    }

    func canPurchase(_ plan: BillingPlan) -> Bool {
        guard let productID = plan.productID else { return false }
        return products[productID] != nil && !isActive(plan)
    }

    func purchase(_ plan: BillingPlan) async {
        guard let productID = plan.productID,
              let product = products[productID] else {
            lastMessage = "This plan is not configured in App Store Connect yet."
            return
        }
        purchaseInFlight = plan
        defer { purchaseInFlight = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard let transaction = verified(verification) else {
                    lastMessage = "Purchase could not be verified."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                lastMessage = "\(plan.label) is active."
            case .pending:
                lastMessage = "Purchase is pending approval."
            case .userCancelled:
                lastMessage = "Purchase cancelled."
            @unknown default:
                lastMessage = "Purchase did not complete."
            }
        } catch {
            lastMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastMessage = purchasedProductIDs.isEmpty
                ? "No active CodeGenie subscription found."
                : "Purchases restored."
        } catch {
            lastMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func recordHostedBuildStarted() {
        refreshFreeBuildUsage()
        guard activePlan == .free else { return }
        freeBuildsUsed += 1
        UserDefaults.standard.set(freeBuildsUsed, forKey: freeBuildsKey)
    }

    private func refreshProducts() async {
        do {
            let ids = BillingPlan.allCases.compactMap(\.productID)
            let loaded = try await Product.products(for: ids)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            if loaded.isEmpty {
                lastMessage = "StoreKit products are not loaded. Free builds still work; paid plans need App Store Connect products."
            }
        } catch {
            lastMessage = "Could not load StoreKit products: \(error.localizedDescription)"
        }
    }

    private func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = verified(result),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate,
               expiration < Date() { continue }
            active.insert(transaction.productID)
        }
        purchasedProductIDs = active
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = verified(result) else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .verified(let safe): safe
        case .unverified: nil
        }
    }

    private func refreshFreeBuildUsage() {
        freeBuildsUsed = UserDefaults.standard.integer(forKey: freeBuildsKey)
    }

    private var freeBuildsKey: String {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "billing.freeBuilds.%04d-%02d", year, month)
    }
}
