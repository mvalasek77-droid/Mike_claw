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

    func testAFinishedBuildLeadsStraightIntoTheGuide() {
        let next = Journey.nextStep(.init(latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: .readyForTest))
        XCTAssertEqual(next.action, .openSubmission(jobID: jobID))
        XCTAssertEqual(next.milestone, .phone)
        XCTAssertTrue(next.detail.contains("Xcode"), "the user should know a Mac is involved before they tap")
        XCTAssertTrue(next.detail.lowercased().contains("nobody has seen it run"))
    }

    func testASubmissionInProgressNamesTheExactStep() {
        let r = record { $0.complete(1); $0.complete(2) }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertEqual(next.action, .openSubmission(jobID: jobID))
        XCTAssertEqual(next.title, ASCStep.step(3)?.title)
        XCTAssertTrue(next.eyebrow.contains("step 3 of \(ASCStep.all.count)"))
        XCTAssertEqual(next.milestone, .phone)
    }

    func testOnceInstalledTheGoalIsTestingNotTheStore() {
        let r = record { r in (1...8).forEach { r.complete($0) } }
        let next = Journey.nextStep(.init(submission: r))
        XCTAssertEqual(next.milestone, .test)
        XCTAssertEqual(next.buttonTitle, "Continue testing")
        XCTAssertTrue(next.detail.lowercased().contains("works"))
    }

    func testAfterTestingTheGoalBecomesTheStore() {
        let r = record { r in (1...11).forEach { r.complete($0) } }
        XCTAssertEqual(Journey.nextStep(.init(submission: r)).milestone, .store)
    }

    func testWaitingOnApplesProcessingIsMarkedAsWaiting() {
        let r = record { r in (1...6).forEach { r.complete($0) } }
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
        let next = Journey.nextStep(.init(latestJobID: jobID, latestJobTitle: "T", latestJobStage: .readyForTest))
        XCTAssertTrue(Journey.reached(.describe, for: next))
        XCTAssertTrue(Journey.reached(.build, for: next))
        XCTAssertFalse(Journey.reached(.phone, for: next))
        XCTAssertFalse(Journey.reached(.live, for: next))
    }

    func testEveryNextStepHasSomethingToTap() {
        let stages = BuildJob.Stage.allCases
        for stage in stages {
            do {
                let next = Journey.nextStep(.init(
                    latestJobID: jobID, latestJobTitle: "Tide Times", latestJobStage: stage
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

final class TourTests: XCTestCase {

    func testTheTourVisitsEveryMilestoneOnceInOrder() {
        XCTAssertEqual(Journey.tour.map(\.milestone), Journey.Milestone.allCases)
    }

    func testEveryStopAnswersWhatYouDoAndHowLong() {
        for stop in Journey.tour {
            XCTAssertFalse(stop.title.isEmpty, "\(stop.milestone)")
            XCTAssertGreaterThan(stop.body.count, 60, "\(stop.milestone)")
            XCTAssertFalse(stop.youDo.isEmpty, "\(stop.milestone)")
            XCTAssertFalse(stop.takes.isEmpty, "\(stop.milestone)")
        }
    }

    func testCostsAndTheMacAreDisclosedBeforeTheUserStarts() {
        let all = Journey.tour.map { $0.body + " " + ($0.needs ?? "") }.joined(separator: " ")
        XCTAssertTrue(all.contains("$99"))
        XCTAssertTrue(all.contains("Mac"))
        XCTAssertTrue(all.contains("Xcode"))
        XCTAssertTrue(all.contains("AI key"))
        XCTAssertTrue(Journey.tourRequirements.contains { $0.contains("$99") })
    }

    func testTheTourPromisesNothingTheGuideDoesNotDo() {
        let all = Journey.tour.map { $0.body + $0.youDo + ($0.needs ?? "") }.joined(separator: " ").lowercased()
        for claim in ["companion", "pair", "simulator in the cloud", "without a mac", "automatically submits", "no mac"] {
            XCTAssertFalse(all.contains(claim), claim)
        }
    }

    func testTheTourSaysTestingIsTheUsersJob() {
        let test = Journey.tour.first { $0.milestone == .test }!
        XCTAssertTrue(test.body.contains("nobody knows yet whether it works"))
        XCTAssertTrue(test.body.contains("rebuild"))
    }

    func testThePhoneStopMatchesTheGuidesRealStepCount() {
        let phone = Journey.tour.first { $0.milestone == .phone }!
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let count = ASCStep.steps(in: .testflight).count
        XCTAssertTrue(phone.youDo.contains(words[count]), "the tour says \(phone.youDo); the guide has \(count) steps")
    }
}
