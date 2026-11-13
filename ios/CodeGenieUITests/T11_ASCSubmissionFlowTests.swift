import XCTest

/// The guide from a finished build to a live app.
///
/// Four parts: onto the phone (the user works in Xcode on their Mac,
/// following instructions), testing, the store page, and Apple's
/// review. These tests cover the tutorial that opens it, the content
/// of the Xcode steps, the test plan and the gates it puts in front of
/// submission, listing validation, and that progress survives
/// relaunching the app.
final class T11_ASCSubmissionFlowTests: CodeGenieTestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchReadyToBuild()
    }

    private var total: Int { Self.guideStepCount }

    private func text(containing fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    private func button(containing fragment: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", fragment)).firstMatch
    }

    // MARK: - Tutorial

    func test01_guideOpensWithATutorial() {
        openSubmissionGuide(skippingTutorial: false)
        assertExists(app.staticTexts["Here's the whole trip"],
                     "The first thing shown is the shape of the whole process")
        assertExists(app.buttons["Next"], "The tutorial should be paged")
        screenshot("01-tutorial-overview")
    }

    func test02_tutorialSaysWhatIsNeededAndThatTestingIsRequired() {
        openSubmissionGuide(skippingTutorial: false)
        let next = app.buttons["Next"]
        guard next.waitForExistence(timeout: 6) else { XCTFail("Tutorial missing"); return }
        next.tap()
        assertExists(app.staticTexts["What you'll need"], "Requirements come before step one")
        assertExists(text(containing: "$99"), "The cost of Apple's program must be stated up front")
        next.tap()
        assertExists(text(containing: "You'll use Xcode yourself"), "The Mac part is the user's, and says so")
        next.tap()
        assertExists(app.staticTexts["Testing is not optional"], "Testing is introduced before the user starts")
        screenshot("02-tutorial-testing")
        next.tap()
        assertExists(app.buttons["Start with step 1"], "The last page leads into the guide")
    }

    func test03_tutorialCanBeReplayed() {
        openSubmissionGuide()
        let help = app.buttons["How this works"]
        assertExists(help, "The tutorial should stay one tap away")
        help.tap()
        assertExists(app.staticTexts["Here's the whole trip"], "It should replay from the start")
    }

    func test04_tutorialIsNotShownTwice() {
        openSubmissionGuide()
        app.buttons["Close submission guide"].tap()
        let resume = app.buttons["journey.primaryAction"]
        if resume.waitForExistence(timeout: 4) { resume.tap() }
        XCTAssertFalse(app.staticTexts["Here's the whole trip"].waitForExistence(timeout: 2),
                       "Once seen, the tutorial should not interrupt again")
    }

    // MARK: - Structure

    func test05_guideOpensOnASingleFocusedStep() {
        openSubmissionGuide()
        assertExists(app.staticTexts["Step 1 of \(total)"], "The guide should open on step 1")
        assertExists(app.staticTexts["Get your project onto your Mac"], "The step's plain-English title")
        XCTAssertFalse(app.staticTexts["Step 9 of \(total)"].exists, "Later steps stay out of sight")
        screenshot("05-focused-step")
    }

    func test06_everyStepSaysWhereItHappens() {
        openSubmissionGuide()
        assertExists(text(containing: "On this iPhone"), "Step 1 happens on the phone")
        jumpToGuideStep(2)
        assertExists(text(containing: "In Xcode on your Mac"), "Step 2 happens in Xcode")
        jumpToGuideStep(5)
        assertExists(text(containing: "On Apple's website"), "Step 5 happens on the web")
    }

    func test07_overviewListsFourParts() {
        openSubmissionGuide()
        let overview = button(containing: "See all \(total) steps")
        scrollDown(times: 4)
        guard overview.waitForExistence(timeout: 3) else { XCTFail("Overview toggle missing"); return }
        overview.tap()
        for part in [
            "Part 1 — Get it on your phone",
            "Part 2 — Test it properly",
            "Part 3 — Put it on the App Store",
            "Part 4 — Through Apple's review",
        ] {
            let header = app.staticTexts[part]
            var tries = 0
            while !header.exists && tries < 8 { app.swipeUp(); tries += 1 }
            assertExists(header, "\(part) should be listed")
        }
        screenshot("07-four-parts")
    }

    func test08_stepsGiveLiteralInstructionsAWarningAndATime() {
        openSubmissionGuide()
        assertExists(app.staticTexts["Do this"], "Every step lists what to do")
        scrollDown(times: 1)
        assertExists(text(containing: "Where people get stuck"), "Every step names its common snag")
        assertExists(text(containing: "AirDrop"), "Step 1 should say how the project gets to the Mac")
        screenshot("08-instructions")
    }

    // MARK: - The Mac part, by hand

    func test09_projectIsPreparedThenSharedNotSentToAHelperApp() {
        openSubmissionGuide()
        scrollDown(times: 2)
        assertExists(app.buttons["Get the project ready to send"],
                     "Step 1 packs the project so it can be shared to the Mac")
        XCTAssertFalse(button(containing: "Pair").exists, "There is no helper app to pair with")
        XCTAssertFalse(button(containing: "Open on my Mac").exists,
                       "CodeGenie cannot open things on the Mac and must not offer to")
        screenshot("09-transfer")
    }

    func test10_xcodeStepTellsTheUserWhichFileToOpen() {
        openSubmissionGuide()
        jumpToGuideStep(2)
        assertExists(app.staticTexts["Open your project in Xcode"], "Step 2 is opening Xcode")
        assertExists(text(containing: ".xcodeproj"), "It must name the file to double-click")
        scrollDown(times: 3)
        assertExists(app.buttons["Done in Xcode"], "The user reports back when it worked")
        assertExists(app.buttons["It showed an error"], "And has somewhere to go when it didn't")
        screenshot("10-open-in-xcode")
    }

    func test11_anXcodeErrorLeadsStraightToTheCoach() {
        openSubmissionGuide()
        jumpToGuideStep(3)
        scrollDown(times: 3)
        let error = app.buttons["It showed an error"]
        guard error.waitForExistence(timeout: 4) else { XCTFail("Error button missing"); return }
        error.tap()
        assertExists(app.navigationBars["Ask about submitting"],
                     "An error in Xcode should open the coach, on that step")
        assertExists(button(containing: "Personal Team"),
                     "The coach should offer the questions people have at this step")
        screenshot("11-error-to-coach")
    }

    func test12_signingStepShowsTheBundleIDToCompare() {
        openSubmissionGuide()
        jumpToGuideStep(3)
        assertExists(text(containing: "Signing & Capabilities"), "It must name the tab")
        scrollDown(times: 2)
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Copy com.'")).firstMatch
        assertExists(chip, "The exact bundle ID should be shown and copyable")
        screenshot("12-signing")
    }

    func test13_runStepOffersARebuildWhenItWontCompile() {
        openSubmissionGuide()
        jumpToGuideStep(4)
        assertExists(app.staticTexts["See it run"], "Step 4 runs the app in the Simulator")
        scrollDown(times: 3)
        assertExists(button(containing: "rebuild it"),
                     "A project that won't build must have a way forward that isn't editing code")
    }

    func test14_archiveStepNamesTheMenuItems() {
        openSubmissionGuide()
        jumpToGuideStep(6)
        assertExists(app.staticTexts["Send your app to Apple"], "Step 6 is the upload")
        assertExists(text(containing: "Any iOS Device"), "It must say which destination to pick")
        scrollDown(times: 2)
        assertExists(text(containing: "Distribute App"), "And which button uploads")
        scrollDown(times: 2)
        assertExists(app.buttons["Xcode says the upload finished"], "The user confirms what Xcode reported")
        screenshot("14-archive")
    }

    func test15_appRecordStepOffersLinksAndExactValues() {
        openSubmissionGuide()
        jumpToGuideStep(5)
        assertExists(app.staticTexts["Tell Apple your app exists"], "Step 5 creates the record")
        scrollDown(times: 1)
        assertExists(app.links.matching(NSPredicate(format: "label CONTAINS[c] 'Open this page'")).firstMatch,
                     "Addresses in the steps should be tappable")
        screenshot("15-app-record")
    }

    // MARK: - Progress is kept

    func test16_completingAStepSurvivesRelaunch() {
        openSubmissionGuide()
        jumpToGuideStep(2)
        scrollDown(times: 3)
        let done = app.buttons["Done in Xcode"]
        guard done.waitForExistence(timeout: 4) else { XCTFail("Step 2 action missing"); return }
        done.tap()

        app.terminate()
        launchReadyToBuild()
        assertExists(text(containing: "step 1 of \(total)"),
                     "Home should offer to continue, on the first unfinished step")
        app.buttons["journey.primaryAction"].tap()
        let carryOn = app.buttons["Continue without verification"]
        if carryOn.waitForExistence(timeout: 6) { carryOn.tap() }
        assertExists(text(containing: "1 step done"), "The finished step should still be finished")
        screenshot("16-resumed")
    }

    func test17_aFinishedStepCanBeReopened() {
        openSubmissionGuide()
        jumpToGuideStep(2)
        scrollDown(times: 3)
        app.buttons["Done in Xcode"].tap()
        jumpToGuideStep(2)
        scrollDown(times: 4)
        assertExists(app.buttons["Reopen this step"], "A mis-tap should be undoable")
    }

    // MARK: - Testing

    func test18_testPlanIsWrittenOutWithWhatToDoAndExpect() {
        openSubmissionGuide()
        jumpToGuideStep(9)
        assertExists(app.staticTexts["Find out whether it actually works"], "Step 9 is testing")
        scrollDown(times: 3)
        assertExists(text(containing: "required test"), "The plan should say how much is left")
        var tries = 0
        let first = button(containing: "Open it for the very first time")
        while !first.exists && tries < 6 { app.swipeUp(); tries += 1 }
        assertExists(first, "The plan starts with a fresh install")
        assertExists(text(containing: "You should see"), "Each test states its expected result")
        assertExists(text(containing: "Why it matters"), "And why it is worth doing")
        screenshot("18-test-plan")
    }

    func test19_testingExplainsWhyItMatters() {
        openSubmissionGuide()
        jumpToGuideStep(9)
        assertExists(text(containing: "written by AI"),
                     "The user should be told plainly why an untested build can't be trusted")
        scrollDown(times: 2)
        assertExists(text(containing: "Be strict"), "And how to judge a result")
    }

    func test20_aFailedTestAsksWhatHappened() {
        openSubmissionGuide()
        jumpToGuideStep(9)
        var tries = 0
        let failed = app.buttons["Didn't work"]
        while !failed.exists && tries < 8 { app.swipeUp(); tries += 1 }
        guard failed.exists else { XCTFail("Verdict buttons missing"); return }
        failed.tap()
        assertExists(app.staticTexts["What happened?"], "A failure should ask for one line about it")
        scrollUp(times: 4)
        assertExists(text(containing: "1 test failed"), "The summary should reflect the failure")
        screenshot("20-failed-test")
    }

    func test21_theTestStepCannotBeTickedByHand() {
        openSubmissionGuide()
        jumpToGuideStep(9)
        scrollDown(times: 2)
        XCTAssertFalse(app.buttons["I did this"].exists, "Testing is finished by results, not a tap")
        assertExists(text(containing: "completes itself when every required test"),
                     "And the step should say so")
    }

    func test22_theVerdictStaysClosedUntilTestsAreTried() {
        openSubmissionGuide()
        jumpToGuideStep(11)
        assertExists(app.staticTexts["Decide: ready, or rebuild?"], "Step 11 is the checkpoint")
        scrollDown(times: 3)
        assertExists(app.buttons["Back to the test plan"], "With nothing tested there is nothing to decide")
        XCTAssertFalse(button(containing: "It's ready").exists, "It can't be declared ready untested")
        screenshot("22-verdict-closed")
    }

    func test23_secondTesterStepExplainsWhyAnOutsiderMatters() {
        openSubmissionGuide()
        jumpToGuideStep(10)
        assertExists(app.staticTexts["Watch someone else use it"], "Step 10 brings in another person")
        assertExists(text(containing: "you know where to tap"), "It should say why you can't do this yourself")
    }

    // MARK: - The store page

    func test24_listingShowsBudgetsAndRequiredFields() {
        openSubmissionGuide()
        jumpToGuideStep(14)
        scrollDown(times: 3)
        assertExists(text(containing: "/30"), "Name and subtitle show Apple's 30-character budget")
        assertExists(text(containing: "Privacy policy"), "Apple requires a privacy policy URL for every app")
        assertExists(text(containing: "Copyright"), "Copyright is required on the version page")
        screenshot("24-listing")
    }

    func test25_anIncompleteListingIsFlaggedAndEditable() {
        openSubmissionGuide()
        jumpToGuideStep(14)
        scrollDown(times: 3)
        assertExists(text(containing: "Apple will reject"), "Missing required fields must be flagged")
        let edit = app.buttons["Edit listing"]
        guard edit.waitForExistence(timeout: 3) else { XCTFail("Edit listing missing"); return }
        edit.tap()
        assertExists(app.navigationBars["Edit listing"], "The editor should open")
        screenshot("25-editor")
    }

    func test26_storeStepsCoverAgeRatingAndReviewNotes() {
        openSubmissionGuide()
        jumpToGuideStep(16)
        assertExists(app.staticTexts["Tell Apple who the app is suitable for"], "Age rating has its own step")
        jumpToGuideStep(18)
        assertExists(app.staticTexts["Give the reviewer what they need"], "So do the reviewer's notes")
        scrollDown(times: 3)
        assertExists(app.staticTexts["Notes for the reviewer"], "With an editable draft")
        assertExists(text(containing: "still to fill in"), "That says which blanks remain")
    }

    // MARK: - Submitting

    func test27_submitIsRefusedWhileTestingIsUnfinished() {
        openSubmissionGuide()
        jumpToGuideStep(20)
        scrollDown(times: 3)
        let submitted = app.buttons["I submitted for review"]
        guard submitted.waitForExistence(timeout: 4) else { XCTFail("Submit action missing"); return }
        submitted.tap()

        XCTAssertFalse(app.alerts["Did you press Submit in App Store Connect?"].waitForExistence(timeout: 2),
                       "The confirmation must not appear for an untested app")
        assertExists(app.staticTexts["Step 9 of \(total)"],
                     "The user should be taken to the test plan instead")
        assertExists(text(containing: "Testing isn't finished"), "And told why")
        screenshot("27-submit-refused")
    }

    // MARK: - Review

    func test28_reviewStepsOfferNothingBeforeSubmission() {
        openSubmissionGuide()
        jumpToGuideStep(21)
        assertExists(app.staticTexts["Wait for a reviewer"], "The queue step explains itself")
        scrollDown(times: 3)
        assertExists(app.staticTexts["Nothing to track yet"],
                     "Status controls must not be offered for an app that hasn't been submitted")
        XCTAssertFalse(app.buttons["Check with Apple"].exists, "No status check before a submission")
    }

    func test29_reviewStepsAreNeverTickedByHand() {
        openSubmissionGuide()
        jumpToGuideStep(22)
        assertExists(app.staticTexts["Act on Apple's answer"], "The decision step explains itself")
        scrollDown(times: 2)
        XCTAssertFalse(app.buttons["I did this"].exists, "A review step follows Apple's status")
    }

    // MARK: - Help on every step

    func test30_everyStepOffersTheCoach() {
        openSubmissionGuide()
        for step in [1, 6, 9, 14, 20] {
            jumpToGuideStep(step)
            var tries = 0
            let ask = app.buttons["Stuck on this step? Ask the coach"]
            while !ask.exists && tries < 8 { app.swipeUp(); tries += 1 }
            assertExists(ask, "Step \(step) should offer the coach")
        }
    }

    func test31_progressHeaderNamesThePart() {
        openSubmissionGuide()
        assertExists(text(containing: "Part 1 of 4"), "The header should say which part this is")
        assertExists(text(containing: "0 of \(total) complete"), "And how far along")
    }
}
