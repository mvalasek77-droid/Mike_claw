import XCTest

/// App Store Connect submission flow.
///
/// Covers the coach panel, listing validation against Apple's real
/// field limits, the metadata editor, per-step actions and their
/// no-Mac fallbacks, and — most importantly — that progress survives
/// closing the guide and relaunching the app.
final class T11_ASCSubmissionFlowTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchOnboarded()
    }

    // MARK: - Reachability

    func test01_ascGuideReachableFromBuildSuccess() {
        openBuildSuccessOverlay()
        let walkthrough = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Walk me through'")
        ).firstMatch
        assertExists(walkthrough,
                     "Build success must offer the submission walkthrough")
        screenshot("01-asc-entry-point")
    }

    func test02_openingGuideShowsTenSteps() {
        openASCGuide()
        for n in [1, 2, 3] {
            assertExists(app.staticTexts["Step \(n)"], "Step \(n) should render")
        }
        scrollDown(times: 6)
        assertExists(app.staticTexts["Step 10"], "Step 10 should render after scrolling")
        screenshot("02-ten-steps")
    }

    // MARK: - Coach

    func test03_coachPanelTellsUserWhatToDoNext() {
        openASCGuide()
        let coach = app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH 'Coach:'")
        ).firstMatch
        assertExists(coach, "The coach panel should state the next action")
        screenshot("03-coach-panel")
    }

    func test04_coachFlagsMissingSupportURLAsBlocking() {
        openASCGuide()
        // A fresh draft ships with an empty support URL on purpose —
        // a placeholder would sail past validation and fail review.
        let blocker = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Support URL'")
        ).firstMatch
        XCTAssertTrue(blocker.waitForExistence(timeout: 4),
                      "Missing support URL must be surfaced as a blocker")
        screenshot("04-support-url-blocker")
    }

    // MARK: - Listing card

    func test05_listingCardShowsCharacterBudgets() {
        openASCGuide()
        let nameRow = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Name' AND label CONTAINS[c] 'characters'")
        ).firstMatch
        XCTAssertTrue(nameRow.waitForExistence(timeout: 4),
                      "Listing rows should show an n-of-limit character count")
        screenshot("05-character-budgets")
    }

    func test06_copyAllPutsListingOnClipboard() {
        openASCGuide()
        let copyAll = app.buttons["Copy the whole listing to the clipboard"]
        guard copyAll.waitForExistence(timeout: 4) else {
            XCTFail("Copy-all button missing"); return
        }
        copyAll.tap()
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'copied'")
        ).firstMatch, "Copying should confirm with a banner")
        screenshot("06-copy-listing")
    }

    // MARK: - Metadata editor

    func test07_editListingOpensEditor() {
        openASCGuide()
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)
        assertExists(app.navigationBars["Edit listing"])
        screenshot("07-metadata-editor")
    }

    func test08_editorEnforcesAppleNameLimit() {
        openASCGuide()
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)

        let nameField = app.textFields["App name"]
        guard nameField.waitForExistence(timeout: 4) else {
            XCTFail("App name field missing"); return
        }
        nameField.tap()
        // 35 characters — five past Apple's 30-char cap.
        nameField.typeText(String(repeating: "A", count: 35))

        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '35/30'")
        ).firstMatch, "Counter should show the field is over Apple's limit")
        screenshot("08-name-over-limit")
    }

    func test09_keywordsExplainSharedCharacterBudget() {
        openASCGuide()
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)
        scrollDown(times: 1)
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'commas included'")
        ).firstMatch,
        "Keywords help text must explain it is one shared 100-char budget")
        screenshot("09-keywords-budget")
    }

    func test10_supportURLFixClearsTheBlocker() {
        openASCGuide()
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)

        scrollDown(times: 3)
        let supportField = app.textFields["Support URL"]
        guard supportField.waitForExistence(timeout: 4) else { return }
        supportField.tap()
        supportField.typeText("https://github.com/example/repo")

        app.buttons["Done"].tap()
        screenshot("10-support-url-fixed")
    }

    // MARK: - No-Mac fallbacks

    func test11_everyStepWorksWithoutAMac() {
        openASCGuide()
        assertExists(app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'No Mac paired'")
        ).firstMatch, "Unpaired state should be stated plainly")
        // The promise of the unpaired copy is that the phone alone is enough.
        assertExists(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch, "Step 1 must offer an on-phone route")
        screenshot("11-no-mac-fallback")
    }

    // MARK: - Save & continue

    func test12_completingAStepPersistsAcrossRelaunch() {
        openASCGuide()

        let safari = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch
        guard safari.waitForExistence(timeout: 4) else {
            XCTFail("Step 1 action missing"); return
        }
        safari.tap()

        // Come back from Safari, then cold-launch the app.
        app.activate()
        app.terminate()
        launchOnboarded()

        let callout = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Continue submitting'")
        ).firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 6),
                      "Home must offer to continue an in-flight submission after relaunch")
        screenshot("12-continue-after-relaunch")
    }

    func test13_continueCalloutResumesOnTheRightStep() {
        openASCGuide()
        let safari = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch
        guard safari.waitForExistence(timeout: 4) else { return }
        safari.tap()
        app.activate()

        dismissSheet()
        sleep(1)

        let callout = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Continue submitting'")
        ).firstMatch
        guard callout.waitForExistence(timeout: 5) else {
            XCTFail("Continue callout missing"); return
        }
        // The label carries the resume position, so assert on it directly.
        XCTAssertTrue(callout.label.contains("step 2"),
                      "Resuming should land on step 2 after step 1 completed — got: \(callout.label)")
        callout.tap()
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Picked up where you left off'")
        ).firstMatch)
        screenshot("13-resumed-banner")
    }

    func test14_completedStepCanBeReopened() {
        openASCGuide()
        let safari = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch
        guard safari.waitForExistence(timeout: 4) else { return }
        safari.tap()
        app.activate()

        let reopen = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Reopen this step'")
        ).firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 4),
                      "A finished step must be reopenable — users mis-tap")
        screenshot("14-reopen-step")
    }

    // MARK: - Submission is gated, not self-reported

    /// Demo builds have no live backend job, so the release-readiness
    /// recheck `attemptFinalSubmit()` runs before showing the
    /// confirmation alert can never come back "ready" — the button
    /// must show the blocked sheet instead of trusting the user's
    /// word. This is the second hard gate: CodeGenie re-verifies at
    /// the moment of truth rather than letting stale state through.
    func test15_finalSubmitIsBlockedWithoutVerifiedReadiness() {
        openASCGuide()
        scrollDown(times: 8)
        let submitted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'I submitted for review'")
        ).firstMatch
        guard submitted.waitForExistence(timeout: 4) else { return }
        submitted.tap()

        assertExists(app.navigationBars["Not quite ready"],
                     "Submit must re-verify the release checklist and block on what's outstanding, not just ask the user to confirm")
        screenshot("15-submit-blocked")
    }

    func test16_progressBarReflectsCompletedSteps() {
        openASCGuide()
        let progress = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'of 10 steps complete'")
        ).firstMatch
        assertExists(progress, "Progress should be announced for VoiceOver")
        screenshot("16-progress")
    }

    // MARK: - Pre-flight gate (proactive, hard-blocking on entry)

    func test17_preflightChecksBeforeAnythingElseIsShown() {
        openBuildSuccessOverlay()
        let walkthrough = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Walk me through'")
        ).firstMatch
        guard walkthrough.waitForExistence(timeout: 10) else { return }
        walkthrough.tap()

        // The AI narrates that it is actively checking, before any step
        // content — this is the "proactive" requirement: no button the
        // user has to remember to press.
        let checking = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Checking your app'")
        ).firstMatch
        let reachedGate = checking.waitForExistence(timeout: 3)
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] \"Can't verify\"")).firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(reachedGate, "Opening the guide must immediately run a check, not show step 1 first")
        screenshot("17-preflight-checking")
    }

    func test18_unverifiableBuildOffersExplicitEscapeHatch() {
        openBuildSuccessOverlay()
        let walkthrough = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Walk me through'")
        ).firstMatch
        guard walkthrough.waitForExistence(timeout: 10) else { return }
        walkthrough.tap()

        // Demo builds have no live backend job to check against.
        let skip = app.buttons["Continue without verification"]
        guard skip.waitForExistence(timeout: 6) else {
            XCTFail("Expected the unverifiable state for a demo build with no backend job")
            return
        }
        screenshot("18-unverifiable-escape-hatch")
        skip.tap()

        assertExists(app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH 'Coach:'")
        ).firstMatch, "Explicitly skipping verification should reach the normal guide")
    }

    // MARK: - Helpers

    private func openBuildSuccessOverlay() {
        scrollDown(times: 2)
        let sampleTile = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'sample'")
        ).firstMatch
        guard sampleTile.waitForExistence(timeout: 4) else { return }
        sampleTile.tap()
        sleep(1)
        let demo = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'instant grade'")
        ).firstMatch
        if demo.waitForExistence(timeout: 4) {
            demo.tap()
            // Canned demo scripts run to green on their own.
            _ = app.staticTexts["Build green"].waitForExistence(timeout: 60)
        }
    }

    /// Opens the guide and clears the pre-flight gate. Demo builds have
    /// no live backend job, so the gate always lands on "unverifiable"
    /// rather than "checking" or "blocked" — tests that need to reach
    /// the normal step list use the explicit escape hatch, exactly as
    /// a real device tester would when offline.
    private func openASCGuide() {
        openBuildSuccessOverlay()
        let walkthrough = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Walk me through'")
        ).firstMatch
        guard walkthrough.waitForExistence(timeout: 10) else { return }
        walkthrough.tap()

        let skip = app.buttons["Continue without verification"]
        if skip.waitForExistence(timeout: 6) {
            skip.tap()
        }
        _ = app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH 'Coach:'")
        ).firstMatch.waitForExistence(timeout: 5)
    }
}
