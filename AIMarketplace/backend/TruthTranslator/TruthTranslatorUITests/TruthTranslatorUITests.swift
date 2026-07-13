import XCTest

final class TruthTranslatorUITests: XCTestCase {
    func testDecodeFlowShowsResult() {
        let app = XCUIApplication()
        app.launch()

        let input = app.textViews["pasteTextInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Sorry just saw this. Crazy week. Maybe we can hang soon?")

        app.buttons["decodeButton"].tap()

        XCTAssertTrue(app.otherElements["resultPanel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The translation"].exists)
    }
}
