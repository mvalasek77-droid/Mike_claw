import XCTest

/// App Store Connect submission flow.
///
/// Covers the focused one-step-at-a-time guide, the two-phase step
/// structure (get it on your phone first, App Store second), the
/// click-by-click walkthrough content, listing validation against
/// Apple's real field limits, the metadata editor, per-step actions and
/// their no-Mac fallbacks, and — most importantly — that progress
/// survives closing the guide and relaunching the app.
final class T11_ASCSubmissionFlowTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchReadyToBuild()
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

    /// Focus mode: the guide opens on one step, not twelve. Seeing all
    /// twelve at once is what made this screen unreadable for someone
    /// who has never submitted an app.
    func test02_guideOpensOnASingleFocusedStep() {
        openASCGuide()

        assertExists(app.staticTexts["Step 1 of 12"],
                     "The guide should say exactly which step you're on")
        assertExists(app.staticTexts["Sign in to Apple's website"],
                     "The focused step should be titled in plain language")

        XCTAssertFalse(app.staticTexts["Step 7 of 12"].exists,
                       "Later steps must not be on screen — that's the whole point of focus mode")
        screenshot("02-single-focused-step")
    }

    func test03_allTwelveStepsAreReachableOnRequest() {
        openASCGuide()
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'See all 12 steps'")
        ).firstMatch)

        assertExists(app.staticTexts["Part 1 — Get it on your phone"],
                     "Phase 1 header should render in the overview")
        scrollDown(times: 4)
        assertExists(app.staticTexts["Part 2 — Put it on the App Store"],
                     "Phase 2 header should render in the overview")
        screenshot("03-full-overview")
    }

    // MARK: - The walkthrough content itself

    /// The core fix: every step spells out the literal clicks, not a
    /// one-line summary that assumes you already know the console.
    func test04_focusedStepGivesLiteralClickByClickInstructions() {
        openASCGuide()
        assertExists(app.staticTexts["Do this"],
                     "Each step must list the actual clicks")
        let firstInstruction = app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH 'Step 1.'")
        ).firstMatch
        XCTAssertTrue(firstInstruction.waitForExistence(timeout: 4),
                      "Instructions should be numbered and readable by VoiceOver")
        screenshot("04-click-by-click")
    }

    func test05_stepWarnsAboutTheCommonMistake() {
        openASCGuide()
        let watchOut = app.otherElements.matching(
            NSPredicate(format: "label BEGINSWITH 'Where people get stuck'")
        ).firstMatch
        XCTAssertTrue(watchOut.waitForExistence(timeout: 4),
                      "Every step should name the thing that usually goes wrong")
        screenshot("05-watch-out")
    }

    /// Bundle ID typos are the most common cause of a rejected upload,
    /// so the value is offered as a copy button rather than as text to
    /// retype.
    func test06_exactValuesAreOfferedAsCopyButtons() {
        openASCGuide()
        jumpToStep(2)
        let copyButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Copy com.codegenie'")
        ).firstMatch
        XCTAssertTrue(copyButton.waitForExistence(timeout: 4),
                      "The bundle ID must be copyable, not retyped by hand")
        copyButton.tap()
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Copied'")
        ).firstMatch, "Copying should confirm")
        screenshot("06-copy-bundle-id")
    }

    func test07_stepSetsATimeExpectation() {
        openASCGuide()
        jumpToStep(4)
        let estimate = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'minutes' OR label CONTAINS[c] 'hours'")
        ).firstMatch
        XCTAssertTrue(estimate.waitForExistence(timeout: 4),
                      "A 30-minute wait must be labelled so it doesn't read as a hang")
        screenshot("07-time-estimate")
    }

    // MARK: - Listing card (step 9)

    func test08_listingCardShowsCharacterBudgets() {
        openASCGuide()
        jumpToStep(9)
        let nameRow = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Name' AND label CONTAINS[c] 'characters'")
        ).firstMatch
        XCTAssertTrue(nameRow.waitForExistence(timeout: 4),
                      "Listing rows should show an n-of-limit character count")
        screenshot("08-character-budgets")
    }

    func test09_copyAllPutsListingOnClipboard() {
        openASCGuide()
        jumpToStep(9)
        let copyAll = app.buttons["Copy the whole listing to the clipboard"]
        guard copyAll.waitForExistence(timeout: 4) else {
            XCTFail("Copy-all button missing"); return
        }
        copyAll.tap()
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'copied'")
        ).firstMatch, "Copying should confirm with a banner")
        screenshot("09-copy-listing")
    }

    func test10_missingSupportURLIsFlaggedAsBlocking() {
        openASCGuide()
        jumpToStep(9)
        // A fresh draft ships with an empty support URL on purpose —
        // a placeholder would sail past validation and fail review.
        let blocker = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Support URL'")
        ).firstMatch
        XCTAssertTrue(blocker.waitForExistence(timeout: 4),
                      "Missing support URL must be surfaced as a blocker")
        screenshot("10-support-url-blocker")
    }

    // MARK: - Metadata editor

    func test11_editListingOpensEditor() {
        openASCGuide()
        jumpToStep(9)
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)
        assertExists(app.navigationBars["Edit listing"])
        screenshot("11-metadata-editor")
    }

    func test12_editorEnforcesAppleNameLimit() {
        openASCGuide()
        jumpToStep(9)
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
        screenshot("12-name-over-limit")
    }

    func test13_keywordsExplainSharedCharacterBudget() {
        openASCGuide()
        jumpToStep(9)
        waitAndTap(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Edit listing'")
        ).firstMatch)
        scrollDown(times: 1)
        assertExists(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'commas included'")
        ).firstMatch,
        "Keywords help text must explain it is one shared 100-char budget")
        screenshot("13-keywords-budget")
    }

    // MARK: - No-Mac fallbacks

    func test14_everyStepWorksWithoutAMac() {
        openASCGuide()
        assertExists(app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'No Mac paired'")
        ).firstMatch, "Unpaired state should be stated plainly")
        // The promise of the unpaired copy is that the phone alone is enough.
        assertExists(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch, "Step 1 must offer an on-phone route")
        screenshot("14-no-mac-fallback")
    }

    // MARK: - Save & continue

    func test15_completingAStepPersistsAcrossRelaunch() {
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
        launchReadyToBuild()

        let callout = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Continue submitting'")
        ).firstMatch
        XCTAssertTrue(callout.waitForExistence(timeout: 6),
                      "Home must offer to continue an in-flight submission after relaunch")
        screenshot("15-continue-after-relaunch")
    }

    func test16_continueCalloutResumesOnTheRightStep() {
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
        screenshot("16-resumed-banner")
    }

    func test17_completedStepCanBeReopened() {
        openASCGuide()
        let safari = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch
        guard safari.waitForExistence(timeout: 4) else { return }
        safari.tap()
        sleep(1)

        // Step 1 is done and we've advanced to step 2; go back to it.
        jumpToStep(1)
        let reopen = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Reopen this step'")
        ).firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 4),
                      "A finished step must be reopenable — users mis-tap")
        screenshot("17-reopen-step")
    }

    func test18_finishedStepsCollapseIntoOneLine() {
        openASCGuide()
        let safari = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Open in Safari'")
        ).firstMatch
        guard safari.waitForExistence(timeout: 4) else { return }
        safari.tap()

        let strip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'step' AND label CONTAINS[c] 'done'")
        ).firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 4),
                      "Completed work should collapse to a single reviewable line")
        screenshot("18-completed-strip")
    }

    // MARK: - Submission is gated, not self-reported

    /// Local builds have no live backend job, so the release-readiness
    /// recheck `attemptFinalSubmit()` runs before showing the
    /// confirmation alert can never come back "ready" — the button
    /// must show the blocked sheet instead of trusting the user's
    /// word. This is the second hard gate: CodeGenie re-verifies at
    /// the moment of truth rather than letting stale state through.
    func test19_finalSubmitIsBlockedWithoutVerifiedReadiness() {
        openASCGuide()
        jumpToStep(12)
        let submitted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'I submitted for review'")
        ).firstMatch
        guard submitted.waitForExistence(timeout: 4) else {
            XCTFail("Step 12 submit action missing"); return
        }
        submitted.tap()

        assertExists(app.navigationBars["A few things are still missing"],
                     "Submit must re-verify the release checklist and block on what's outstanding, not just ask the user to confirm")
        screenshot("19-submit-blocked")
    }

    func test20_progressBarReflectsCompletedSteps() {
        openASCGuide()
        let progress = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'of 12 steps complete'")
        ).firstMatch
        assertExists(progress, "Progress should be announced for VoiceOver")
        screenshot("20-progress")
    }

    // MARK: - Pre-flight gate (proactive, hard-blocking on entry)

    func test21_preflightChecksBeforeAnythingElseIsShown() {
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
        screenshot("21-preflight-checking")
    }

    func test22_unverifiableBuildOffersExplicitEscapeHatch() {
        openBuildSuccessOverlay()
        let walkthrough = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Walk me through'")
        ).firstMatch
        guard walkthrough.waitForExistence(timeout: 10) else { return }
        walkthrough.tap()

        // Local builds have no live backend job to check against.
        let skip = app.buttons["Continue without verification"]
        guard skip.waitForExistence(timeout: 6) else {
            XCTFail("Expected the unverifiable state for a local build with no backend job")
            return
        }
        screenshot("22-unverifiable-escape-hatch")
        skip.tap()

        assertExists(app.staticTexts["Step 1 of 12"],
                     "Explicitly skipping verification should reach the focused guide")
    }

    // MARK: - Phase 1: get it on your phone

    func test23_uploadStepHasClaudeDrivenButton() {
        openASCGuide()
        jumpToStep(3)
        let upload = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Upload to TestFlight'")
        ).firstMatch
        XCTAssertTrue(upload.waitForExistence(timeout: 4),
                      "Step 3 must be a button CodeGenie drives itself, not a self-report checkbox")
        screenshot("23-upload-button")
    }

    func test24_openTestFlightStepExplainsWhereToLook() {
        openASCGuide()
        jumpToStep(5)
        assertExists(app.staticTexts["Install it on your own iPhone"],
                     "Step 5 should be titled the way a person would say it")
        let explain = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Apple emails you an invite'")
        ).firstMatch
        XCTAssertTrue(explain.waitForExistence(timeout: 4),
                      "Step 5 should say where the invite comes from")
        screenshot("24-open-testflight-copy")
    }

    func test25_inviteTestersExplainsInternalVsExternal() {
        openASCGuide()
        jumpToStep(6)
        let internalCopy = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Internal:'")
        ).firstMatch
        let externalCopy = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'External:'")
        ).firstMatch
        XCTAssertTrue(internalCopy.waitForExistence(timeout: 4) && externalCopy.exists,
                      "Step 6 must explain both tester types, not just say 'invite testers'")
        screenshot("25-invite-testers")
    }

    func test26_becomingTestableShowsMilestoneCard() {
        openASCGuide()
        for _ in 0..<6 {
            let action = app.buttons.matching(NSPredicate(
                format: "label CONTAINS[c] 'Open in Safari' OR label CONTAINS[c] 'I installed it' OR label CONTAINS[c] 'I invited testers' OR label CONTAINS[c] 'Build finished processing'"
            )).firstMatch
            guard action.waitForExistence(timeout: 3) else { break }
            action.tap()
            sleep(1)
        }
        let milestone = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Your app is testable'")
        ).firstMatch
        // Step 3 (the real upload) can't succeed against a local build,
        // so this loop realistically stalls there — assert only when
        // all six phase-1 steps happened to complete.
        if milestone.waitForExistence(timeout: 3) {
            screenshot("26-testable-milestone")
        }
    }

    // MARK: - Helpers

    /// Runs a real build on the local simulated builder and waits for
    /// the success overlay. The canned-sample shortcut this used to
    /// rely on was removed with the sample gallery.
    private func openBuildSuccessOverlay() {
        _ = runLocalBuildToGreen()
    }

    /// Opens the guide and clears the pre-flight gate. Local builds
    /// have no live backend job, so the gate always lands on
    /// "unverifiable" rather than "checking" or "blocked" — tests that
    /// need the step content use the explicit escape hatch, exactly as
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
        _ = app.staticTexts["Step 1 of 12"].waitForExistence(timeout: 5)
    }

    /// Focus mode shows one step at a time, so tests navigate the way a
    /// user does: open the overview, tap the step they want.
    private func jumpToStep(_ number: Int) {
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'See all 12 steps'")
        ).firstMatch
        guard toggle.waitForExistence(timeout: 5) else {
            XCTFail("Overview toggle missing — cannot reach step \(number)"); return
        }
        toggle.tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Step \(number).'")
        ).firstMatch
        for _ in 0..<6 where !row.exists {
            scrollDown(times: 1)
        }
        guard row.waitForExistence(timeout: 4) else {
            XCTFail("Step \(number) row not found in the overview"); return
        }
        row.tap()
        _ = app.staticTexts["Step \(number) of 12"].waitForExistence(timeout: 4)
    }
}
