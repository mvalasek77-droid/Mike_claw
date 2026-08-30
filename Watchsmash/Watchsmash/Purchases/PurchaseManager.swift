import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let fullRosterProductID = "com.valasek.watchsmash.fullroster"

    @Published private(set) var fullRosterProduct: Product?
    @Published private(set) var ownsFullRoster = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?
    /// Owns the in-flight purchase/restore so a view teardown mid-flow can't
    /// orphan it and a double tap can't start a second one.
    private var storeTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
        storeTask?.cancel()
    }

    /// Fire-and-forget entry points for SwiftUI buttons. The work is owned here,
    /// not by the view, so it survives a redraw and is cancelled on teardown.
    func startPurchase() {
        guard storeTask == nil else { return }
        storeTask = Task { [weak self] in
            await self?.purchaseFullRoster()
            self?.storeTask = nil
        }
    }

    func startRestore() {
        guard storeTask == nil else { return }
        storeTask = Task { [weak self] in
            await self?.restore()
            self?.storeTask = nil
        }
    }

    func prepare() async {
        do {
            fullRosterProduct = try await Product.products(for: [Self.fullRosterProductID]).first
            await refreshEntitlements()
        } catch {
            message = "STORE UNAVAILABLE"
        }
        listenForUpdates()
    }

    func purchaseFullRoster() async {
        guard let fullRosterProduct, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            switch try await fullRosterProduct.purchase() {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                message = "PURCHASE PENDING"
            case .userCancelled:
                break
            @unknown default:
                message = "TRY AGAIN"
            }
        } catch {
            message = "PURCHASE FAILED"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = ownsFullRoster ? "ROSTER RESTORED" : "NO PURCHASE FOUND"
        } catch {
            message = "RESTORE FAILED"
        }
    }

    private func listenForUpdates() {
        updatesTask?.cancel()
        updatesTask = Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.verified(result) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func refreshEntitlements() async {
        var owns = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if transaction.productID == Self.fullRosterProductID,
               transaction.revocationDate == nil {
                owns = true
            }
        }
        ownsFullRoster = owns
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw PurchaseError.failedVerification
        }
    }

    private enum PurchaseError: Error {
        case failedVerification
    }
}
