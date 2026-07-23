import XCTest

/// Tests every Settings section:
/// - Auth mode toggle (BYOK / Hosted)
/// - API key entry & reveal
/// - Hosted plan status
/// - Model comparison
/// - Cost estimator
/// - Setup guides (GitHub, Apple Dev, Xcode readiness)
/// - Power user mode toggle
/// - Power-user surfaces (cost cap, agent routing, custom agents,
///   Apple Dev, Mac pairing, admin)
/// - Tutorial replay
/// - Telemetry toggle
/// - Support (bug report, changelog)
/// - About section
final class T04_SettingsTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
        selectTab("Settings")
        sleep(1)
    }

    // MARK: - Basic layout

    func test01_settingsHeaderExists() {
        let header = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Settings'")
        ).firstMatch
        assertExists(header)
        screenshot("01-settings-header")
    }

    // MARK: - Auth mode

    func test02_authModePickerExists() {
        let byok = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Bring your own' OR label CONTAINS[c] 'BYOK' OR label CONTAINS[c] 'own key'")
        ).firstMatch
        let hosted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Hosted' OR label CONTAINS[c] 'CodeGenie'")
        ).firstMatch
        let either = byok.exists || hosted.exists
        XCTAssertTrue(either, "Auth mode picker should exist in Settings")
        screenshot("02-auth-mode")
    }

    func test03_switchToByokShowsKeyEntry() {
        let byok = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Bring your own' OR label CONTAINS[c] 'BYOK' OR label CONTAINS[c] 'own key'")
        ).firstMatch
        if byok.waitForExistence(timeout: 3) {
            byok.tap()
            sleep(1)
            let keyField = app.secureTextFields.firstMatch
            let revealButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Show key' OR label CONTAINS[c] 'Hide key'")
            ).firstMatch
            let hasKeyUI = keyField.exists || revealButton.exists
            XCTAssertTrue(hasKeyUI, "BYOK mode should show key entry fields")
            screenshot("03-byok-key-entry")
        }
    }

    // MARK: - Model comparison

    func test04_modelComparisonSectionExists() {
        scrollDown(times: 1)
        let modelSection = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'model' OR label CONTAINS[c] 'Model'")
        ).firstMatch
        assertExists(modelSection, "Model comparison section should exist")
    }

    // MARK: - Cost estimator

    func test05_costEstimatorExists() {
        scrollDown(times: 1)
        let estimator = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'cost' OR label CONTAINS[c] 'Cost' OR label CONTAINS[c] 'estimate'")
        ).firstMatch
        assertExists(estimator, "Cost estimator block should exist")
        screenshot("05-cost-estimator")
    }

    // MARK: - Setup guides

    func test06_gitHubSetupGuideOpens() {
        scrollDown(times: 2)
        let guide = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'GitHub'")
        ).firstMatch
        if guide.waitForExistence(timeout: 3) {
            guide.tap()
            sleep(1)
            let stepIndicator = app.otherElements.matching(
                NSPredicate(format: "label CONTAINS[c] 'Step 1'")
            ).firstMatch
            if stepIndicator.waitForExistence(timeout: 3) {
                screenshot("06-github-setup")
            }
            dismissSheet()
        }
    }

    func test07_appleDevWalkthroughOpens() {
        scrollDown(times: 2)
        let guide = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple Developer' OR label CONTAINS[c] 'apple dev'")
        ).firstMatch
        if guide.waitForExistence(timeout: 3) {
            guide.tap()
            sleep(1)
            screenshot("07-apple-dev-walkthrough")
            dismissSheet()
        }
    }

    func test08_xcodeReadinessOpens() {
        scrollDown(times: 2)
        let xcode = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Xcode'")
        ).firstMatch
        if xcode.waitForExistence(timeout: 3) {
            xcode.tap()
            sleep(1)
            screenshot("08-xcode-readiness")
            dismissSheet()
        }
    }

    // MARK: - Power user mode

    func test09_powerUserToggleExists() {
        scrollDown(times: 3)
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Power' OR label CONTAINS[c] 'power user'")
        ).firstMatch
        assertExists(toggle, "Power user mode toggle should exist")
        screenshot("09-power-user-toggle")
    }

    func test10_enablingPowerModeShowsAdvancedSections() {
        scrollDown(times: 3)
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Power' OR label CONTAINS[c] 'power user'")
        ).firstMatch
        guard toggle.waitForExistence(timeout: 3) else { return }
        toggle.tap()
        sleep(1)
        scrollDown(times: 2)

        let costCap = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'cost cap' OR label CONTAINS[c] 'Cost cap'")
        ).firstMatch
        let agentRouting = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Agent routing' OR label CONTAINS[c] 'routing'")
        ).firstMatch
        let customAgents = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Custom agents' OR label CONTAINS[c] 'custom agent'")
        ).firstMatch

        let anyAdvanced = costCap.exists || agentRouting.exists || customAgents.exists
        XCTAssertTrue(anyAdvanced,
                      "Power mode should reveal cost cap, agent routing, or custom agents")
        screenshot("10-power-mode-surfaces")
    }

    // MARK: - Power-user sub-screens

    func test11_agentRoutingOpens() {
        enablePowerMode()
        scrollDown(times: 3)
        let routing = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Agent routing' OR label CONTAINS[c] 'routing'")
        ).firstMatch
        if routing.waitForExistence(timeout: 3) {
            routing.tap()
            sleep(1)
            screenshot("11-agent-routing")
            dismissSheet()
        }
    }

    func test12_customAgentsOpens() {
        enablePowerMode()
        scrollDown(times: 4)
        let custom = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Custom agents' OR label CONTAINS[c] 'custom agent'")
        ).firstMatch
        if custom.waitForExistence(timeout: 3) {
            custom.tap()
            sleep(1)
            screenshot("12-custom-agents")
            dismissSheet()
        }
    }

    func test13_pairMacOpens() {
        enablePowerMode()
        scrollDown(times: 4)
        let pair = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Pair' OR label CONTAINS[c] 'Mac'")
        ).firstMatch
        if pair.waitForExistence(timeout: 3) {
            pair.tap()
            sleep(1)
            screenshot("13-pair-mac")
            dismissSheet()
        }
    }

    func test14_adminOpens() {
        enablePowerMode()
        scrollDown(times: 5)
        let admin = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Admin'")
        ).firstMatch
        if admin.waitForExistence(timeout: 3) {
            admin.tap()
            sleep(1)
            let decisionSearch = app.buttons["Open decision memory search"]
            let archives = app.buttons["Open archived workspaces"]
            let hasAdmin = decisionSearch.exists || archives.exists
            XCTAssertTrue(hasAdmin, "Admin panel should have decision search or archives")
            screenshot("14-admin-panel")
            dismissSheet()
        }
    }

    // MARK: - Tutorial replay

    func test15_tutorialReplayOpens() {
        scrollDown(times: 4)
        let tutorial = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'tutorial' OR label CONTAINS[c] 'Tutorial' OR label CONTAINS[c] 'Watch again'")
        ).firstMatch
        if tutorial.waitForExistence(timeout: 3) {
            tutorial.tap()
            sleep(1)
            let closeLabel = app.buttons["Close tutorial"]
            assertExists(closeLabel, "Tutorial replay should open")
            screenshot("15-tutorial-replay")
            dismissSheet()
        }
    }

    // MARK: - Telemetry

    func test16_telemetryToggleExists() {
        scrollDown(times: 5)
        let telemetry = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'telemetry' OR label CONTAINS[c] 'Telemetry' OR label CONTAINS[c] 'analytics'")
        ).firstMatch
        if telemetry.waitForExistence(timeout: 3) {
            screenshot("16-telemetry")
        }
    }

    // MARK: - Support

    func test17_changelogOpens() {
        scrollDown(times: 6)
        let changelog = app.buttons["Open changelog"]
        if changelog.waitForExistence(timeout: 3) {
            changelog.tap()
            sleep(1)
            screenshot("17-changelog")
            dismissSheet()
        }
    }

    func test18_crashLogOpens() {
        scrollDown(times: 6)
        let crashLog = app.buttons["Open recent build failures"]
        if crashLog.waitForExistence(timeout: 3) {
            crashLog.tap()
            sleep(1)
            screenshot("18-crash-log")
            dismissSheet()
        }
    }

    func test19_bugReportOpens() {
        scrollDown(times: 6)
        let bug = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'bug' OR label CONTAINS[c] 'Bug'")
        ).firstMatch
        if bug.waitForExistence(timeout: 3) {
            bug.tap()
            sleep(1)
            let details = app.textViews["Bug report details"]
            if details.waitForExistence(timeout: 3) {
                screenshot("19-bug-report")
            }
            dismissSheet()
        }
    }

    // MARK: - Helpers

    private func enablePowerMode() {
        scrollDown(times: 3)
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Power' OR label CONTAINS[c] 'power user'")
        ).firstMatch
        if toggle.waitForExistence(timeout: 3) {
            toggle.tap()
            sleep(1)
        }
    }
}
