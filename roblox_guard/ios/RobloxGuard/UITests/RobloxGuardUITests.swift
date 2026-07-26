import XCTest

final class RobloxGuardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreenshotsForAppStore() throws {
        let app = XCUIApplication()
        app.launch()
        sleep(5)

        // If onboarding is shown, complete it. If already skipped (UserDefaults), move on.
        let firstSwitch = app.switches.firstMatch
        if firstSwitch.waitForExistence(timeout: 5) {
            for _ in 0..<4 {
                app.switches.firstMatch.tap()
                sleep(1)
            }
            let agree = app.buttons["buttonAgreeContinue"]
            if agree.waitForExistence(timeout: 5) { agree.tap() }
            sleep(3)
        }

        // 2. Wait for Dashboard and capture it
        let noAccounts = app.staticTexts["No accounts linked"]
        XCTAssertTrue(noAccounts.waitForExistence(timeout: 10), "Dashboard not loaded: \(app.debugDescription)")
        let dashboardAttachment = XCTAttachment(screenshot: app.screenshot())
        dashboardAttachment.name = "Dashboard Empty State"
        dashboardAttachment.lifetime = .keepAlways
        add(dashboardAttachment)

        // 3. Open the paywall
        let subscribe = app.buttons["Subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 5))
        subscribe.tap()
        sleep(3)

        // 4. Wait for paywall and capture it
        let title = app.staticTexts["Choose your plan"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Paywall not loaded: \(app.debugDescription)")
        let paywallAttachment = XCTAttachment(screenshot: app.screenshot())
        paywallAttachment.name = "Paywall"
        paywallAttachment.lifetime = .keepAlways
        add(paywallAttachment)
    }
}
