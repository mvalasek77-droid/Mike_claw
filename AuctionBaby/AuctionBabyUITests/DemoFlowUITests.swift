import XCTest

/// Headless UI automation for the Demo-Mode happy path — the flows that need
/// no Apple ID, no network, and no system sheets (so they run deterministically
/// on device via `xcodebuild test`).
///
/// Covered: launch → onboarding as a bidder (name "demo" → Demo Mode) → the
/// Floor renders → place a bid → it appears in My Bids.
///
/// NOT covered here (and can't be, by design): Sign in with Apple, real
/// StoreKit purchases, and the push-tap deep-links — those are system UI that
/// no automation can drive. Verify those manually per QA_CHECKLIST.md.
///
/// Determinism: every launch passes `-uiTestReset`, which (DEBUG only) wipes
/// any persisted account so we always start at onboarding. See AuctionBabyApp.
final class DemoFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestReset"]
        app.launch()
        return app
    }

    /// Tap an element, scrolling the frontmost scroll view up a few times if
    /// it's present but off-screen (bid sheet + onboarding form are scrollable).
    private func tapWhenReady(_ element: XCUIElement, in app: XCUIApplication,
                              timeout: TimeInterval = 10, file: StaticString = #filePath,
                              line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "element never appeared: \(element)", file: file, line: line)
        var tries = 0
        while !element.isHittable && tries < 5 {
            app.swipeUp()
            tries += 1
        }
        element.tap()
    }

    /// Complete Demo-Mode onboarding as a bidder and land on the Floor.
    private func onboardAsBidder(_ app: XCUIApplication) {
        // Role picker appears after the ~1.9s splash.
        tapWhenReady(app.buttons["role_bidder"], in: app, timeout: 20)

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 8), "name field should appear")
        name.tap()
        name.typeText("demo")            // "demo" → Demo Mode (on-device sim)

        // Submit — PrimaryButton's label is its title.
        tapWhenReady(app.buttons["Step onto the floor"], in: app)

        // The Lot-of-the-Day intro fires on the first Floor open after a reset.
        let browse = app.buttons["Browse the floor instead"]
        if browse.waitForExistence(timeout: 5) { browse.tap() }
    }

    // MARK: - Tests

    /// Launch → onboard → the Floor renders tappable lots.
    func testOnboardingReachesFloor() {
        let app = launchFresh()
        onboardAsBidder(app)
        XCTAssertTrue(app.buttons["floor_bid"].firstMatch.waitForExistence(timeout: 12),
                      "the Floor should render lots with Bid buttons")
    }

    /// Placing a bid populates My Bids. Tolerant of whether the first lot is a
    /// Copycat: a real lot lands under "Live bids", a Copycat bid is revealed +
    /// declined and lands under "Settled" — either proves the bid was recorded.
    func testPlaceBidLandsInMyBids() {
        let app = launchFresh()
        onboardAsBidder(app)

        tapWhenReady(app.buttons["floor_bid"].firstMatch, in: app, timeout: 12)
        // A Floor card is also a NavigationLink. On some iOS releases the
        // outer link wins the nested Bid-button tap, so continue from the
        // profile's equivalent Bid CTA when that happens.
        let placeBid = app.buttons["bidsheet_place"]
        let detailBid = app.buttons["detail_bid"]
        if detailBid.waitForExistence(timeout: 5) {
            tapWhenReady(detailBid, in: app)
        }
        tapWhenReady(placeBid, in: app)

        let myBids = app.tabBars.buttons["My Bids"]
        XCTAssertTrue(myBids.waitForExistence(timeout: 6), "My Bids tab should exist for a bidder")
        if !myBids.isHittable {
            let backToFloor = app.navigationBars.buttons["The Floor"]
            XCTAssertTrue(backToFloor.waitForExistence(timeout: 5),
                          "profile detail should provide a route back to the Floor")
            backToFloor.tap()
        }
        XCTAssertTrue(myBids.isHittable, "My Bids tab should be tappable from the Floor")
        myBids.tap()

        let live = app.staticTexts["Live bids"]
        let settled = app.staticTexts["Settled"]
        XCTAssertTrue(live.waitForExistence(timeout: 8) || settled.exists,
                      "a placed bid should appear under Live bids (real lot) or Settled (copycat)")
    }
}
