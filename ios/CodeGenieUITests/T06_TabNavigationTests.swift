import XCTest

/// Tests tab bar navigation, tab switching, and that each
/// tab renders its expected root view. Also covers the Build
/// tab's auto-open describe sheet behavior.
final class T06_TabNavigationTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    func test01_homeTabShowsHomeView() {
        selectTab("Home")
        sleep(1)
        let hero = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'CodeGenie' OR label CONTAINS[c] 'build'")
        ).firstMatch
        assertExists(hero)
        screenshot("01-home-tab")
    }

    func test02_buildTabOpensDescribeSheet() {
        selectTab("Build")
        sleep(1)
        assertExists(app.staticTexts["Shape the experience"],
                     "Build tab should auto-present the Describe sheet")
        screenshot("02-build-tab-describe")
    }

    func test03_dismissingDescribeReturnsToHome() {
        selectTab("Build")
        sleep(1)
        dismissSheet()
        sleep(1)
        assertExists(app.buttons["Home"],
                     "Dismissing the Describe sheet should return to Home")
    }

    func test04_playTabShowsGame() {
        selectTab("Play")
        sleep(1)
        let gameContent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'BitDrop' OR label CONTAINS[c] 'game' OR label CONTAINS[c] 'difficulty'")
        ).firstMatch
        assertExists(gameContent, "Play tab should show the game home")
        screenshot("04-play-tab")
    }

    func test05_appsTabShowsProjectsGallery() {
        selectTab("Apps")
        sleep(1)
        let gallery = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apps' OR label CONTAINS[c] 'projects' OR label CONTAINS[c] 'No builds'")
        ).firstMatch
        assertExists(gallery, "Apps tab should show the projects gallery")
        screenshot("05-apps-tab")
    }

    func test06_settingsTabShowsSettings() {
        selectTab("Settings")
        sleep(1)
        let settingsContent = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Settings'")
        ).firstMatch
        assertExists(settingsContent)
        screenshot("06-settings-tab")
    }

    func test07_rapidTabSwitchingDoesNotCrash() {
        let tabs = ["Home", "Build", "Play", "Apps", "Settings"]
        for _ in 0..<3 {
            for tab in tabs {
                selectTab(tab)
                usleep(200_000)
            }
        }
        assertExists(app.buttons["Home"], "App should survive rapid tab switching")
    }

    func test08_tabBarVisibleOnAllTabs() {
        for tab in ["Home", "Play", "Apps", "Settings"] {
            selectTab(tab)
            sleep(0.5)
            for name in ["Home", "Build", "Play", "Apps", "Settings"] {
                assertExists(app.buttons[name],
                             "\(name) tab should be visible on \(tab)")
            }
        }
    }
}
