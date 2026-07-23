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

    // MARK: - Onboarding slides

    func test03_onboardingShowsAllSevenSlides() {
        launchFreshInstall()
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))

        for i in 1...7 {
            let slideLabel = "Slide \(i) of 7"
            assertExists(app.otherElements[slideLabel],
                         "Slide \(i) should be visible")
            screenshot("03-onboarding-slide-\(i)")
            if i < 7 {
                waitAndTap(app.buttons["Next slide"])
            }
        }
    }

    func test04_onboardingLastSlideShowsGetStarted() {
        launchFreshInstall()
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))

        for _ in 1..<7 {
            waitAndTap(app.buttons["Next slide"])
        }

        let getStarted = app.buttons.matching(NSPredicate(format: "label CONTAINS 'started'")).firstMatch
        assertExists(getStarted, "Last slide should show a 'Get started' CTA")
    }

    func test05_onboardingBackButtonWorks() {
        launchFreshInstall()
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))

        waitAndTap(app.buttons["Next slide"])
        assertExists(app.otherElements["Slide 2 of 7"])

        waitAndTap(app.buttons["Previous slide"])
        assertExists(app.otherElements["Slide 1 of 7"],
                     "Back button should return to the previous slide")
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

    func test08_termsAdvancesToPricing() {
        launchAfterOnboarding()

        assertExists(app.staticTexts["Before we start"])
        scrollDown(times: 8)
        sleep(1)

        let agreeButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'agree'")
        ).firstMatch
        waitAndTap(agreeButton, timeout: 3)

        assertExists(app.staticTexts["Pick how you'll pay"],
                     "Accepting terms should show the pricing chooser")
        screenshot("08-pricing-view")
    }

    // MARK: - Pricing chooser

    func test09_pricingShowsTwoPlans() {
        launchAfterTerms()

        assertExists(app.staticTexts["Pick how you'll pay"])

        let hosted = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'CodeGenie Hosted'")
        ).firstMatch
        let byok = app.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] 'Bring your own key'")
        ).firstMatch

        assertExists(hosted, "CodeGenie Hosted plan card should exist")
        assertExists(byok, "BYOK plan card should exist")
        screenshot("09-pricing-two-plans")
    }

    func test10_pricingHostedPathLeadsToHome() {
        launchAfterTerms()

        let startHosted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start with free hosted'")
        ).firstMatch
        waitAndTap(startHosted)

        assertExists(app.buttons["Home"],
                     "Choosing hosted should land on the main tab bar")
        screenshot("10-home-after-hosted")
    }

    func test11_pricingBYOKPathLeadsToHome() {
        launchAfterTerms()

        scrollDown(times: 2)

        let byokButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Use my own key'")
        ).firstMatch
        if byokButton.waitForExistence(timeout: 3) {
            byokButton.tap()
        } else {
            let byokCard = app.otherElements.matching(
                NSPredicate(format: "label CONTAINS[c] 'Bring your own key'")
            ).firstMatch
            waitAndTap(byokCard)
        }

        assertExists(app.buttons["Home"],
                     "Choosing BYOK should land on the main tab bar")
    }

    func test12_pricingLaterEscapeLeadsToHome() {
        launchAfterTerms()

        scrollDown(times: 3)

        let later = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'later' OR label CONTAINS[c] 'decide later'")
        ).firstMatch
        if later.waitForExistence(timeout: 3) {
            later.tap()
            assertExists(app.buttons["Home"],
                         "'Decide later' should also land on Home")
        }
    }

    // MARK: - Full funnel end-to-end

    func test13_fullFunnelFreshInstallToHome() {
        launchFreshInstall()

        // 1. Wait for splash to dismiss
        let skip = app.buttons["Skip onboarding"]
        XCTAssertTrue(waitFor(skip, timeout: 8))

        // 2. Skip onboarding
        skip.tap()

        // 3. Terms — scroll and agree
        assertExists(app.staticTexts["Before we start"])
        scrollDown(times: 8)
        sleep(1)
        let agree = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'agree'")
        ).firstMatch
        waitAndTap(agree, timeout: 3)

        // 4. Pricing — pick hosted
        assertExists(app.staticTexts["Pick how you'll pay"])
        let hosted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start with free hosted'")
        ).firstMatch
        waitAndTap(hosted)

        // 5. Home
        assertExists(app.buttons["Home"])
        screenshot("13-full-funnel-complete")
    }
}
