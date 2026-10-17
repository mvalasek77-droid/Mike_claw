import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let fullRosterProductID = "com.alphaeliteholdings.watchfighter.fullroster"

    @Published private(set) var fullRosterProduct: Product?
    @Published private(set) var ownsFullRoster = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var message: String?

    private var updatesTask: Task<Void, Never>?
    private var storeTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
        storeTask?.cancel()
    }

    func startPurchase() {
        guard storeTask == nil else { return }
        if fullRosterProduct == nil {
            storeTask = Task { [weak self] in
                await self?.loadProduct()
                self?.storeTask = nil
            }
            return
        }
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
        await loadProduct()
        await refreshEntitlements()
        listenForUpdates()
    }

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }

        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double(1 << attempt)))
            }
            do {
                let products = try await Product.products(for: [Self.fullRosterProductID])
                if let product = products.first {
                    fullRosterProduct = product
                    message = nil
                    return
                }
            } catch {
                continue
            }
        }
        if fullRosterProduct == nil {
            message = "TAP TO RETRY"
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
