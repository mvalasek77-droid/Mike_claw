import StoreKit

/// Product identifiers for Screenshot Studio Pro. These must match the products
/// configured in App Store Connect (and the bundled `.storekit` file used for
/// local testing).
enum ProductID {
    static let monthly = "com.screenshotstudio.pro.monthly"
    static let annual = "com.screenshotstudio.pro.annual"
    static let lifetime = "com.screenshotstudio.pro.lifetime"
    static let all: [String] = [monthly, annual, lifetime]
}

/// Free-tier limits. The output is public App Store screenshots, so we never
/// watermark — the free tier is gated on scope (sizes, languages, count) and
/// the pro-grade embellishments instead.
enum FreeTier {
    static let maxScreenshots = 3
}

/// A Pro-gated capability, used to give the paywall context about what the user
/// just reached for.
enum ProFeature: Identifiable {
    case moreScreenshots, additionalSizes, localization, overlays, photoBackdrop, videoFrames

    var id: String { title }

    var title: String {
        switch self {
        case .moreScreenshots: return "More screenshots"
        case .additionalSizes: return "Every device size"
        case .localization: return "Localized caption sets"
        case .overlays: return "Text & sticker overlays"
        case .photoBackdrop: return "Photo backdrops"
        case .videoFrames: return "App Preview video frames"
        }
    }

    var blurb: String {
        switch self {
        case .moreScreenshots: return "Add up to ten screenshots per set."
        case .additionalSizes: return "Export every required iPhone and iPad size at once."
        case .localization: return "Manage a caption set for every App Store language."
        case .overlays: return "Drop annotations, badges and stickers anywhere."
        case .photoBackdrop: return "Use any photo as your backdrop."
        case .videoFrames: return "Pull stills from an App Preview video."
        }
    }
}

/// Source of truth for purchases and the Pro entitlement, backed by StoreKit 2.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published var isPurchasing = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.all)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            BugLog.error("Store", "Couldn't load products: \(error.localizedDescription)")
        }
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    BugLog.info("Store", "Purchased \(product.id).")
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            BugLog.error("Store", "Purchase failed: \(error.localizedDescription)")
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            BugLog.warning("Store", "Restore/sync failed: \(error.localizedDescription)")
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        if entitled {
            isPro = true
        } else if UserDefaults.standard.bool(forKey: "developerBypass") {
            isPro = true
        }
    }

    /// Developer-only bypass: unlocks Pro without a StoreKit purchase.
    /// Gated to builds signed by team UDM4W27W9V — the caller (SettingsView)
    /// checks the provisioning profile before calling this.
    func activateAdminBypass() async {
        UserDefaults.standard.set(true, forKey: "developerBypass")
        BugLog.info("Store", "Developer bypass activated.")
        isPro = true
    }

    /// Disable the developer bypass (tap the version label 5× again).
    func disableAdminBypass() {
        UserDefaults.standard.removeObject(forKey: "developerBypass")
        BugLog.info("Store", "Developer bypass disabled.")
        Task { await refreshEntitlements() }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }
}
