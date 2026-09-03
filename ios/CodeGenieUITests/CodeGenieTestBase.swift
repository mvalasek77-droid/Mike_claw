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

    /// Onboarded *and* able to start a build.
    ///
    /// The Describe form refuses to build until the user has a way to
    /// pay for tokens. `-auth.mode codegenie` lands in UserDefaults via
    /// the standard launch-argument domain, which is exactly where
    /// `Credentials` reads it from, so this picks the hosted-credits
    /// mode and clears the pre-flight block without seeding a fake API
    /// key. Builds then run on the local simulated builder — no
    /// backend, no tokens, no network.
    func launchReadyToBuild() {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true",
            "-hasAcceptedTerms", "true",
            "-hasChosenPricing", "true",
            "-auth.mode", "codegenie"
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

    // MARK: - Build helpers

    /// Drives the real Describe → confirm → build path and waits for
    /// the success overlay. Replaces the old canned-sample shortcut,
    /// which was removed along with the sample gallery.
    ///
    /// Requires `launchReadyToBuild()`.
    @discardableResult
    func runLocalBuildToGreen(
        name: String = "TideRider",
        prompt: String = "A tide times app for surfers with a clean Apple-style UI and haptics",
        timeout: TimeInterval = 90
    ) -> Bool {
        let cta = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start' AND label CONTAINS[c] 'build'")
        ).firstMatch
        if cta.waitForExistence(timeout: 5) {
            cta.tap()
        } else {
            selectTab("Build")
        }

        // First-run fork: offer to set shipping up first. Take the
        // "just build" branch so the build actually starts.
        let buildNow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Just build something'")
        ).firstMatch
        if buildNow.waitForExistence(timeout: 3) { buildNow.tap() }

        let nameField = app.textFields["App name"]
        guard nameField.waitForExistence(timeout: 6) else { return false }
        nameField.tap()
        nameField.typeText(name)

        let promptField = app.textViews["App description"]
        guard promptField.waitForExistence(timeout: 4) else { return false }
        promptField.tap()
        promptField.typeText(prompt)

        scrollDown(times: 3)
        let build = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build it'")
        ).firstMatch
        guard build.waitForExistence(timeout: 4) else { return false }
        build.tap()

        let confirm = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Confirm and build'")
        ).firstMatch
        guard confirm.waitForExistence(timeout: 6) else { return false }
        confirm.tap()

        return app.staticTexts["Your app is built"].waitForExistence(timeout: timeout)
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
