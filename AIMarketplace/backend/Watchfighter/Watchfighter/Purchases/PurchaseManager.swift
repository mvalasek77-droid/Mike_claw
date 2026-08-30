import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let fullRosterProductID = "com.valasek.watchfighter.fullroster"

    @Published private(set) var fullRosterProduct: Product?
    @Published private(set) var ownsFullRoster = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?

    func prepare() async {
        do {
            fullRosterProduct = try await Product.products(for: [Self.fullRosterProductID]).first
            await refreshEntitlements()
        } catch {
            message = "STORE UNAVAILABLE"
        }
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

    private func refreshEntitlements() async {
        var ownsFullRoster = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if transaction.productID == Self.fullRosterProductID,
               transaction.revocationDate == nil {
                ownsFullRoster = true
            }
        }
        self.ownsFullRoster = ownsFullRoster
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
