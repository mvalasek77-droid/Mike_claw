import StoreKitTest
import XCTest

final class RobloxGuardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppReviewDemoRoute() throws {
        let app = XCUIApplication()
        app.launch()
        completeOnboardingIfNeeded(in: app)

        app.buttons["Settings"].tap()
        if app.buttons["Exit Demo Mode"].waitForExistence(timeout: 2) {
            app.buttons["Exit Demo Mode"].tap()
            XCTAssertTrue(
                app.buttons["Subscribe"].waitForExistence(timeout: 5),
                "Demo mode did not finish turning off"
            )
        }

        let demoToggle = app.switches["App Review Demo"]
        for _ in 0..<4 where !demoToggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(
            demoToggle.waitForExistence(timeout: 5) && demoToggle.isHittable,
            "App Review Demo toggle was not reachable: \(app.debugDescription)"
        )
        demoToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(
            for: NSPredicate(format: "value == %@", "1"),
            evaluatedWith: demoToggle
        )
        waitForExpectations(timeout: 5)
        app.buttons["Home"].tap()

        XCTAssertTrue(app.staticTexts["builderman"].waitForExistence(timeout: 8))
        let elevatedAlert = app.buttons[
            "Talk soon alert: New friend's bio contains gaming-adjacent contact handle"
        ]
        XCTAssertTrue(elevatedAlert.exists)
        keepScreenshot(named: "App Review Demo Dashboard", from: app)

        elevatedAlert.tap()
        XCTAssertTrue(app.staticTexts["What we observed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What you can do"].exists)
        keepScreenshot(named: "App Review Demo Alert", from: app)

        app.buttons["Get Help"].tap()
        XCTAssertTrue(app.staticTexts["Roblox 101"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Know the Dangers"].exists)
        keepScreenshot(named: "Parent Safety Resources", from: app)
    }

    func testCapturePaywallForAppStore() throws {
        let session = try SKTestSession(configurationFileNamed: "RobloxGuard")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let app = XCUIApplication()
        app.launch()
        completeOnboardingIfNeeded(in: app)

        app.buttons["Settings"].tap()
        if app.buttons["Exit Demo Mode"].waitForExistence(timeout: 2) {
            app.buttons["Exit Demo Mode"].tap()
            XCTAssertTrue(
                app.buttons["Subscribe"].waitForExistence(timeout: 5),
                "Demo mode did not finish turning off"
            )
        }
        let subscribe = app.buttons["Subscribe"]
        XCTAssertTrue(subscribe.waitForExistence(timeout: 5))
        subscribe.tap()

        let title = app.staticTexts["Choose your plan"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Paywall not loaded: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Single Child"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Family"].exists)
        keepScreenshot(named: "Subscription Paywall", from: app)
    }

    private func completeOnboardingIfNeeded(in app: XCUIApplication) {
        let parentToggle = app.switches["toggleParent"]
        guard parentToggle.waitForExistence(timeout: 3) else { return }

        for identifier in [
            "toggleParent",
            "toggleScope",
            "toggleData",
            "toggleLimits",
        ] {
            app.switches[identifier].tap()
        }
        let agree = app.buttons["buttonAgreeContinue"]
        XCTAssertTrue(agree.isEnabled)
        agree.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 8))
    }

    private func keepScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
