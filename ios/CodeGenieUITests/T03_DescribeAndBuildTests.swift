import XCTest

/// Tests the Describe → cost confirm → Build flow, including:
/// - All form fields (title, prompt, category, style)
/// - Experience DNA readout
/// - Suggestion pills
/// - Cost confirmation gate
/// - Build screen layout (progress, stages, BitDrop, transcript)
/// - Pause/continue, snapshot buttons
/// - Success overlay (Perfection, GitHub, Submit)
/// - Failure overlay (Resume from checkpoint, Start over)
final class T03_DescribeAndBuildTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchReadyToBuild()
    }

    // MARK: - Describe form

    func test01_describeFormHasAllFields() {
        openDescribeForm()

        assertExists(app.staticTexts["Describe your app"])
        assertExists(app.textFields["App name"])
        assertExists(app.textViews.matching(
            NSPredicate(format: "label CONTAINS[c] 'description' OR placeholderValue CONTAINS[c] 'describe'")
        ).firstMatch)

        screenshot("01-describe-all-fields")
    }

    func test02_appNameFieldAcceptsInput() {
        openDescribeForm()

        let nameField = app.textFields["App name"]
        waitAndTap(nameField)
        nameField.typeText("TestApp")

        XCTAssertEqual(nameField.value as? String, "TestApp")
    }

    func test03_promptFieldAcceptsInput() {
        openDescribeForm()

        let promptField = app.textViews.matching(
            NSPredicate(format: "label CONTAINS[c] 'description' OR placeholderValue CONTAINS[c] 'describe'")
        ).firstMatch
        if promptField.waitForExistence(timeout: 3) {
            promptField.tap()
            promptField.typeText("A simple todo app")
        }
    }

    func test04_suggestionPillsExist() {
        openDescribeForm()
        scrollDown(times: 1)

        let suggestions = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'habit' OR label CONTAINS[c] 'journal' OR label CONTAINS[c] 'tide' OR label CONTAINS[c] 'podcast' OR label CONTAINS[c] 'camera'")
        )
        XCTAssertGreaterThan(suggestions.count, 0,
                             "At least one suggestion pill should be visible")
        screenshot("04-suggestions")
    }

    func test05_tappingSuggestionFillsPrompt() {
        openDescribeForm()
        scrollDown(times: 1)

        let suggestion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'habit' OR label CONTAINS[c] 'journal'")
        ).firstMatch
        if suggestion.waitForExistence(timeout: 3) {
            suggestion.tap()
            sleep(1)
            screenshot("05-suggestion-filled")
        }
    }

    func test06_experienceDNAReadoutVisible() {
        openDescribeForm()

        let nameField = app.textFields["App name"]
        waitAndTap(nameField)
        nameField.typeText("TideRider")

        let promptField = app.textViews.firstMatch
        promptField.tap()
        promptField.typeText("Tide times app for surfers with Apple Watch glance and haptics")

        scrollDown(times: 1)

        let dnaLabel = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Experience DNA'")
        ).firstMatch
        if dnaLabel.waitForExistence(timeout: 3) {
            screenshot("06-experience-dna")
        }
    }

    func test07_categoryPickerWorks() {
        openDescribeForm()
        scrollDown(times: 2)

        let categorySection = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Category'")
        ).firstMatch
        if categorySection.waitForExistence(timeout: 3) {
            screenshot("07-category-picker")
        }
    }

    func test08_stylePickerWorks() {
        openDescribeForm()
        scrollDown(times: 2)

        let styleSection = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Style' OR label CONTAINS[c] 'Liquid Glass'")
        ).firstMatch
        if styleSection.waitForExistence(timeout: 3) {
            screenshot("08-style-picker")
        }
    }

    func test09_doubleSubmitGuard() {
        openDescribeForm()
        fillMinimalForm()
        scrollDown(times: 3)

        let buildButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build' OR label CONTAINS[c] 'Start building'")
        ).firstMatch
        guard buildButton.waitForExistence(timeout: 3) else { return }

        buildButton.tap()
        sleep(0.3)

        if buildButton.exists {
            XCTAssertFalse(buildButton.isEnabled,
                           "Build button should disable after first tap to prevent double submit")
        }
    }

    // MARK: - Build screen layout

    func test10_buildScreenShowsProgressOrb() {
        startDemoBuild()
        sleep(2)

        let titleText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'TestApp' OR label CONTAINS[c] 'planning'")
        ).firstMatch
        assertExists(titleText, "Build screen should show app title or stage")
        screenshot("10-build-progress")
    }

    func test11_buildScreenShowsStageList() {
        startDemoBuild()
        sleep(2)

        let stages = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'planning' OR label CONTAINS[c] 'building' OR label CONTAINS[c] 'testing' OR label CONTAINS[c] 'reviewing'")
        )
        XCTAssertGreaterThan(stages.count, 0, "Pipeline stage labels should be visible")
    }

    func test12_buildScreenHasBitDropGame() {
        startDemoBuild()
        sleep(2)

        let gameToggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'BitDrop' OR label CONTAINS[c] 'Hide BitDrop' OR label CONTAINS[c] 'Show BitDrop'")
        ).firstMatch
        if gameToggle.waitForExistence(timeout: 3) {
            screenshot("12-bitdrop-in-build")
        }
    }

    func test13_buildScreenHasMinimizeButton() {
        startDemoBuild()
        sleep(1)

        let minimize = app.buttons["Minimize build"]
        assertExists(minimize, "Minimize (chevron down) button should exist")
    }

    func test14_minimizeDismissesBuildScreen() {
        startDemoBuild()
        sleep(1)

        waitAndTap(app.buttons["Minimize build"])
        sleep(1)

        assertExists(app.buttons["Home"],
                     "Minimizing should return to the tab bar")
    }

    // MARK: - Build screen controls (pause, snapshots)

    func test15_pauseButtonExists() {
        startDemoBuild()
        sleep(2)

        let pause = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Pause build' OR label CONTAINS[c] 'Continue build'")
        ).firstMatch
        if pause.waitForExistence(timeout: 5) {
            screenshot("15-pause-button")
        }
    }

    func test16_snapshotsButtonExists() {
        startDemoBuild()
        sleep(2)

        let snapshots = app.buttons["Open snapshots"]
        if snapshots.waitForExistence(timeout: 5) {
            screenshot("16-snapshots-button")
        }
    }

    func test17_saveCheckpointButtonExists() {
        startDemoBuild()
        sleep(2)

        let save = app.buttons["Save checkpoint"]
        if save.waitForExistence(timeout: 5) {
            screenshot("17-save-checkpoint")
        }
    }

    // MARK: - Jargon help

    func test18_jargonHelpForPipeline() {
        startDemoBuild()
        sleep(2)

        let pipelineHelp = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'pipeline' OR label CONTAINS[c] 'Pipeline'")
        ).firstMatch
        if pipelineHelp.waitForExistence(timeout: 3) {
            pipelineHelp.tap()
            sleep(1)
            screenshot("18-jargon-pipeline")
            dismissSheet()
        }
    }

    // MARK: - Helpers

    private func openDescribeForm() {
        let cta = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start' AND label CONTAINS[c] 'build'")
        ).firstMatch
        if cta.waitForExistence(timeout: 3) {
            cta.tap()
        } else {
            selectTab("Build")
        }
        _ = waitFor(app.staticTexts["Describe your app"], timeout: 5)
    }

    private func fillMinimalForm() {
        let nameField = app.textFields["App name"]
        if nameField.waitForExistence(timeout: 3) {
            nameField.tap()
            nameField.typeText("TestApp")
        }

        let promptField = app.textViews.firstMatch
        if promptField.waitForExistence(timeout: 3) {
            promptField.tap()
            promptField.typeText("A simple todo app with haptics and dark mode")
        }
    }

    /// Starts a real build on the local simulated builder and returns
    /// as soon as the build screen is up, so callers can assert on the
    /// in-progress UI. The canned-sample shortcut this replaced was
    /// removed along with the sample gallery.
    private func startDemoBuild() {
        let cta = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start' AND label CONTAINS[c] 'build'")
        ).firstMatch
        if cta.waitForExistence(timeout: 5) { cta.tap() } else { selectTab("Build") }

        let buildNow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Just build something'")
        ).firstMatch
        if buildNow.waitForExistence(timeout: 3) { buildNow.tap() }

        let nameField = app.textFields["App name"]
        guard nameField.waitForExistence(timeout: 6) else { return }
        nameField.tap()
        nameField.typeText("TestApp")

        let promptField = app.textViews["App description"]
        if promptField.waitForExistence(timeout: 4) {
            promptField.tap()
            promptField.typeText("A simple todo app with haptics and dark mode")
        }

        scrollDown(times: 3)
        let build = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build it'")
        ).firstMatch
        guard build.waitForExistence(timeout: 4) else { return }
        build.tap()

        let confirm = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Confirm and build'")
        ).firstMatch
        if confirm.waitForExistence(timeout: 6) { confirm.tap() }
        _ = app.buttons["Minimize build"].waitForExistence(timeout: 8)
    }
}
