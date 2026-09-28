import XCTest

/// End-to-end iPhone journeys. Each test launches the app with
/// `-uiTesting` (see UITestSupport) so it starts from a known state.
final class BoxCallUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - First launch

    func testFirstLaunch_ageGateAndFullTour_landOnTheTabs() {
        let app = launch("-resetState")

        let year = app.textFields["ageGate.year"]
        XCTAssertTrue(year.waitForExistence(timeout: 15))
        year.tap()
        year.typeText("1990")
        app.buttons["ageGate.confirm"].tap()

        let next = app.buttons["tour.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<7 { next.tap() }
        XCTAssertEqual(next.label, "Start trading", "The tour should be 8 pages long")
        next.tap()

        XCTAssertTrue(app.tabBars.buttons["Now Showing"].waitForExistence(timeout: 5))
    }

    func testAgeGate_blocksUnder13() {
        let app = launch("-resetState")
        let year = app.textFields["ageGate.year"]
        XCTAssertTrue(year.waitForExistence(timeout: 15))
        year.tap()
        let thisYear = Calendar.current.component(.year, from: Date())
        year.typeText("\(thisYear - 10)")
        app.buttons["ageGate.confirm"].tap()

        XCTAssertTrue(app.staticTexts["You must be at least 13 to use BoxCall."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["tour.next"].exists)
    }

    // MARK: - Trading

    func testBuyingACall_showsInPositions_andSurvivesARelaunch() {
        var app = launch("-resetState", "-skipIntro")
        buyFirstTradableContract(in: app)

        app.tabBars.buttons["Positions"].tap()
        XCTAssertTrue(positionRows(in: app).firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app = launch("-skipIntro")
        app.tabBars.buttons["Positions"].tap()
        XCTAssertTrue(positionRows(in: app).firstMatch.waitForExistence(timeout: 10),
                      "Positions must be saved across a force-quit")
    }

    // MARK: - Leaderboard + spotlight

    func testLeaderboard_ranksByProfit_andHomeSpotlightExplainsIt() {
        let app = launch("-resetState", "-skipIntro")

        app.tabBars.buttons["Box Office"].tap()
        XCTAssertTrue(anyText(in: app, containing: "total profit").waitForExistence(timeout: 5))

        app.tabBars.buttons["Marquee"].tap()
        let spotlight = anyText(in: app, containing: "five most profitable traders")
        XCTAssertTrue(scrollUntilVisible(spotlight, in: app))
    }

    // MARK: - Account deletion (App Review 5.1.1(v))

    func testDeleteAccount_wipesDataAndReturnsToTheAgeGate() {
        let app = launch("-resetState", "-skipIntro")
        buyFirstTradableContract(in: app)

        app.tabBars.buttons["Profile"].tap()
        let delete = app.buttons["account.delete"]
        XCTAssertTrue(scrollUntilVisible(delete, in: app))
        delete.tap()
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(app.textFields["ageGate.year"].waitForExistence(timeout: 5))
    }

    // MARK: - Performance

    func testLaunchPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            self.launch("-skipIntro")
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    private func positionRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "position.row")
    }

    private func anyText(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    @discardableResult
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication,
                                    maxSwipes: Int = 10) -> Bool {
        if element.waitForExistence(timeout: 3), element.isHittable { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if element.exists, element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    /// Opens movies from the top of Now Showing until one is still trading,
    /// then buys one contract. Movies that already opened show no chain.
    private func buyFirstTradableContract(in app: XCUIApplication) {
        app.tabBars.buttons["Now Showing"].tap()
        let movies = app.descendants(matching: .any).matching(identifier: "movie.row")
        XCTAssertTrue(movies.firstMatch.waitForExistence(timeout: 20), "The catalog never loaded")

        for index in 0..<min(movies.count, 8) {
            movies.element(boundBy: index).tap()
            let row = app.buttons.matching(identifier: "chain.row").firstMatch
            if scrollUntilVisible(row, in: app, maxSwipes: 6) {
                row.tap()

                // The first Call opens a one-time explainer over the trade sheet.
                let gotIt = app.buttons["tutorial.gotIt"]
                if gotIt.waitForExistence(timeout: 5) {
                    scrollUntilVisible(gotIt, in: app)
                    gotIt.tap()
                    XCTAssertTrue(gotIt.waitForNonExistence(timeout: 5))
                }

                // The order button sits at the bottom of a lazily built Form,
                // so it only exists once scrolled into view.
                let submit = app.buttons["trade.submit"]
                XCTAssertTrue(scrollUntilVisible(submit, in: app, maxSwipes: 15),
                              "Couldn't reach the Buy button on the trade sheet")
                submit.tap()
                XCTAssertFalse(submit.waitForExistence(timeout: 2), "The trade sheet should close after buying")
                return
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTFail("No movie in the first 8 was still trading")
    }
}
