import XCTest
@testable import CodeGenieLogic

final class TestPlanTests: XCTestCase {

    private func app(
        _ category: AppDescription.Category = .utility,
        prompt: String = "Tide tables for surfers",
        features: [String] = ["Pick a beach", "See today's tides"]
    ) -> AppDescription {
        AppDescription(title: "Tide Times", prompt: prompt, category: category, features: features)
    }

    func testIDsAreUniqueAndStable() {
        let plan = TestPlan.make(for: app())
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertEqual(plan.map(\.id), TestPlan.make(for: app()).map(\.id), "results are keyed by id across launches")
    }

    func testEveryTestSaysWhatToDoWhatToExpectAndWhy() {
        for category in AppDescription.Category.allCases {
            for test in TestPlan.make(for: app(category), requiresLogin: true) {
                XCTAssertGreaterThan(test.how.count, 20, test.id)
                XCTAssertGreaterThan(test.expect.count, 20, test.id)
                XCTAssertGreaterThan(test.why.count, 20, test.id)
            }
        }
    }

    func testTheBasicsAreAlwaysRequired() {
        let required = Set(TestPlan.make(for: app(features: [])).filter(\.required).map(\.id))
        XCTAssertTrue(required.isSuperset(of: ["first_launch", "main_task", "every_button", "quit_relaunch", "no_network", "no_placeholder"]))
    }

    func testThePlanIsWrittenForThisApp() {
        let plan = TestPlan.make(for: app())
        XCTAssertTrue(plan.contains { $0.title == "Try: Pick a beach" && $0.required })
        XCTAssertTrue(plan.contains { $0.title == "Try: See today's tides" })
        XCTAssertTrue(plan.first { $0.id == "first_launch" }!.how.contains("Tide Times"))
    }

    func testFeatureListIsBoundedAndBlankOnesDropped() {
        let many = (1...20).map { "Feature \($0)" } + ["  ", ""]
        let plan = TestPlan.make(for: app(features: many))
        XCTAssertEqual(plan.filter { $0.id.hasPrefix("feature_") }.count, 6)
    }

    func testLoginAppsMustProveTheReviewAccountWorks() {
        XCTAssertFalse(TestPlan.make(for: app()).contains { $0.id == "login" })
        let login = TestPlan.make(for: app(), requiresLogin: true).first { $0.id == "login" }
        XCTAssertEqual(login?.required, true)
    }

    func testPermissionRefusalIsTestedOnlyWhereItApplies() {
        XCTAssertFalse(TestPlan.make(for: app()).contains { $0.id == "permission_denied" })
        XCTAssertTrue(TestPlan.make(for: app(.photo)).contains { $0.id == "permission_denied" })
        XCTAssertTrue(TestPlan.make(for: app(prompt: "Remind me with a notification at high tide")).contains { $0.id == "permission_denied" })
        XCTAssertTrue(TestPlan.make(for: app(features: ["Show beaches on a map"])).contains { $0.id == "permission_denied" })
    }

    func testAnUntitledAppStillGetsAReadablePlan() {
        let plan = TestPlan.make(for: AppDescription(title: "  ", prompt: ""))
        XCTAssertTrue(plan.first { $0.id == "first_launch" }!.how.contains("your app"))
        XCTAssertGreaterThanOrEqual(plan.count, 8)
    }

    func testEveryAreaIsRepresented() {
        let areas = Set(TestPlan.make(for: app()).map(\.area))
        XCTAssertEqual(areas, Set(TestCase.Area.allCases))
    }

    // MARK: Summaries

    func testNothingTriedIsNeitherCompleteNorPassing() {
        let plan = TestPlan.make(for: app())
        let summary = TestPlan.summary(of: plan, results: [:])
        XCTAssertEqual(summary.done, 0)
        XCTAssertFalse(summary.isComplete)
        XCTAssertFalse(summary.isPassing)
        XCTAssertEqual(summary.requiredRemaining, plan.filter(\.required).count)
        XCTAssertTrue(summary.headline.contains("to go"))
    }

    func testRequiredPassesAreEnoughButOptionalOnesAreStillCounted() {
        let plan = TestPlan.make(for: app())
        var results: [String: TestResult] = [:]
        for test in plan where test.required { results[test.id] = TestResult(outcome: .passed) }
        let summary = TestPlan.summary(of: plan, results: results)
        XCTAssertTrue(summary.isPassing)
        XCTAssertGreaterThan(summary.optionalRemaining, 0)
        XCTAssertEqual(summary.headline, "Required tests passed")
    }

    func testOneFailureMeansNotPassingAndLeadsTheHeadline() {
        let plan = TestPlan.make(for: app())
        var results: [String: TestResult] = [:]
        for test in plan { results[test.id] = TestResult(outcome: .passed) }
        XCTAssertEqual(TestPlan.summary(of: plan, results: results).headline, "Every test passed")
        results["dark_mode"] = TestResult(outcome: .failed)
        let summary = TestPlan.summary(of: plan, results: results)
        XCTAssertTrue(summary.isComplete)
        XCTAssertFalse(summary.isPassing)
        XCTAssertEqual(summary.headline, "1 test failed")
    }

    func testResultsForTestsNoLongerInThePlanAreIgnored() {
        let plan = TestPlan.make(for: app())
        let summary = TestPlan.summary(of: plan, results: ["retired": TestResult(outcome: .failed)])
        XCTAssertEqual(summary.failed, 0)
    }

    func testNextPrefersRequiredTests() {
        let plan = TestPlan.make(for: app())
        XCTAssertEqual(TestPlan.next(in: plan, results: [:])?.id, "first_launch")
        var results: [String: TestResult] = [:]
        for test in plan where test.required { results[test.id] = TestResult(outcome: .passed) }
        XCTAssertEqual(TestPlan.next(in: plan, results: results)?.required, false)
        for test in plan { results[test.id] = TestResult(outcome: .passed) }
        XCTAssertNil(TestPlan.next(in: plan, results: results))
    }

    // MARK: Turning failures into the next build

    func testNoFailuresMeansNoBrief() {
        let plan = TestPlan.make(for: app())
        XCTAssertNil(TestPlan.fixBrief(for: plan, results: [:]))
        XCTAssertNil(TestPlan.fixBrief(for: plan, results: ["main_task": TestResult(outcome: .passed)]))
    }

    func testTheBriefCarriesWhatWasExpectedAndWhatHappened() throws {
        let plan = TestPlan.make(for: app())
        let brief = try XCTUnwrap(TestPlan.fixBrief(for: plan, results: [
            "no_network": TestResult(outcome: .failed, note: "spinner forever"),
            "main_task": TestResult(outcome: .failed),
            "first_launch": TestResult(outcome: .passed),
        ]))
        XCTAssertTrue(brief.contains("Use it with no internet"))
        XCTAssertTrue(brief.contains("What happened instead: spinner forever"))
        XCTAssertTrue(brief.contains("Do the one thing the app is for"))
        XCTAssertFalse(brief.contains("Open it for the very first time"), "passes are not problems")
        XCTAssertEqual(brief.components(separatedBy: "\n- ").count - 1, 2)
    }

    func testBlankNotesAreTreatedAsNoNote() {
        XCTAssertNil(TestResult(outcome: .failed, note: "   ").note)
        XCTAssertNil(TestResult(outcome: .failed, note: nil).note)
        XCTAssertEqual(TestResult(outcome: .failed, note: " x ").note, "x")
    }

    // MARK: Feeding the submission checklist

    func testPassedTestsSettleTheMatchingChecklistItems() {
        let plan = TestPlan.make(for: app())
        var results: [String: TestResult] = [:]
        XCTAssertEqual(SubmissionChecklist.satisfiedByTesting(plan: plan, results: results), ["demo_account"],
                       "no login means nothing to hand the reviewer")
        results["first_launch"] = TestResult(outcome: .passed)
        XCTAssertFalse(SubmissionChecklist.satisfiedByTesting(plan: plan, results: results).contains("runs_on_device"))
        results["main_task"] = TestResult(outcome: .passed)
        results["every_button"] = TestResult(outcome: .passed)
        results["no_placeholder"] = TestResult(outcome: .failed)
        let settled = SubmissionChecklist.satisfiedByTesting(plan: plan, results: results)
        XCTAssertTrue(settled.isSuperset(of: ["runs_on_device", "no_broken_links"]))
        XCTAssertFalse(settled.contains("no_placeholder"))
    }

    func testALoginAppMustPassTheLoginTestToSettleTheDemoAccount() {
        let plan = TestPlan.make(for: app(), requiresLogin: true)
        XCTAssertFalse(SubmissionChecklist.satisfiedByTesting(plan: plan, results: [:]).contains("demo_account"))
        XCTAssertTrue(SubmissionChecklist.satisfiedByTesting(
            plan: plan, results: ["login": TestResult(outcome: .passed)]
        ).contains("demo_account"))
    }

    func testEverySettledItemIsARealChecklistItem() {
        let plan = TestPlan.make(for: app())
        var results: [String: TestResult] = [:]
        for test in plan { results[test.id] = TestResult(outcome: .passed) }
        let known = Set(SubmissionChecklist.all.map(\.id))
        XCTAssertTrue(SubmissionChecklist.satisfiedByTesting(plan: plan, results: results).isSubset(of: known))
    }
}

final class GuideContentTests: XCTestCase {

    func testTutorialCoversWhatAFirstTimerMustKnowBeforeStarting() {
        let pages = SubmissionTutorial.pages(appName: "Tide Times")
        XCTAssertEqual(Set(pages.map(\.id)).count, pages.count)
        let text = pages.flatMap { [$0.title, $0.body] + $0.points }.joined(separator: " ")
        for needle in ["Mac", "Xcode", "$99", "Tide Times", "test plan", "coach", "rejects"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        for page in pages { XCTAssertGreaterThanOrEqual(page.points.count, 3, page.id) }
    }

    func testTutorialStepCountsMatchTheRealGuide() {
        let overview = SubmissionTutorial.pages(appName: "T").first { $0.id == "overview" }!
        XCTAssertEqual(overview.points.count, ASCPhase.allCases.count)
        for phase in ASCPhase.allCases {
            let count = ASCStep.steps(in: phase).count
            XCTAssertTrue(overview.points.contains { $0.contains(phase.shortLabel) && $0.contains("\(count) steps") }, phase.rawValue)
        }
    }

    func testTutorialNeverPromisesAHelperOnTheMac() {
        let text = SubmissionTutorial.pages(appName: "T").flatMap { [$0.body] + $0.points }.joined().lowercased()
        XCTAssertFalse(text.contains("companion"))
        XCTAssertTrue(text.contains("you open it"), "the Mac part is the user's, and says so")
    }

    func testAfterSubmissionExplainsEveryOutcomeAndWhatToDoMeanwhile() {
        XCTAssertFalse(AfterSubmission.headline.isEmpty)
        let ids = AfterSubmission.sections.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isSuperset(of: ["queue", "review", "meanwhile", "approved", "rejected", "tracking"]))
        let text = AfterSubmission.sections.map { $0.title + " " + $0.body }.joined(separator: " ")
        for needle in ["Waiting for Review", "In Review", "within a day", "normal", "resubmit", "emails"] {
            XCTAssertTrue(text.contains(needle), needle)
        }
        for section in AfterSubmission.sections { XCTAssertGreaterThan(section.body.count, 60, section.id) }
    }
}
