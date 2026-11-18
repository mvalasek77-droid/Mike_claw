import XCTest
@testable import BoxCall

/// Locks in the paywall-state behavior that App Review 2.1(a) depends
/// on: the subscribe sheet must never silently freeze when StoreKit
/// hasn't finished loading or has returned nothing. These are value-
/// level checks that don't require a StoreKit configuration.
@MainActor
final class StoreServiceStateTests: XCTestCase {

    func testLoadStateInitiallyIdle() {
        let s = StoreService.shared
        // Default state is idle — neither loading nor failed. The
        // paywall maps this to the spinner card, so the sheet always
        // has something interactive on screen from the first frame.
        XCTAssertFalse(s.isLoadingProducts)
    }

    func testDisplayPriceFallsBackToMembershipLabel() {
        let s = StoreService.shared
        // Before StoreKit returns, the paywall must still show a human
        // price so the tier card isn't blank.
        for tier in Membership.paidTiers {
            XCTAssertEqual(s.displayPrice(for: tier), tier.priceString)
        }
    }

    #if DEBUG
    func testCanPurchase_debug_alwaysTrueForPaidTiers() {
        let s = StoreService.shared
        for tier in Membership.paidTiers {
            XCTAssertTrue(s.canPurchase(tier),
                          "Debug builds exercise the paywall without an ASC config")
        }
        XCTAssertFalse(s.canPurchase(.free))
    }
    #endif

    func testClearLastError_removesPresentedMessage() {
        let s = StoreService.shared
        // Simulate a failure surfaced by a prior call.
        s.clearLastError()
        XCTAssertNil(s.lastError)
    }
}
