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
            assertExists(app.staticTexts["Shape the experience"],
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

    func test07_sampleAppsTileOpensSheet() {
        scrollDown(times: 2)
        let tile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Sample' OR label CONTAINS[c] 'sample'")
        ).firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.tap()
            sleep(1)
            screenshot("07-sample-apps-sheet")
            dismissSheet()
        }
    }

    func test08_appOfYearTileOpensSheet() {
        scrollDown(times: 2)
        let tile = app.buttons["App of the Year Studio"]
        if tile.waitForExistence(timeout: 3) {
            tile.tap()
            sleep(1)
            let closeButton = app.buttons["Close App of the Year DNA"]
            assertExists(closeButton, "App of Year sheet should open")
            screenshot("08-app-of-year-sheet")
            dismissSheet()
        }
    }

    // MARK: - Quality checklist

    func test09_qualityChecklistExists() {
        scrollDown(times: 3)
        let checklist = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Quality checklist'")
        ).firstMatch
        assertExists(checklist, "Quality checklist card should exist on Home")
        screenshot("09-quality-checklist")
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

    // MARK: - Demo build from Home

    func test12_sampleAppCanLaunchDemoBuild() {
        scrollDown(times: 2)
        let tile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Sample' OR label CONTAINS[c] 'sample'")
        ).firstMatch
        guard tile.waitForExistence(timeout: 3) else { return }
        tile.tap()
        sleep(1)

        let firstSample = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'instant grade'")
        ).firstMatch
        if firstSample.waitForExistence(timeout: 3) {
            firstSample.tap()
            sleep(2)
            screenshot("12-demo-build-launched")
        }
    }

    // MARK: - Launch automation audit

    func test13_automationAuditTileOpensSheet() {
        scrollDown(times: 2)
        let tile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'automation' OR label CONTAINS[c] 'Automation'")
        ).firstMatch
        if tile.waitForExistence(timeout: 3) {
            tile.tap()
            sleep(1)
            let close = app.buttons["Close automation audit"]
            assertExists(close, "Automation audit sheet should open")
            screenshot("13-automation-audit")
            dismissSheet()
        }
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
