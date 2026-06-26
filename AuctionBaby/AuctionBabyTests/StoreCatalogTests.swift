import XCTest
@testable import AuctionBaby

/// Catalog-level checks for the StoreKit layer. These assert the product
/// definitions are internally consistent (IDs, Gavel grants, subscription
/// tiers) without needing a live `SKTestSession`.
final class StoreCatalogTests: XCTestCase {

    func testGavelPacksAscendByValue() {
        let gavels = StoreKitService.gavelCatalog.map(\.gavels)
        XCTAssertEqual(gavels, gavels.sorted(), "packs should ascend in Gavel amount")
        XCTAssertEqual(Set(StoreKitService.gavelIDs).count, StoreKitService.gavelIDs.count, "product IDs unique")
    }

    func testGavelLookupMatchesCatalog() {
        for pack in StoreKitService.gavelCatalog {
            XCTAssertEqual(StoreKitService.gavels(for: pack.id), pack.gavels)
        }
        XCTAssertEqual(StoreKitService.gavels(for: "com.valasek.auctionbaby.unknown"), 0)
    }

    /// The whole point: the top status tier must be reachable. The largest pack
    /// has to cover the most expensive archetype.
    func testLargestPackCoversTrillionaire() {
        let largest = StoreKitService.gavelCatalog.map(\.gavels).max() ?? 0
        XCTAssertGreaterThanOrEqual(largest, Archetype.trillionaire.price,
                                    "a single top pack should afford the Trillionaire tier")
    }

    func testBoostProductIsDistinctFromGavels() {
        XCTAssertFalse(StoreKitService.gavelIDs.contains(StoreKitService.boostProductID))
        XCTAssertEqual(StoreKitService.gavels(for: StoreKitService.boostProductID), 0,
                       "the Boost grants time, not Gavels")
        XCTAssertGreaterThan(StoreKitService.boostMinutes, 0)
    }

    @MainActor
    func testActivateBoostMakesItLive() {
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v4")
        let store = AuctionStore()
        store.resetAccount()
        XCTAssertFalse(store.isBoosted)
        store.activateBoost()
        XCTAssertTrue(store.isBoosted)
        XCTAssertNotNil(store.boostUntil)
    }

    func testSubscriptionTiersAreDistinctAndComplete() {
        let tiers = StoreKitService.PassTier.allCases
        XCTAssertEqual(tiers.count, 3)
        let ids = tiers.map(\.productID)
        XCTAssertEqual(Set(ids).count, ids.count, "subscription IDs unique")
        XCTAssertEqual(StoreKitService.subscriptionIDs, ids)
        for tier in tiers { XCTAssertFalse(tier.perks.isEmpty, "\(tier.title) needs perks") }
    }

    @MainActor
    func testCreditAndRevokeMoveTheWallet() {
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v4")
        let store = AuctionStore()
        store.resetAccount()
        let start = store.wallet
        store.creditGavels(5_000)
        XCTAssertEqual(store.wallet, start + 5_000)
        store.revokeGavels(2_000)
        XCTAssertEqual(store.wallet, start + 3_000)
        // Clawback floors at zero, never negative.
        store.revokeGavels(1_000_000)
        XCTAssertEqual(store.wallet, 0)
    }
}
