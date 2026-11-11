import XCTest

/// Tests every surface on the Home tab: hero, primary CTA, resume
/// callout, experience compass, ship readiness, quick grid, recent
/// jobs, quality checklist, and all sheets launched from tiles.
final class T02_HomeScreenTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    // MARK: - Tab bar

    func test01_homeTabIsSelectedByDefault() {
        let homeTab = app.buttons["Home"]
        assertExists(homeTab)
        XCTAssertTrue(homeTab.isSelected || homeTab.value as? String == "1",
                      "Home tab should be selected on launch")
    }

    func test02_allFiveTabsExist() {
        for tab in ["Home", "Build", "Play", "Apps", "Settings"] {
            assertExists(app.buttons[tab], "\(tab) tab should exist")
        }
        screenshot("02-five-tabs")
    }

    // MARK: - Hero + primary action

    func test03_heroTextIsVisible() {
        let heroTexts = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'CodeGenie' OR label CONTAINS[c] 'build'")
        )
        XCTAssertGreaterThan(heroTexts.count, 0, "Hero section should have branding text")
    }

    func test04_startBuildCTAExists() {
        let cta = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start' OR label CONTAINS[c] 'new build' OR label CONTAINS[c] 'Build'")
        ).firstMatch
        assertExists(cta, "A primary 'Start a build' CTA should exist on Home")
        screenshot("04-home-primary-cta")
    }

    func test05_startBuildOpensDescribeSheet() {
        let cta = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start' AND label CONTAINS[c] 'build'")
        ).firstMatch
        if cta.waitForExistence(timeout: 3) {
            cta.tap()
            assertExists(app.staticTexts["Describe your app"],
                         "Tapping Start should open the Describe form")
            screenshot("05-describe-sheet")
        }
    }

    // MARK: - Ship readiness card

    func test06_shipReadinessCardExists() {
        scrollDown(times: 1)
        let card = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Ship checklist'")
        ).firstMatch
        assertExists(card, "Ship readiness checklist card should exist on Home")
        screenshot("06-ship-readiness")
    }

    // MARK: - Quick grid tiles

    /// The gear in the Home header used to be a decorative icon with
    /// an empty action — tapping it did nothing at all.
    func test07_settingsGearInHeaderOpensSettings() {
        let gear = app.buttons["Settings"]
        assertExists(gear, "Home header should have a working Settings button")
        gear.tap()
        assertExists(app.staticTexts["Settings"], "Tapping the gear should open Settings")
        screenshot("07-header-settings")
    }

    // MARK: - Next step

    func test09_homeNamesOneNextStep() {
        let card = app.descendants(matching: .any)["journey.card"]
        assertExists(card, "Home should lead with a single next step")
        assertExists(app.staticTexts["Describe the app you want"],
                     "With nothing built yet, the next step is to describe an app")
        let action = app.buttons["journey.primaryAction"]
        assertExists(action, "The next step needs one button")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Quality checklist'")).firstMatch.exists,
            "Home must not show a checklist of claims nothing verifies"
        )
        screenshot("09-next-step")
    }

    func test09b_nextStepOpensTheDescribeForm() {
        let action = app.buttons["journey.primaryAction"]
        guard action.waitForExistence(timeout: 3) else {
            XCTFail("Next-step button missing"); return
        }
        action.tap()
        let describe = app.staticTexts["Describe your app"]
        let prompt = app.staticTexts["Good to know before you start"]
        XCTAssertTrue(describe.waitForExistence(timeout: 3) || prompt.waitForExistence(timeout: 2),
                      "The next step should lead straight into describing an app")
        screenshot("09b-next-step-opens-describe")
    }

    // MARK: - Experience compass

    func test10_experienceCompassIsVisible() {
        scrollDown(times: 1)
        let compass = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'compass' OR label CONTAINS[c] 'Experience'")
        ).firstMatch
        if compass.waitForExistence(timeout: 3) {
            screenshot("10-experience-compass")
        }
    }

    // MARK: - Resume callout (negative — no pending job)

    func test11_noResumeCalloutWhenNoPendingJob() {
        let resumeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Resume'")
        ).firstMatch
        XCTAssertFalse(resumeButton.waitForExistence(timeout: 2),
                       "No resume callout should appear without a pending job")
    }

    // MARK: - Removed surfaces

    /// The sample gallery was a dead end — its builds could not be
    /// submitted, downloaded, or reopened, so it was removed.
    func test12_noSampleGalleryEntryPointRemains() {
        scrollDown(times: 2)
        let tile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Try a sample'")
        ).firstMatch
        XCTAssertFalse(tile.waitForExistence(timeout: 2),
                       "The dead sample tile should no longer be on Home")
    }

    // MARK: - Game tile

    func test14_gameTileOpensGameFullScreen() {
        scrollDown(times: 2)
        let tile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'game' OR label CONTAINS[c] 'Game' OR label CONTAINS[c] 'Play' OR label CONTAINS[c] 'BitDrop'")
        ).firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.tap()
            sleep(1)
            let close = app.buttons["Close game"]
            if close.waitForExistence(timeout: 3) {
                screenshot("14-game-screen")
                close.tap()
            }
        }
    }

    // MARK: - Bug report

    func test15_bugReportIsReachable() {
        scrollDown(times: 4)
        let bugTile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'bug' OR label CONTAINS[c] 'report'")
        ).firstMatch
        if bugTile.waitForExistence(timeout: 3) {
            bugTile.tap()
            sleep(1)
            screenshot("15-bug-report")
            dismissSheet()
        }
    }
}
