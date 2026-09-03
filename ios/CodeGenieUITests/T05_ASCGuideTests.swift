import XCTest

/// Apple Developer Program setup walkthrough — the four-screen primer
/// reachable from Settings that explains the $99/year enrolment, the
/// difference between App Store Connect and the Developer Portal, and
/// collects the signing credentials.
///
/// This file previously claimed to cover the App Store Connect
/// submission guide, but its helper only ever opened this screen. The
/// submission guide itself is covered end to end in
/// `T11_ASCSubmissionFlowTests`.
final class T05_AppleDevWalkthroughTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    func test01_walkthroughOpensFromSettings() {
        openAppleDevWalkthrough()
        let heading = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple Developer' OR label CONTAINS[c] 'Developer Program'")
        ).firstMatch
        assertExists(heading, "The Apple Developer walkthrough should open from Settings")
        screenshot("01-apple-dev-open")
    }

    func test02_walkthroughAnnouncesItsPosition() {
        openAppleDevWalkthrough()
        let position = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'of 4'")
        ).firstMatch
        XCTAssertTrue(position.waitForExistence(timeout: 4),
                      "Progress through the four screens should be announced for VoiceOver")
        screenshot("02-apple-dev-progress")
    }

    /// The $99/year cost is the single most surprising fact for a
    /// first-time submitter, so it must be stated up front rather than
    /// discovered on Apple's site.
    func test03_costIsDisclosedUpFront() {
        openAppleDevWalkthrough()
        let cost = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '99'")
        ).firstMatch
        XCTAssertTrue(cost.waitForExistence(timeout: 4),
                      "The annual fee should be disclosed before the user starts")
        screenshot("03-cost-disclosure")
    }

    func test04_walkthroughAdvancesThroughScreens() {
        openAppleDevWalkthrough()
        for i in 0..<3 {
            let next = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Next' OR label CONTAINS[c] 'Continue' OR label CONTAINS[c] 'I have'")
            ).firstMatch
            guard next.waitForExistence(timeout: 3) else { break }
            next.tap()
            sleep(1)
            screenshot("04-apple-dev-screen-\(i)")
        }
    }

    // MARK: - Helpers

    private func openAppleDevWalkthrough() {
        selectTab("Settings")
        sleep(1)
        scrollDown(times: 4)

        let apple = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple Developer'")
        ).firstMatch
        if apple.waitForExistence(timeout: 4) {
            apple.tap()
            sleep(1)
        }
    }
}
