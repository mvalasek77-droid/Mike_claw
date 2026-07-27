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

    /// The Gavel ladder must stay reachable: the largest pack has to cover the
    /// most expensive *Gavel-priced* archetype. (The top four tiers are real
    /// StoreKit purchases, deliberately outside the Gavel economy — no pack
    /// stack could honestly reach $9,999.)
    func testLargestPackCoversTopGavelTier() {
        let largest = StoreKitService.gavelCatalog.map(\.gavels).max() ?? 0
        let topGavelTier = Archetype.allCases.compactMap(\.gavelPrice).max() ?? 0
        XCTAssertGreaterThanOrEqual(largest, topGavelTier,
                                    "a single top pack should afford the top Gavel tier")
        XCTAssertNil(Archetype.trillionaire.gavelPrice,
                     "Trillionaire is a real-money purchase, not a Gavel one")
    }

    func testBoostProductIsDistinctFromGavels() {
        XCTAssertFalse(StoreKitService.gavelIDs.contains(StoreKitService.boostProductID))
        XCTAssertEqual(StoreKitService.gavels(for: StoreKitService.boostProductID), 0,
                       "the Boost grants time, not Gavels")
        XCTAssertGreaterThan(StoreKitService.boostMinutes, 0)
    }

    @MainActor
    func testActivateBoostMakesItLive() {
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v5")
        let store = AuctionStore()
        store.resetAccount()
        XCTAssertFalse(store.isBoosted)
        store.activateBoost()
        XCTAssertTrue(store.isBoosted)
        XCTAssertNotNil(store.boostUntil)
    }

    func testPaywallTriggersSuggestTheCheapestSolvingTier() {
        XCTAssertEqual(PaywallTrigger.rankReveal.suggestedTier, .paddle)
        XCTAssertEqual(PaywallTrigger.bidLimit.suggestedTier, .paddle)
        XCTAssertEqual(PaywallTrigger.filters.suggestedTier, .reserve)
        XCTAssertEqual(PaywallTrigger.readReceipts.suggestedTier, .blackcard)
        // Every trigger has a non-empty hook line + icon.
        for t: PaywallTrigger in [.rankReveal, .bidLimit, .filters, .readReceipts, .general] {
            XCTAssertFalse(t.headline.isEmpty)
            XCTAssertFalse(t.icon.isEmpty)
        }
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
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v5")
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
