import XCTest

class CodeGenieTestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
    }

    // MARK: - Launch helpers

    func launchFreshInstall() {
        app.launchArguments += ["-resetDefaults"]
        app.launch()
    }

    func launchOnboarded() {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true",
            "-hasAcceptedTerms", "true",
            "-hasChosenPricing", "true"
        ]
        app.launch()
    }

    func launchAfterOnboarding() {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true"
        ]
        app.launch()
    }

    func launchAfterTerms() {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true",
            "-hasAcceptedTerms", "true"
        ]
        app.launch()
    }

    // MARK: - Wait helpers

    @discardableResult
    func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    func waitAndTap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(waitFor(element, timeout: timeout),
                      "Element \(element) did not appear within \(timeout)s")
        element.tap()
    }

    func assertExists(_ element: XCUIElement, _ message: String = "") {
        XCTAssertTrue(waitFor(element, timeout: 3), message.isEmpty ? "\(element) should exist" : message)
    }

    func assertNotExists(_ element: XCUIElement, _ message: String = "") {
        XCTAssertFalse(element.exists, message.isEmpty ? "\(element) should not exist" : message)
    }

    // MARK: - Tab navigation

    func selectTab(_ label: String) {
        waitAndTap(app.buttons[label])
    }

    // MARK: - Scroll helpers

    func scrollDown(in element: XCUIElement? = nil, times: Int = 1) {
        let target = element ?? app
        for _ in 0..<times {
            target.swipeUp()
        }
    }

    func scrollUp(in element: XCUIElement? = nil, times: Int = 1) {
        let target = element ?? app
        for _ in 0..<times {
            target.swipeDown()
        }
    }

    func dismissSheet() {
        let topCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let botCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        topCoord.press(forDuration: 0.1, thenDragTo: botCoord)
    }

    // MARK: - Screenshot

    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
