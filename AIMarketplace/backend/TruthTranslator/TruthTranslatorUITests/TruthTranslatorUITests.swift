import XCTest

final class TruthTranslatorUITests: XCTestCase {
    func testLegalLinksAreAvailableInApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--chaddrop-reset-free-decodes"]
        app.launch()

        XCTAssertTrue(app.links["termsOfUseLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.links["privacyPolicyLink"].waitForExistence(timeout: 5))
    }

    func testDecodeFlowShowsResult() {
        let app = XCUIApplication()
        app.launchArguments = ["--chaddrop-reset-free-decodes"]
        app.launch()

        let input = app.textViews["pasteTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Sorry just saw this. Crazy week. Maybe we can hang soon?")

        app.buttons["decodeButton"].tap()

        XCTAssertTrue(app.otherElements["resultPanel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The calendar is always full but the schedule is always empty."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What he really means"].exists)
    }
}
