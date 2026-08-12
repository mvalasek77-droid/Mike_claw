import XCTest
import StoreKit
import StoreKitTest
@testable import AuctionBaby

/// Full StoreKit transaction tests using SKTestSession (StoreKit Testing).
/// These exercise the real purchase → grant → entitlement → refund flow
/// against the bundled Products.storekit configuration file.
///
/// Requires the scheme's test action to have `Products.storekit` attached
/// (already configured in project.yml).
@MainActor
final class StoreKitTransactionTests: XCTestCase {

    private var session: SKTestSession!
    private var storeKit: StoreKitService!
    private var store: AuctionStore!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v5")
        session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        storeKit = StoreKitService()
        storeKit.resetForTesting()
        storeKit.suspendListenerForTesting = true
        store = AuctionStore()
        store.resetAccount()
        // Wire hooks like the app root does
        storeKit.onCredit = { [weak store] gavels in store?.creditGavels(gavels) }
        storeKit.onRevoke = { [weak store] gavels, txID in
            store?.revokeGavels(gavels, txID: txID)
        }
        storeKit.onBoost = { [weak store] in store?.activateBoost() }
        storeKit.onStatusPurchased = { [weak store] tier in store?.equipArchetype(tier) }
        await storeKit.loadProducts()
    }

    override func tearDown() async throws {
        storeKit.suspendListenerForTesting = false
        storeKit.resetForTesting()
        try await super.tearDown()
    }

    // MARK: Product loading

    func testAll16ProductsLoadFromStoreKitConfig() async {
        let total = storeKit.gavelPacks.count + (storeKit.boostProduct != nil ? 1 : 0)
                   + storeKit.statusProducts.count + storeKit.subscriptions.count
        XCTAssertEqual(total, 16, "all 16 products should load from the .storekit config")
    }

    func testGavelPacksHaveCorrectAmounts() async {
        let amounts = storeKit.gavelPacks.compactMap { StoreKitService.gavels(for: $0.id) }
        XCTAssertEqual(amounts.sorted(), [1_000, 5_000, 14_000, 30_000])
    }

    func testSubscriptionsLoadInPriceOrder() async {
        XCTAssertEqual(storeKit.subscriptions.count, 3)
        XCTAssertEqual(storeKit.subscriptions.first?.id, "com.valasek.auctionbaby.sub.paddle")
        XCTAssertEqual(storeKit.subscriptions.last?.id, "com.valasek.auctionbaby.sub.blackcard")
    }

    // MARK: Gavel purchase

    func testBuyGavelHandfulCreditsWallet() async {
        let startWallet = store.wallet
        let product = storeKit.gavelPacks.first { $0.id == "com.valasek.auctionbaby.gavels.handful" }
        XCTAssertNotNil(product)
        let outcome = await storeKit.purchase(product!, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(store.wallet, startWallet + 1_000)
    }

    func testBuyGavelVaultCreditsWallet() async {
        let startWallet = store.wallet
        let product = storeKit.gavelPacks.first { $0.id == "com.valasek.auctionbaby.gavels.vault" }
        XCTAssertNotNil(product)
        let outcome = await storeKit.purchase(product!, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(store.wallet, startWallet + 30_000)
    }

    func testDoublePurchaseCreditsTwice() async {
        let product = storeKit.gavelPacks.first { $0.id == "com.valasek.auctionbaby.gavels.handful" }!
        let outcome1 = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome1, .success)
        let walletAfterFirst = store.wallet
        let outcome2 = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome2, .success)
        XCTAssertEqual(store.wallet, walletAfterFirst + 1_000)
    }

    // MARK: Spotlight Boost

    func testBuySpotlightBoostActivatesBoost() async {
        XCTAssertFalse(store.isBoosted)
        let product = storeKit.boostProduct
        XCTAssertNotNil(product)
        let outcome = await storeKit.purchase(product!, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(store.isBoosted)
        XCTAssertNotNil(store.boostUntil)
    }

    // MARK: Subscription

    func testBuyPaddleSubscriptionGrantsEntitlement() async {
        XCTAssertFalse(storeKit.hasPass)
        let product = storeKit.subscriptions.first { $0.id == "com.valasek.auctionbaby.sub.paddle" }
        XCTAssertNotNil(product)
        let outcome = await storeKit.purchase(product!, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(storeKit.isSubscribed(to: .paddle))
        XCTAssertTrue(storeKit.hasPass)
        XCTAssertEqual(storeKit.activeTier, .paddle)
    }

    func testBuyBlackCardIsHighestTier() async {
        let product = storeKit.subscriptions.first { $0.id == "com.valasek.auctionbaby.sub.blackcard" }!
        _ = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        XCTAssertTrue(storeKit.isSubscribed(to: .blackcard))
        XCTAssertEqual(storeKit.activeTier, .blackcard)
    }

    // MARK: Status archetype (non-consumable)

    func testBuyGoodGuyStatusEquipsBadge() async {
        let product = storeKit.statusProducts.first { $0.id == "com.valasek.auctionbaby.status.goodguy" }
        XCTAssertNotNil(product)
        let outcome = await storeKit.purchase(product!, appAccountToken: store.appAccountToken)
        XCTAssertEqual(outcome, .success)
        XCTAssertTrue(storeKit.owns(.goodGuy))
    }

    // MARK: Refund clawback

    func testRefundGavelPackClawsBackWallet() async throws {
        let product = storeKit.gavelPacks.first { $0.id == "com.valasek.auctionbaby.gavels.stack" }!
        _ = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        let walletAfterPurchase = store.wallet
        // Simulate a refund via the test helper (same path as a real revocation)
        storeKit.simulateRefundForTesting(productID: "com.valasek.auctionbaby.gavels.stack")
        let expected = max(0, walletAfterPurchase - 5_000)
        XCTAssertEqual(store.wallet, expected)
    }

    // MARK: Interrupted purchase

    func testInterruptedPurchaseDoesNotCredit() async {
        let startWallet = store.wallet
        let product = storeKit.gavelPacks.first!
        session.interruptedPurchasesEnabled = true
        let outcome = await storeKit.purchase(product, appAccountToken: store.appAccountToken)
        session.interruptedPurchasesEnabled = false
        // Interrupted purchases return .pending, not .success
        XCTAssertEqual(outcome, .pending)
        // Wallet should not have changed
        XCTAssertEqual(store.wallet, startWallet)
    }

    // MARK: Restore

    func testRestoreRegrantsEntitlements() async throws {
        // Buy a subscription
        let subProduct = storeKit.subscriptions.first { $0.id == "com.valasek.auctionbaby.sub.paddle" }!
        _ = await storeKit.purchase(subProduct, appAccountToken: store.appAccountToken)
        XCTAssertTrue(storeKit.isSubscribed(to: .paddle))
        // Clear entitlements (simulate fresh launch losing in-memory state)
        storeKit.resetForTesting()
        XCTAssertFalse(storeKit.isSubscribed(to: .paddle))
        // Restore
        await storeKit.restore()
        XCTAssertTrue(storeKit.isSubscribed(to: .paddle))
    }
}