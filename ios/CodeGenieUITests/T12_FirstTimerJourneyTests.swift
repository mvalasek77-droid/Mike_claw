import XCTest

/// The path someone takes who has never built an app: no API key, no
/// Mac, no Apple account, no idea what any of those are. Every test
/// here is a place that path used to end in a dead end.
final class T12_FirstTimerJourneyTests: CodeGenieTestBase {

    /// Onboarded, but with nothing set up — the default payment mode
    /// and no key, exactly as a new install is.
    private func launchWithNothingSetUp(keepDrafts: Bool = false) {
        app.launchArguments += [
            "-hasFinishedOnboarding", "true",
            "-hasAcceptedTerms", "true",
            "-auth.mode", "byok",
        ]
        if keepDrafts { app.launchArguments += ["-keepDrafts"] }
        app.launch()
    }

    private func openDescribeForm() {
        let next = app.buttons["journey.primaryAction"]
        XCTAssertTrue(next.waitForExistence(timeout: 6), "Home should offer a next step")
        next.tap()
        let buildFirst = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build my app first'")
        ).firstMatch
        if buildFirst.waitForExistence(timeout: 3) { buildFirst.tap() }
        XCTAssertTrue(app.staticTexts["Describe your app"].waitForExistence(timeout: 5))
    }

    private func typeDescription(_ text: String) {
        let prompt = app.textViews["App description"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 4))
        prompt.tap()
        prompt.typeText(text)
    }

    // MARK: - Home

    func test01_aNewUserIsToldToBuildBeforeSettingAnythingUp() {
        launchWithNothingSetUp()
        assertExists(app.staticTexts["Describe the app you want"],
                     "The first thing asked of a newcomer is an idea, not an install")
        app.buttons["journey.primaryAction"].tap()
        let buildFirst = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Build my app first'")
        ).firstMatch
        assertExists(buildFirst, "Building first should be the leading choice")
        screenshot("01-build-first")
    }

    // MARK: - The API key

    func test02_withoutAKeyTheFormSaysWhyAndOffersTheWayForward() {
        launchWithNothingSetUp()
        openDescribeForm()
        typeDescription("A tide times app for surfers with a clean look")
        app.swipeUp()

        assertExists(app.staticTexts["Can't build yet"],
                     "A blocked build must say it is blocked")
        let addKey = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Add my' AND label CONTAINS[c] 'key'")
        ).firstMatch
        assertExists(addKey, "The fix must be one tap from where the problem is shown")
        screenshot("02-blocked-with-a-way-forward")
    }

    func test03_keySetupExplainsWhatAKeyIsAndWhereToGetOne() {
        launchWithNothingSetUp()
        openDescribeForm()
        typeDescription("A tide times app for surfers with a clean look")
        app.swipeUp()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Add my' AND label CONTAINS[c] 'key'")
        ).firstMatch.tap()

        assertExists(app.staticTexts["What's an API key?"],
                     "Someone who has never seen one needs it explained")
        let console = app.links.matching(
            NSPredicate(format: "label CONTAINS[c] 'console'")
        ).firstMatch
        assertExists(console, "There must be a link to where a key comes from")
        let save = app.buttons["Save and check"]
        assertExists(save, "The key should be checked, not just stored")
        XCTAssertFalse(save.isEnabled, "An empty key can't be saved")
        screenshot("03-key-setup")
    }

    func test04_aWrongKindOfKeyIsCaughtBeforeItIsSaved() {
        launchWithNothingSetUp()
        openDescribeForm()
        typeDescription("A tide times app for surfers with a clean look")
        app.swipeUp()
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Add my' AND label CONTAINS[c] 'key'")
        ).firstMatch.tap()

        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        field.typeText("too-short")
        let warning = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'too short'")
        ).firstMatch
        assertExists(warning, "A truncated paste should be named as one")
        XCTAssertFalse(app.buttons["Save and check"].isEnabled)
        screenshot("04-bad-key-caught")
    }

    func test05_leavingToGetAKeyDoesNotLoseWhatWasTyped() {
        launchWithNothingSetUp()
        openDescribeForm()
        typeDescription("A tide times app for surfers")
        app.terminate()

        app = XCUIApplication()
        app.launchArguments += ["-UITests"]
        launchWithNothingSetUp(keepDrafts: true)
        openDescribeForm()
        let prompt = app.textViews["App description"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 4))
        XCTAssertTrue((prompt.value as? String ?? "").contains("tide times"),
                      "The description should survive leaving the app to fetch a key")
        screenshot("05-draft-kept")
    }

    func test06_aTooShortDescriptionSaysWhatIsMissing() {
        launchWithNothingSetUp()
        openDescribeForm()
        typeDescription("tides")
        app.swipeUp()
        let hint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'few more words'")
        ).firstMatch
        assertExists(hint, "A disabled button needs a visible reason")
    }

    // MARK: - After the build

    func test07_theSuccessScreenHasOneNextStepAndAWayOut() {
        launchReadyToBuild()
        XCTAssertTrue(runLocalBuildToGreen(), "The stand-in build should finish")

        assertExists(app.buttons["Put it on my iPhone"], "One clear next step")
        assertExists(app.buttons["See what was built"], "A way to look at the result")
        let done = app.buttons["Done for now"]
        assertExists(done, "A way to leave without choosing anything")
        XCTAssertFalse(app.buttons["Upload build to TestFlight"].exists,
                       "The upload belongs in the guide, behind its checks")
        screenshot("07-success")

        done.tap()
        assertExists(app.buttons["journey.primaryAction"], "Done should return to Home")
    }

    func test08_afterABuildHomePointsAtTheNextRealStep() {
        launchReadyToBuild()
        XCTAssertTrue(runLocalBuildToGreen())
        app.buttons["Done for now"].tap()

        let setUp = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Get ready to install'")
        ).firstMatch
        assertExists(setUp, "With an app built and nothing set up, the next step is setup — named, not implied")
        let needs = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'a paired Mac'")
        ).firstMatch
        assertExists(needs, "It should say exactly what is missing")
        screenshot("08-home-after-build")
    }

    func test09_theBuiltAppScreenIsHonestAboutWhatItCanShow() {
        launchReadyToBuild()
        XCTAssertTrue(runLocalBuildToGreen())
        app.buttons["See what was built"].tap()

        assertExists(app.staticTexts["This is your app"], "The screen should open")
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Streaming live'")).firstMatch.exists,
            "There is no live preview and the app must not pretend there is"
        )
        assertExists(app.buttons["Put it on my iPhone"], "The real way to run it should be offered")
        screenshot("09-built-app")
    }

    // MARK: - The upload without a Mac

    func test10_uploadingWithoutAMacExplainsAndOffersPairing() {
        launchReadyToBuild()
        XCTAssertTrue(runLocalBuildToGreen())
        app.buttons["Put it on my iPhone"].tap()
        let skip = app.buttons["Continue without verification"]
        if skip.waitForExistence(timeout: 6) { skip.tap() }

        let noMac = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'No Mac paired'")
        ).firstMatch
        scrollDown(times: 3)
        assertExists(noMac, "The guide should say plainly that no Mac is paired")
        screenshot("10-no-mac")
    }

    // MARK: - Registering the app ID

    func test11_creatingTheAppRecordStartsWithRegisteringItsID() {
        launchReadyToBuild()
        XCTAssertTrue(runLocalBuildToGreen())
        app.buttons["Put it on my iPhone"].tap()
        let skip = app.buttons["Continue without verification"]
        if skip.waitForExistence(timeout: 6) { skip.tap() }

        let overview = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'See all 18 steps'")
        ).firstMatch
        scrollDown(times: 4)
        if overview.waitForExistence(timeout: 3) { overview.tap() }
        let stepTwo = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Step 2.'")
        ).firstMatch
        if stepTwo.waitForExistence(timeout: 3) { stepTwo.tap() }

        let register = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Identifiers page'")
        ).firstMatch
        assertExists(register, "The ID has to be registered before it can be picked, and the step must say so")
        screenshot("11-register-id")
    }
}
