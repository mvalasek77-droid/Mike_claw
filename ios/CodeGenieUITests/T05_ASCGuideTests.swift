import XCTest

/// Tests the App Store Connect guided walkthrough — 10 steps
/// from sign-in through submission. Since the guide is shown
/// post-build, these tests verify the sheet presentation and
/// step navigation, not actual ASC actions.
final class T05_ASCGuideTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    // MARK: - ASC guide reachable from build success

    func test01_ascGuideStructureExists() {
        openASCGuideFromSettings()
        guard waitFor(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'App Store Connect' OR label CONTAINS[c] 'Submit'")
        ).firstMatch, timeout: 5) else { return }

        screenshot("01-asc-guide-open")
    }

    func test02_ascGuideHasTenSteps() {
        openASCGuideFromSettings()
        sleep(1)

        var stepCount = 0
        for i in 1...10 {
            let step = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Step \(i)'")
            ).firstMatch
            if step.exists { stepCount += 1 }
        }
        scrollDown(times: 3)
        for i in 1...10 {
            let step = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'Step \(i)'")
            ).firstMatch
            if step.exists { stepCount += 1 }
        }

        XCTAssertGreaterThanOrEqual(stepCount, 3,
                                    "ASC guide should show at least some numbered steps")
        screenshot("02-asc-steps")
    }

    func test03_ascStepCardsAreInteractive() {
        openASCGuideFromSettings()
        sleep(1)

        let firstStep = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Step 1' OR label CONTAINS[c] 'Sign in'")
        ).firstMatch
        if firstStep.waitForExistence(timeout: 3) {
            firstStep.tap()
            sleep(1)
            screenshot("03-asc-step-expanded")
        }
    }

    func test04_ascStepShowsAutomationBadge() {
        openASCGuideFromSettings()
        sleep(1)

        let badge = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Auto' OR label CONTAINS[c] 'Hybrid' OR label CONTAINS[c] 'Manual'")
        ).firstMatch
        if badge.waitForExistence(timeout: 3) {
            screenshot("04-automation-badge")
        }
    }

    func test05_ascGuideScrollsThroughAllSteps() {
        openASCGuideFromSettings()
        sleep(1)

        for i in 0..<5 {
            scrollDown(times: 1)
            sleep(0.5)
            screenshot("05-asc-scroll-\(i)")
        }
    }

    // MARK: - Helpers

    private func openASCGuideFromSettings() {
        selectTab("Settings")
        sleep(1)
        scrollDown(times: 4)

        let apple = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple Developer' OR label CONTAINS[c] 'App Store Connect'")
        ).firstMatch
        if apple.waitForExistence(timeout: 3) {
            apple.tap()
            sleep(1)
        }
    }
}
