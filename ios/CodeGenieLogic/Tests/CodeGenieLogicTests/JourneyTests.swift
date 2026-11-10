import XCTest
@testable import CodeGenieLogic

final class JourneyTests: XCTestCase {

    private let jobID = UUID()

    private func record(_ configure: (inout ASCSubmissionRecord) -> Void) -> ASCSubmissionRecord {
        var r = ASCSubmissionRecord(jobID: jobID, appTitle: "Tide Times", metadata: .empty)
        configure(&r)
        return r
    }

    func testABrandNewUserIsAskedToDescribeAnApp() {
        let next = Journey.nextStep(.init())
        XCTAssertEqual(next.action, .describeApp)
        XCTAssertEqual(next.milestone, .describe)
        XCTAssertFalse(next.isWaiting)
    }

    func testAnInterruptedBuildComesBeforeStartingAnother() {
        let next = Journey.nextStep(.init(
            buildInProgressTitle: "Tide Times",
            latestJobID: jobID, latestJobTitle: "Old App", latestJobStage: .readyForTest
        ))
        XCTAssertEqual(next.action, .resumeBuild)
        XCTAssertTrue(next.title.contains("Tide Times"))
    }

    func testAFailedBuildPointsAtTheFailure() {
        let next = Journey.nextStep(.init(latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: .failed))
        XCTAssertEqual(next.action, .openLatestBuild)
        XCTAssertEqual(next.milestone, .build)
    }

    func testAnUnfinishedBuildIsReopened() {
        let next = Journey.nextStep(.init(latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: .generatingUI))
        XCTAssertEqual(next.action, .openLatestBuild)
    }

    func testAFinishedBuildWithoutSetupNamesExactlyWhatIsMissing() {
        var facts = Journey.Facts(latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: .readyForTest)
        var next = Journey.nextStep(facts)
        XCTAssertEqual(next.action, .setUpShipping)
        XCTAssertTrue(next.detail.contains("a paired Mac and your Apple Developer details"))

        facts.macPaired = true
        next = Journey.nextStep(facts)
        XCTAssertEqual(next.action, .setUpShipping)
        XCTAssertFalse(next.detail.contains("a paired Mac"))
        XCTAssertTrue(next.detail.contains("your Apple Developer details"))
    }

    func testAFinishedBuildWithSetupGoesStraightToSubmission() {
        let next = Journey.nextStep(.init(
            latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: .readyForTest,
            macPaired: true, appleAccountReady: true
        ))
        XCTAssertEqual(next.action, .openSubmission(jobID: jobID))
        XCTAssertEqual(next.milestone, .phone)
    }

    func testASubmissionInProgressNamesTheExactStep() {
        let r = record { $0.complete(1); $0.complete(2) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertEqual(next.action, .openSubmission(jobID: jobID))
        XCTAssertEqual(next.title, ASCStep.step(3)?.title)
        XCTAssertTrue(next.eyebrow.contains("step 3 of \(ASCStep.all.count)"))
        XCTAssertEqual(next.milestone, .phone)
    }

    func testAfterTestFlightTheGoalBecomesTheStore() {
        let r = record { r in (1...6).forEach { r.complete($0) } }
        XCTAssertEqual(Journey.nextStep(.init(submission: r)).milestone, .store)
    }

    func testWaitingOnApplesProcessingIsMarkedAsWaiting() {
        let r = record { r in (1...3).forEach { r.complete($0) } }
        XCTAssertTrue(Journey.nextStep(.init(submission: r)).isWaiting)
    }

    func testInReviewIsWaitingAndSaysSo() {
        let r = record { $0.markSubmitted(); $0.applyReview(.inReview) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertTrue(next.isWaiting)
        XCTAssertEqual(next.title, ASCReviewState.inReview.headline)
        XCTAssertTrue(next.eyebrow.contains("with Apple"))
    }

    func testARejectionIsTheUsersTurnAndOffersTheFix() {
        let r = record { $0.markSubmitted(); $0.applyReview(.rejected) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertFalse(next.isWaiting)
        XCTAssertEqual(next.buttonTitle, "See how to fix it")
        XCTAssertTrue(next.eyebrow.contains("needs you"))
    }

    func testApprovalAwaitingReleaseIsTheUsersTurn() {
        let r = record { $0.markSubmitted(); $0.applyReview(.pendingDeveloperRelease) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertFalse(next.isWaiting)
        XCTAssertEqual(next.milestone, .live)
    }

    func testALiveAppInvitesTheNextOne() {
        let r = record { $0.markSubmitted(); $0.applyReview(.live) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertEqual(next.action, .startAnother)
        for milestone in Journey.Milestone.allCases {
            XCTAssertTrue(Journey.reached(milestone, for: next), "\(milestone)")
        }
    }

    func testMilestonesBehindTheUserAreReached() {
        let next = Journey.nextStep(.init(
            latestJobID: jobID, latestJobTitle: "T", latestJobStage: .readyForTest,
            macPaired: true, appleAccountReady: true
        ))
        XCTAssertTrue(Journey.reached(.describe, for: next))
        XCTAssertTrue(Journey.reached(.build, for: next))
        XCTAssertFalse(Journey.reached(.phone, for: next))
        XCTAssertFalse(Journey.reached(.live, for: next))
    }

    func testEveryNextStepHasSomethingToTap() {
        let stages = BuildJob.Stage.allCases
        for stage in stages {
            for paired in [true, false] {
                let next = Journey.nextStep(.init(
                    latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: stage,
                    macPaired: paired, appleAccountReady: paired
                ))
                XCTAssertFalse(next.title.isEmpty)
                XCTAssertFalse(next.detail.isEmpty)
                XCTAssertFalse(next.buttonTitle.isEmpty)
            }
        }
        for state in ASCReviewState.allCases {
            let r = record { $0.markSubmitted(); $0.applyReview(state) }
            let next = Journey.nextStep(.init(submission: r))
            XCTAssertFalse(next.title.isEmpty, "\(state)")
            XCTAssertFalse(next.detail.isEmpty, "\(state)")
        }
    }

    // MARK: Choosing which submission to show

    func testTheSubmissionNeedingTheUserWinsOverOneWaiting() {
        var waiting = ASCSubmissionRecord(jobID: UUID(), appTitle: "Waiting", metadata: .empty)
        waiting.markSubmitted()
        waiting.lastTouchedAt = Date()
        var rejected = ASCSubmissionRecord(jobID: UUID(), appTitle: "Rejected", metadata: .empty)
        rejected.markSubmitted()
        rejected.applyReview(.rejected)
        rejected.lastTouchedAt = Date(timeIntervalSinceNow: -86_400)
        XCTAssertEqual(Journey.primarySubmission(among: [waiting, rejected])?.appTitle, "Rejected")
    }

    func testUntouchedRecordsAreNotSurfaced() {
        let untouched = ASCSubmissionRecord(jobID: UUID(), appTitle: "Opened once", metadata: .empty)
        XCTAssertNil(Journey.primarySubmission(among: [untouched]))
        XCTAssertNil(Journey.primarySubmission(among: []))
    }

    func testAnOpenSubmissionWinsOverAFinishedOne() {
        var live = ASCSubmissionRecord(jobID: UUID(), appTitle: "Live", metadata: .empty)
        live.markSubmitted(); live.applyReview(.live)
        var open = ASCSubmissionRecord(jobID: UUID(), appTitle: "Open", metadata: .empty)
        open.complete(1)
        open.lastTouchedAt = Date(timeIntervalSinceNow: -999_999)
        XCTAssertEqual(Journey.primarySubmission(among: [live, open])?.appTitle, "Open")
        XCTAssertEqual(Journey.primarySubmission(among: [live])?.appTitle, "Live")
    }
}
