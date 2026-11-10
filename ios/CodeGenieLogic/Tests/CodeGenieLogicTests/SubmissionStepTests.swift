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

    func testTestFlightPhaseNeedsNoStoreAssets() {
        for step in ASCStep.steps(in: .testflight) {
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
            for paired in [true, false] {
                let walk = ASCCoach.walkthrough(
                    for: step, appName: "Tide Times",
                    bundleID: "com.jane.tidetimes", macPaired: paired
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
        let walk = ASCCoach.walkthrough(
            for: ASCStep.step(2)!, appName: "Tide Times",
            bundleID: "com.jane.tidetimes", macPaired: false
        )
        XCTAssertTrue(walk.doThis.contains { $0.copyValue == "com.jane.tidetimes" })
        XCTAssertTrue(walk.doThis.contains { $0.copyValue == "Tide Times" })
    }

    func testOwnershipNeverClaimsCodeGenieCanSubmit() {
        XCTAssertEqual(ASCStep.step(ASCStep.submitStepNumber)?.ownership, .you)
        XCTAssertEqual(ASCStep.step(16)?.ownership, .apple)
        XCTAssertEqual(ASCStep.step(18)?.ownership, .you)
    }
}
