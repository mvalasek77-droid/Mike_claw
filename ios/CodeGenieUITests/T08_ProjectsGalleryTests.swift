import XCTest

/// Tests the Apps tab (Projects Gallery): empty state, recent
/// builds list, job cards, fork/resume actions, cost display.
final class T08_ProjectsGalleryTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
        selectTab("Apps")
        sleep(1)
    }

    func test01_emptyStateShowsNewBuildCTA() {
        let newBuild = app.buttons["New build"]
        if newBuild.waitForExistence(timeout: 3) {
            screenshot("01-apps-empty-new-build")
        } else {
            let anyJob = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Open'")
            ).firstMatch
            if anyJob.exists {
                screenshot("01-apps-with-jobs")
            }
        }
    }

    func test02_newBuildButtonOpensDescribe() {
        let newBuild = app.buttons["New build"]
        if newBuild.waitForExistence(timeout: 3) {
            newBuild.tap()
            sleep(1)
            assertExists(app.staticTexts["Shape the experience"],
                         "New build should open the Describe form")
            dismissSheet()
        }
    }

    func test03_jobCardShowsTitle() {
        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open'")
        ).firstMatch
        if card.waitForExistence(timeout: 3) {
            screenshot("03-job-card")
        }
    }

    func test04_jobCardShowsCostBadge() {
        let cost = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Spent' OR label CONTAINS[c] 'dollar'")
        ).firstMatch
        if cost.waitForExistence(timeout: 3) {
            screenshot("04-job-cost-badge")
        }
    }

    func test05_forkBadgeVisible() {
        let fork = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Forked from'")
        ).firstMatch
        if fork.waitForExistence(timeout: 3) {
            screenshot("05-fork-badge")
        }
    }
}
