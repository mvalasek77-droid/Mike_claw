import XCTest

/// Tests the complete first-launch funnel:
/// Splash → 7 onboarding slides → Terms & Privacy → Pricing → Home.
///
/// Run on a fresh simulator with no UserDefaults state.
final class T01_OnboardingFlowTests: CodeGenieTestBase {

    // MARK: - Splash

    func test01_splashAppearsOnColdLaunch() {
        launchFreshInstall()
        assertExists(app.staticTexts["CodeGenie. Ship from your pocket."],
                     "Splash branding should appear on first launch")
        screenshot("01-splash")
    }

    func test02_splashAutoDismisses() {
        launchFreshInstall()
        let onboardingSkip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(onboardingSkip, timeout: 8),
                      "Splash should auto-dismiss into onboarding within 8s")
    }

    // MARK: - The tour

    /// Six stops, one per milestone on Home's rail, then a page that
    /// gathers what the trip needs.
    private let tourPages = 7

    func test03_tourWalksEveryStopInOrder() {
        launchFreshInstall()
        XCTAssertTrue(waitFor(app.buttons["Skip onboarding"], timeout: 8))

        let titles = [
            "Start with a sentence",
            "Watch it get built",
            "Put it on your own iPhone",
            "Test it before anyone else does",
            "Prepare your App Store page",
            "Through Apple's review, and live",
            "What you'll need",
        ]
        for (offset, title) in titles.enumerated() {
            assertExists(app.staticTexts["Slide \(offset + 1) of \(tourPages)"],
                         "Page \(offset + 1) should say where it is")
            assertExists(app.staticTexts[title], "Page \(offset + 1) should be \"\(title)\"")
            screenshot("03-tour-\(offset + 1)")
            if offset < titles.count - 1 { waitAndTap(app.buttons["Next slide"]) }
        }
    }

    func test04_tourEndsWithWhatIsNeededAndAStartButton() {
        launchFreshInstall()
        XCTAssertTrue(waitFor(app.buttons["Skip onboarding"], timeout: 8))
        for _ in 1..<tourPages { waitAndTap(app.buttons["Next slide"]) }

        assertExists(app.staticTexts["What you'll need"], "The tour should end on requirements")
        let cost = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$99'")).firstMatch
        assertExists(cost, "The cost of Apple's programme must be stated before the user starts")
        let mac = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'A Mac with Xcode'")).firstMatch
        assertExists(mac, "So must the need for a Mac")
        assertExists(app.buttons["Start building"], "And it should lead into the app")
    }

    func test05_tourBackButtonWorks() {
        launchFreshInstall()
        XCTAssertTrue(waitFor(app.buttons["Skip onboarding"], timeout: 8))

        waitAndTap(app.buttons["Next slide"])
        assertExists(app.staticTexts["Slide 2 of \(tourPages)"])

        waitAndTap(app.buttons["Previous slide"])
        assertExists(app.staticTexts["Slide 1 of \(tourPages)"],
                     "Back should return to the previous page")
    }

    func test05b_eachStopSaysWhatYouDoAndHowLongItTakes() {
        launchFreshInstall()
        XCTAssertTrue(waitFor(app.buttons["Skip onboarding"], timeout: 8))
        waitAndTap(app.buttons["Next slide"])
        waitAndTap(app.buttons["Next slide"])

        let needs = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Needs: '")).firstMatch
        scrollDown(times: 1)
        assertExists(needs, "The iPhone stop should say it needs a Mac, Xcode and Apple's programme")
        assertExists(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You: '")).firstMatch,
                     "Each stop should say what the user does")
        assertExists(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Takes: '")).firstMatch,
                     "And how long it takes")
    }

    func test05c_theRailJumpsBetweenStops() {
        launchFreshInstall()
        XCTAssertTrue(waitFor(app.buttons["Skip onboarding"], timeout: 8))
        let tested = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tested, stop 4'")).firstMatch
        assertExists(tested, "The rail should name every milestone")
        tested.tap()
        assertExists(app.staticTexts["Test it before anyone else does"],
                     "Tapping a milestone should jump to its page")
    }

    func test06_skipOnboardingJumpsToTerms() {
        launchFreshInstall()
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))

        waitAndTap(skip)

        assertExists(app.staticTexts["Before we start"],
                     "Skipping onboarding should land on Terms")
        screenshot("06-skip-to-terms")
    }

    // MARK: - Terms & Privacy

    func test07_termsRequiresScrollToBottom() {
        launchAfterOnboarding()

        assertExists(app.staticTexts["Before we start"])

        let agreeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'agree'")
        ).firstMatch

        if agreeButton.exists && agreeButton.isEnabled {
            XCTFail("Agree button should be disabled until user scrolls to the bottom")
        }

        scrollDown(times: 8)
        sleep(1)

        XCTAssertTrue(agreeButton.waitForExistence(timeout: 3),
                      "Agree button should appear after scrolling")
        screenshot("07-terms-scrolled")
    }

    func test08_agreeingToTermsLandsOnHome() {
        launchAfterOnboarding()
        assertExists(app.staticTexts["Before we start"])
        scrollDown(times: 8)
        sleep(1)

        let toggle = app.switches.firstMatch
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        let agree = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'agree'")).firstMatch
        guard agree.waitForExistence(timeout: 3) else { XCTFail("Agree button missing"); return }
        agree.tap()

        assertExists(app.buttons["Home"], "Agreeing should land on Home")
        assertExists(app.staticTexts["Describe the app you want"],
                     "And Home should lead with the first step")
        screenshot("08-home-after-terms")
    }

    func test09_fullFunnelFreshInstallToHome() {
        launchFreshInstall()
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))
        waitAndTap(skip)

        assertExists(app.staticTexts["Before we start"])
        scrollDown(times: 8)
        sleep(1)
        let toggle = app.switches.firstMatch
        if toggle.waitForExistence(timeout: 3) { toggle.tap() }
        let agree = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'agree'")).firstMatch
        if agree.waitForExistence(timeout: 3) { agree.tap() }

        assertExists(app.buttons["Home"], "A fresh install should reach Home")
        screenshot("09-full-funnel")
    }

    func test10_theTourCanBeReplayedFromHome() {
        launchOnboarded()
        scrollDown(times: 3)
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'How it works'")).firstMatch
        guard tile.waitForExistence(timeout: 4) else { XCTFail("Tour tile missing"); return }
        tile.tap()
        assertExists(app.staticTexts["Start with a sentence"], "The tour should replay from the start")
        assertExists(app.buttons["Close tutorial"], "And be closable")
    }
}
