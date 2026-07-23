import XCTest

/// Edge cases, state persistence, error states, and regression
/// tests for known issues fixed during development.
final class T10_EdgeCaseTests: CodeGenieTestBase {

    // MARK: - State persistence across launches

    func test01_onboardingStatePersistedAcrossLaunches() {
        launchOnboarded()
        assertExists(app.buttons["Home"], "First launch should show Home")
        app.terminate()

        launchOnboarded()
        assertExists(app.buttons["Home"],
                     "Second launch should still show Home (not re-onboard)")
    }

    func test02_freshInstallDoesNotSkipOnboarding() {
        launchFreshInstall()
        let splash = app.staticTexts["CodeGenie. Ship from your pocket."]
        let skip = app.buttons["Skip onboarding"]
        let either = splash.waitForExistence(timeout: 5) || skip.waitForExistence(timeout: 5)
        XCTAssertTrue(either, "Fresh install should show splash or onboarding")
    }

    // MARK: - Empty state handling

    func test03_noRecentJobsShowsEmptyState() {
        launchOnboarded()
        selectTab("Apps")
        sleep(1)

        let newBuild = app.buttons["New build"]
        let noJobs = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'No builds' OR label CONTAINS[c] 'no apps'")
        ).firstMatch
        let emptyUI = newBuild.exists || noJobs.exists
        XCTAssertTrue(emptyUI, "Apps tab should handle empty state gracefully")
    }

    // MARK: - Terms scroll gate (regression: lazy vs eager VStack)

    func test04_termsAgreeDisabledUntilScroll() {
        launchAfterOnboarding()
        assertExists(app.staticTexts["Before we start"])

        let agree = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'agree'")
        ).firstMatch
        if agree.waitForExistence(timeout: 2) {
            XCTAssertFalse(agree.isEnabled,
                           "Agree should be disabled before scrolling (LazyVStack gate)")
        }
    }

    // MARK: - Describe form double-submit guard

    func test05_describeFormPreventsDoubleSubmit() {
        launchOnboarded()
        selectTab("Build")
        sleep(1)

        let nameField = app.textFields["App name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("TestApp")
        }

        let promptField = app.textViews.firstMatch
        if promptField.waitForExistence(timeout: 3) {
            promptField.tap()
            promptField.typeText("A test app with haptics")
        }

        scrollDown(times: 3)

        let build = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build' OR label CONTAINS[c] 'Start building'")
        ).firstMatch
        guard build.waitForExistence(timeout: 3) else { return }

        build.tap()
        usleep(200_000)

        if build.exists {
            XCTAssertFalse(build.isEnabled, "Double-submit should be prevented")
        }
    }

    // MARK: - Build tab dismiss returns to Home

    func test06_buildTabDismissReturnsHome() {
        launchOnboarded()
        selectTab("Build")
        sleep(1)
        dismissSheet()
        sleep(1)
        assertExists(app.buttons["Home"],
                     "Dismissing Build tab's describe sheet should go to Home")
    }

    // MARK: - Settings auth mode round-trip

    func test07_authModeRoundTrip() {
        launchOnboarded()
        selectTab("Settings")
        sleep(1)

        let byok = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'own key' OR label CONTAINS[c] 'BYOK'")
        ).firstMatch
        if byok.waitForExistence(timeout: 3) {
            byok.tap()
            sleep(1)
        }

        let hosted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Hosted' OR label CONTAINS[c] 'CodeGenie Hosted'")
        ).firstMatch
        if hosted.waitForExistence(timeout: 3) {
            hosted.tap()
            sleep(1)
        }

        screenshot("07-auth-mode-round-trip")
    }

    // MARK: - Memory pressure (rapid navigation)

    func test08_rapidNavigationStressTest() {
        launchOnboarded()

        for _ in 0..<5 {
            selectTab("Settings")
            usleep(100_000)
            selectTab("Home")
            usleep(100_000)
            selectTab("Play")
            usleep(100_000)
            selectTab("Apps")
            usleep(100_000)
            selectTab("Build")
            usleep(300_000)
            dismissSheet()
            usleep(100_000)
        }

        assertExists(app.buttons["Home"], "App should survive rapid navigation")
    }

    // MARK: - Landscape rotation

    func test09_landscapeDoesNotCrash() {
        launchOnboarded()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        assertExists(app.buttons["Home"],
                     "App should survive landscape rotation")
        screenshot("09-landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
    }

    // MARK: - Background / foreground cycle

    func test10_backgroundForegroundCycle() {
        launchOnboarded()
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        sleep(1)
        assertExists(app.buttons["Home"],
                     "App should recover from background/foreground cycle")
    }

    // MARK: - No subscription mode (regression)

    func test11_noSubscriptionModeInSettings() {
        launchOnboarded()
        selectTab("Settings")
        sleep(1)
        scrollDown(times: 6)

        let subscription = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Subscription'")
        ).firstMatch
        XCTAssertFalse(subscription.exists,
                       "Subscription mode was removed — should not appear in Settings")
    }

    func test12_noSubscriptionModeInPricing() {
        launchAfterTerms()

        let subscription = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Subscription'")
        ).firstMatch
        XCTAssertFalse(subscription.exists,
                       "Subscription plan was removed — should not appear in Pricing")
    }
}
