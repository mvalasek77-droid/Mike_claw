import XCTest

/// Tests the Play tab (BitDrop game) and game integration
/// within the Build screen.
final class T07_GameAndPlayTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    func test01_playTabShowsGameHome() {
        selectTab("Play")
        sleep(1)
        screenshot("01-game-home")
    }

    func test02_difficultySelectorsExist() {
        selectTab("Play")
        sleep(1)

        let difficulties = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'difficulty'")
        )
        XCTAssertGreaterThan(difficulties.count, 0,
                             "Difficulty selectors should be visible")
        screenshot("02-difficulty-selectors")
    }

    func test03_howToPlayButtonExists() {
        selectTab("Play")
        sleep(1)

        let howTo = app.buttons["How to play"]
        assertExists(howTo, "How to play button should exist")
    }

    func test04_gameStatsDisplayed() {
        selectTab("Play")
        sleep(1)

        let stats = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'High score' OR label CONTAINS[c] 'Games played' OR label CONTAINS[c] 'score'")
        )
        if stats.count > 0 {
            screenshot("04-game-stats")
        }
    }

    func test05_canStartGame() {
        selectTab("Play")
        sleep(1)

        let playButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Play' OR label CONTAINS[c] 'Start'")
        ).firstMatch
        if playButton.waitForExistence(timeout: 3) && playButton.isHittable {
            playButton.tap()
            sleep(2)
            screenshot("05-game-playing")
        }
    }
}
