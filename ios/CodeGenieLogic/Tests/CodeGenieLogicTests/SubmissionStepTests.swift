import XCTest
@testable import CodeGenieLogic

final class SubmissionStepTests: XCTestCase {

    func testStepsAreNumberedContiguouslyFromOne() {
        XCTAssertEqual(ASCStep.all.map(\.number), Array(1...ASCStep.all.count))
    }

    func testPhasesAppearInOrderWithoutInterleaving() {
        let phases = ASCStep.all.map(\.phase)
        var seen: [ASCPhase] = []
        for phase in phases where seen.last != phase { seen.append(phase) }
        XCTAssertEqual(seen, ASCPhase.allCases)
    }

    func testNothingBeforeTheStorePhaseAsksForStoreAssets() {
        for step in ASCStep.steps(in: .testflight) + ASCStep.steps(in: .testing) {
            if case .prepareAsset = step.action { XCTFail("step \(step.number) asks for a store asset before TestFlight") }
            if case .fillForm = step.action { XCTFail("step \(step.number) asks for the listing before TestFlight") }
        }
    }

    func testSubmitStepIsTheLastStoreStep() {
        let submit = ASCStep.step(ASCStep.submitStepNumber)
        XCTAssertEqual(submit?.action, .submit)
        XCTAssertEqual(ASCStep.steps(in: .appStore).last?.number, ASCStep.submitStepNumber)
    }

    func testReviewPhaseCoversQueueDecisionAndRelease() {
        let moments: [ASCStep.ReviewMoment] = ASCStep.steps(in: .review).compactMap {
            if case .review(let moment) = $0.action { return moment }
            return nil
        }
        XCTAssertEqual(moments, [.queue, .decision, .release])
    }

    func testEveryStepHasAFullWalkthrough() {
        for step in ASCStep.all {
            do {
                let walk = ASCCoach.walkthrough(
                    for: step, appName: "Tide Times", bundleID: "com.jane.tidetimes"
                )
                XCTAssertFalse(walk.plainTitle.isEmpty, "step \(step.number)")
                XCTAssertGreaterThanOrEqual(walk.doThis.count, 3, "step \(step.number) has too few instructions")
                XCTAssertNotNil(walk.watchOut, "step \(step.number) has no warning")
                XCTAssertFalse(walk.timeEstimate.isEmpty, "step \(step.number) sets no time expectation")
                XCTAssertNotEqual(walk.whatThisIs, step.body, "step \(step.number) fell through to the default walkthrough")
            }
        }
    }

    func testAppRecordStepOffersTheExactBundleIDToCopy() {
        let walk = ASCCoach.walkthrough(for: ASCStep.step(5)!, appName: "Tide Times", bundleID: "com.jane.tidetimes")
        XCTAssertTrue(walk.doThis.contains { $0.copyValue == "com.jane.tidetimes" })
        XCTAssertTrue(walk.doThis.contains { $0.copyValue == "Tide Times" })
    }

    func testOwnershipNeverClaimsCodeGenieCanSubmit() {
        XCTAssertEqual(ASCStep.step(ASCStep.submitStepNumber)?.ownership, .you)
        XCTAssertEqual(ASCStep.step(ASCStep.queueStepNumber)?.ownership, .apple)
        XCTAssertEqual(ASCStep.step(ASCStep.releaseStepNumber)?.ownership, .you)
    }

    func testNamedStepNumbersPointAtTheRightSteps() {
        XCTAssertEqual(ASCStep.step(ASCStep.testPlanStepNumber)?.action, .testPlan)
        XCTAssertEqual(ASCStep.step(ASCStep.testVerdictStepNumber)?.action, .testVerdict)
        XCTAssertEqual(ASCStep.step(ASCStep.queueStepNumber)?.action, .review(.queue))
        XCTAssertEqual(ASCStep.step(ASCStep.decisionStepNumber)?.action, .review(.decision))
        XCTAssertEqual(ASCStep.step(ASCStep.releaseStepNumber)?.action, .review(.release))
        if case .wait = ASCStep.step(ASCStep.processingStepNumber)!.action {} else { XCTFail("processing step") }
        XCTAssertEqual(ASCStep.step(ASCStep.uploadStepNumber)?.place, .xcode)
    }

    // MARK: The Mac part is done by hand, in Xcode

    func testTheProjectReachesTheMacBeforeXcodeIsOpened() {
        XCTAssertEqual(ASCStep.step(1)?.action, .transferProject)
        XCTAssertEqual(ASCStep.step(2)?.place, .xcode)
    }

    func testXcodeStepsNameTheExactControls() {
        func text(_ n: Int) -> String {
            let w = ASCCoach.walkthrough(for: ASCStep.step(n)!, appName: "Tide Times", bundleID: "com.jane.tidetimes")
            return (w.doThis.map(\.text) + [w.watchOut ?? ""]).joined(separator: " ")
        }
        XCTAssertTrue(text(1).contains("AirDrop"))
        XCTAssertTrue(text(2).contains(".xcodeproj"))
        XCTAssertTrue(text(2).contains("Accounts"))
        XCTAssertTrue(text(3).contains("Signing & Capabilities"))
        XCTAssertTrue(text(3).contains("Automatically manage signing"))
        XCTAssertTrue(text(3).contains("Personal Team"), "the commonest wrong choice must be named")
        XCTAssertTrue(text(4).contains("Command-R"))
        XCTAssertTrue(text(6).contains("Any iOS Device"))
        XCTAssertTrue(text(6).contains("Archive"))
        XCTAssertTrue(text(6).contains("Distribute App"))
        XCTAssertTrue(text(6).contains("greyed out"), "the commonest snag must be named")
    }

    func testSigningStepShowsTheBundleIDToCompare() {
        let walk = ASCCoach.walkthrough(for: ASCStep.step(3)!, appName: "T", bundleID: "com.jane.t")
        XCTAssertTrue(walk.doThis.contains { $0.copyValue == "com.jane.t" })
    }

    func testNoStepMentionsACompanionApp() {
        for step in ASCStep.all {
            let w = ASCCoach.walkthrough(for: step, appName: "T", bundleID: "b")
            let all = ([step.title, step.body, w.plainTitle, w.whatThisIs, w.watchOut ?? ""] + w.doThis.map(\.text))
                .joined(separator: " ").lowercased()
            XCTAssertFalse(all.contains("companion"), "step \(step.number)")
            XCTAssertFalse(all.contains("pair your mac"), "step \(step.number)")
            XCTAssertFalse(all.contains("on my mac for you"), "step \(step.number)")
        }
    }

    func testTestingComesAfterInstallAndBeforeTheStorePage() {
        let install = ASCStep.steps(in: .testflight).last!.number
        let firstStore = ASCStep.steps(in: .appStore).first!.number
        XCTAssertGreaterThan(ASCStep.testPlanStepNumber, install)
        XCTAssertLessThan(ASCStep.testVerdictStepNumber, firstStore)
        XCTAssertEqual(ASCStep.steps(in: .testing).count, 3)
    }

    func testEveryStepSaysWhereItHappens() {
        XCTAssertEqual(Set(ASCStep.all.map(\.place)), [.phone, .xcode, .web, .apple])
    }
}
