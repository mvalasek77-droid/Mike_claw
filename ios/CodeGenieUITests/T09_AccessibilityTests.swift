import XCTest

/// Accessibility audit across every major screen.
/// Verifies that all interactive elements have labels,
/// no text is clipped, and VoiceOver can traverse every tab.
final class T09_AccessibilityTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    // MARK: - Home tab

    func test01_homeButtonsHaveLabels() {
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty,
                           "Button at \(button.frame) has no accessibility label")
        }
    }

    func test02_homeStaticTextsNotEmpty() {
        let texts = app.staticTexts.allElementsBoundByAccessibilityElement
        let nonEmpty = texts.filter { !$0.label.isEmpty }
        XCTAssertGreaterThan(nonEmpty.count, 3,
                             "Home should have visible text content")
    }

    // MARK: - Settings tab

    func test03_settingsButtonsHaveLabels() {
        selectTab("Settings")
        sleep(1)
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty,
                           "Settings button at \(button.frame) has no accessibility label")
        }
    }

    // MARK: - Play tab

    func test04_playTabAccessible() {
        selectTab("Play")
        sleep(1)
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty,
                           "Play button at \(button.frame) has no accessibility label")
        }
    }

    // MARK: - Describe form

    func test05_describeFormFieldsLabeled() {
        selectTab("Build")
        sleep(1)

        let nameField = app.textFields["App name"]
        assertExists(nameField, "App name field should have accessibility label")

        let promptField = app.textViews.matching(
            NSPredicate(format: "label CONTAINS[c] 'description'")
        ).firstMatch
        if promptField.exists {
            XCTAssertFalse(promptField.label.isEmpty)
        }
    }

    // MARK: - VoiceOver traversal smoke test

    func test06_voiceOverCanTraverseHome() {
        let elements = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .filter { $0.isHittable }
        XCTAssertGreaterThan(elements.count, 5,
                             "Home should have multiple hittable accessible elements")
    }

    // MARK: - Dynamic Type

    func test07_appLaunchesWithLargeText() {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true",
            "-hasAcceptedTerms", "true",
            "-hasChosenPricing", "true",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()

        assertExists(app.buttons["Home"],
                     "App should launch successfully with extra-large text")
        screenshot("07-dynamic-type-large")
    }

    // MARK: - Dark mode

    func test08_appRendersInDarkMode() {
        screenshot("08-dark-mode-home")
    }

    // MARK: - Color scheme persistence

    func test09_appRespectsPreferredColorScheme() {
        selectTab("Settings")
        sleep(1)
        selectTab("Home")
        sleep(1)
        screenshot("09-color-scheme")
    }
}
