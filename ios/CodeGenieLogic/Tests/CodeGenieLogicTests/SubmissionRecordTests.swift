import XCTest
@testable import CodeGenieLogic

final class SubmissionRecordTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func fresh() -> ASCSubmissionRecord {
        ASCSubmissionRecord(jobID: UUID(), appTitle: "Tide Times", metadata: .empty, now: t0)
    }

    private func through(_ last: Int, _ record: inout ASCSubmissionRecord) {
        for step in 1...last { record.complete(step, at: t0) }
    }

    func testFreshRecordStartsAtStepOne() {
        let record = fresh()
        XCTAssertEqual(record.resumeStep, 1)
        XCTAssertEqual(record.progressFraction, 0)
        XCTAssertFalse(record.isSubmitted)
        XCTAssertFalse(record.isComplete)
        XCTAssertEqual(record.schema, ASCStep.schemaVersion)
        XCTAssertEqual(record.statusLine, "Step 1 of \(ASCStep.all.count)")
    }

    func testResumeSkipsToTheFirstGap() {
        var record = fresh()
        record.complete(1); record.complete(2); record.complete(4)
        XCTAssertEqual(record.resumeStep, 3)
    }

    func testCompletingAStepThatDoesNotExistIsIgnored() {
        var record = fresh()
        record.complete(0); record.complete(99); record.complete(-3)
        XCTAssertTrue(record.completedSteps.isEmpty)
    }

    func testReopenUndoesACompletion() {
        var record = fresh()
        record.complete(1)
        record.reopen(1)
        XCTAssertEqual(record.resumeStep, 1)
    }

    func testSubmittingIsNotTheSameAsFinished() {
        var record = fresh()
        record.markSubmitted(at: t0)
        XCTAssertTrue(record.isSubmitted)
        XCTAssertFalse(record.isComplete, "a submitted app still has a review to get through")
        XCTAssertEqual(record.resumeStep, ASCStep.queueStepNumber)
        XCTAssertEqual(record.review?.state, .waitingForReview)
        XCTAssertFalse(record.needsAttention, "waiting on Apple is not the user's turn")
    }

    func testReviewStepsFollowApplesStatus() {
        var record = fresh()
        record.markSubmitted(at: t0)

        XCTAssertTrue(record.applyReview(.inReview, at: t0))
        XCTAssertTrue(record.completedSteps.contains(ASCStep.queueStepNumber))
        XCTAssertFalse(record.completedSteps.contains(ASCStep.decisionStepNumber))
        XCTAssertEqual(record.resumeStep, ASCStep.decisionStepNumber)

        record.applyReview(.pendingDeveloperRelease, at: t0)
        XCTAssertTrue(record.completedSteps.contains(ASCStep.decisionStepNumber))
        XCTAssertEqual(record.resumeStep, ASCStep.releaseStepNumber)
        XCTAssertTrue(record.needsAttention, "the user has to press Release")

        record.applyReview(.live, at: t0)
        XCTAssertTrue(record.isComplete)
        XCTAssertEqual(record.progressFraction, 1)
    }

    func testRejectionKeepsTheUserOnTheDecisionStep() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.rejected, at: t0)
        XCTAssertEqual(record.resumeStep, ASCStep.decisionStepNumber)
        XCTAssertTrue(record.needsAttention)
        XCTAssertFalse(record.isComplete)
        XCTAssertEqual(record.statusLine, ASCReviewState.rejected.headline)
    }

    func testApprovalCanBeWithdrawnByALaterRejection() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.pendingDeveloperRelease, at: t0)
        record.applyReview(.rejected, at: t0)
        XCTAssertFalse(record.completedSteps.contains(ASCStep.decisionStepNumber))
        XCTAssertFalse(record.completedSteps.contains(ASCStep.releaseStepNumber))
    }

    func testResubmittingGoesBackToTheQueue() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.rejected, at: t0)
        record.noteRejectionGuideline("2.1")
        XCTAssertEqual(record.review?.rejectionGuideline, "2.1")
        record.markResubmitted(at: t0)
        XCTAssertEqual(record.review?.state, .waitingForReview)
        XCTAssertEqual(record.review?.resubmissions, 1)
        XCTAssertNil(record.review?.rejectionGuideline)
        XCTAssertEqual(record.resumeStep, ASCStep.queueStepNumber)
    }

    func testWithdrawalReopensTheSubmitStep() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.inReview, at: t0)
        record.applyReview(.developerRejected, at: t0)
        XCTAssertEqual(record.resumeStep, ASCStep.submitStepNumber)
    }

    func testApplePipelineStatusImpliesSubmission() {
        var record = fresh()
        through(ASCStep.submitStepNumber - 1, &record)
        record.applyReview(.waitingForReview, at: t0)
        XCTAssertTrue(record.isSubmitted, "submitting on Apple's site without tapping here is still submitted")
        XCTAssertTrue(record.completedSteps.contains(ASCStep.submitStepNumber))
    }

    func testPrepareForSubmissionBeforeSubmittingMeansNothing() {
        var record = fresh()
        through(8, &record)
        XCTAssertFalse(record.applyReview(.notSubmitted, at: t0))
        XCTAssertFalse(record.applyReview(.unknown, at: t0))
        XCTAssertFalse(record.isSubmitted)
        XCTAssertNil(record.review)
        XCTAssertEqual(record.resumeStep, 9)
    }

    func testPhaseCompletion() {
        var record = fresh()
        through(8, &record)
        XCTAssertTrue(record.isPhaseComplete(.testflight))
        XCTAssertFalse(record.isPhaseComplete(.testing))
        XCTAssertFalse(record.isPhaseComplete(.appStore))
    }

    // MARK: Migration

    private func legacy(completed: Set<Int>, submitted: Bool, schema: Int? = nil) throws -> ASCSubmissionRecord {
        var submittedField = submitted ? #","submittedAt":721692800"# : ""
        if let schema { submittedField += #","schema":\#(schema)"# }
        let steps = completed.sorted().map(String.init).joined(separator: ",")
        let json = """
        {"jobID":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","appTitle":"Tide Times",
         "completedSteps":[\(steps)],
         "metadata":{"name":"Tide Times","subtitle":"","primaryCategory":"Utility","keywords":["tide"],
                     "description":"Tides.","promotionalText":"","supportURL":"","marketingURL":"",
                     "ageRating":"4+","price":"Free"},
         "startedAt":721692000,"lastTouchedAt":721692500\(submittedField)}
        """
        return try JSONDecoder().decode(ASCSubmissionRecord.self, from: Data(json.utf8))
    }

    func testRecordsSavedBeforeTheNewFieldsStillDecode() throws {
        let record = try legacy(completed: [1, 2], submitted: false)
        XCTAssertNil(record.schema)
        XCTAssertNil(record.review)
        XCTAssertNil(record.checkedItems)
        XCTAssertNil(record.testResults)
        XCTAssertNil(record.tutorialSeen)
        XCTAssertNil(record.metadata.privacyPolicyURL)
        XCTAssertEqual(record.appTitle, "Tide Times")
        XCTAssertTrue(record.results.isEmpty)
    }

    func testFromTwelveSteps_AnUploadImpliesTheXcodeSteps() throws {
        // v1: 1 sign in, 2 record, 3 upload, 4 processing, 5 TestFlight.
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: [1, 2, 3, 4, 5], submitted: false))
        XCTAssertEqual(migrated.completedSteps, [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(migrated.resumeStep, ASCStep.testPlanStepNumber, "installed, so testing is next")
        XCTAssertEqual(migrated.schema, ASCStep.schemaVersion)
    }

    func testFromTwelveSteps_TestingIsNeverAssumedDone() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: Set(1...11), submitted: false))
        XCTAssertFalse(migrated.completedSteps.contains(ASCStep.testPlanStepNumber))
        XCTAssertFalse(migrated.completedSteps.contains(ASCStep.testVerdictStepNumber))
        XCTAssertTrue(migrated.completedSteps.contains(10), "inviting testers carries over")
        XCTAssertTrue(migrated.completedSteps.contains(17), "pricing: 11 → 12 → 17")
        XCTAssertFalse(migrated.completedSteps.contains(16), "age rating was never confirmed")
        XCTAssertEqual(migrated.resumeStep, ASCStep.testPlanStepNumber)
    }

    func testFromEighteenSteps_StoreStepsShiftByFive() throws {
        // v2: 7 icon, 8 screenshots, 9 listing.
        let migrated = ASCSubmissionRecord.migrate(
            try legacy(completed: [1, 2, 3, 4, 5, 6, 7, 8, 9], submitted: false, schema: 2)
        )
        XCTAssertTrue(migrated.completedSteps.isSuperset(of: [12, 13, 14]))
        XCTAssertFalse(migrated.completedSteps.contains(15))
        XCTAssertFalse(migrated.completedSteps.contains(ASCStep.testPlanStepNumber))
    }

    func testFromEighteenSteps_OnlyTheAppRecordDoneLandsOnTheFirstXcodeStep() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: [1, 2], submitted: false, schema: 2))
        XCTAssertEqual(migrated.completedSteps, [5])
        XCTAssertEqual(migrated.resumeStep, 1)
    }

    func testAnAlreadySubmittedRecordLandsInReviewFromAnyVersion() throws {
        for (steps, schema) in [(Set(1...12), nil as Int?), (Set(1...15), 2)] {
            let migrated = ASCSubmissionRecord.migrate(try legacy(completed: steps, submitted: true, schema: schema))
            XCTAssertTrue(migrated.isSubmitted)
            XCTAssertEqual(migrated.resumeStep, ASCStep.queueStepNumber)
            XCTAssertEqual(migrated.review?.state, .waitingForReview)
            XCTAssertFalse(migrated.isComplete)
            XCTAssertEqual(migrated.afterSubmissionSeen, true)
        }
    }

    func testMigrationIsIdempotent() throws {
        for schema in [nil as Int?, 2] {
            let once = ASCSubmissionRecord.migrate(try legacy(completed: Set(1...9), submitted: false, schema: schema))
            XCTAssertEqual(ASCSubmissionRecord.migrate(once), once)
        }
    }

    func testMigrationDropsStepNumbersThatNeverExisted() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: [2, 13, 40], submitted: false))
        XCTAssertEqual(migrated.completedSteps, [5])
    }

    func testCurrentRecordsRoundTrip() throws {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.metadataRejected, version: "1.0", at: t0)
        record.noteRejectionGuideline("2.3")
        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([ASCSubmissionRecord].self, from: data)
        XCTAssertEqual(decoded, [record])
        XCTAssertEqual(ASCSubmissionRecord.migrate(decoded[0]), record, "current schema is left untouched")
    }

    // MARK: Testing gates

    private var plan: [TestCase] {
        TestPlan.make(for: AppDescription(title: "Tide Times", prompt: "tides", features: ["Pick a beach"]))
    }

    private func passAll(_ record: inout ASCSubmissionRecord, only required: Bool = false) {
        for test in plan where !required || test.required {
            record.setTestResult(TestResult(outcome: .passed, at: t0), for: test.id, in: plan, at: t0)
        }
    }

    func testTheTestStepCannotBeFinishedUntilRequiredTestsPass() {
        var record = fresh()
        through(8, &record)
        XCTAssertEqual(record.resumeStep, ASCStep.testPlanStepNumber)
        let firstRequired = plan.first { $0.required }!
        record.setTestResult(TestResult(outcome: .passed, at: t0), for: firstRequired.id, in: plan, at: t0)
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testPlanStepNumber), "one pass is not a tested app")
        passAll(&record, only: true)
        XCTAssertTrue(record.completedSteps.contains(ASCStep.testPlanStepNumber))
    }

    func testAnyFailureReopensTestingAndWithdrawsTheVerdict() {
        var record = fresh()
        through(8, &record)
        passAll(&record)
        XCTAssertTrue(record.confirmTestingPassed(with: plan, at: t0))
        XCTAssertTrue(record.completedSteps.contains(ASCStep.testVerdictStepNumber))

        record.setTestResult(TestResult(outcome: .failed, note: "crashes offline", at: t0), for: "no_network", in: plan, at: t0)
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testPlanStepNumber))
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testVerdictStepNumber))
        XCTAssertFalse(record.confirmTestingPassed(with: plan, at: t0), "can't declare it ready with a failing test")
    }

    func testAnOptionalFailureAlsoBlocks() {
        var record = fresh()
        passAll(&record, only: true)
        record.setTestResult(TestResult(outcome: .failed, at: t0), for: "dark_mode", in: plan, at: t0)
        XCTAssertFalse(record.confirmTestingPassed(with: plan, at: t0), "a known bug is a known bug, required or not")
    }

    func testClearingAResultReopensTheStep() {
        var record = fresh()
        passAll(&record)
        record.setTestResult(nil, for: "first_launch", in: plan, at: t0)
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testPlanStepNumber))
    }

    func testVerdictIsRefusedWithNothingTested() {
        var record = fresh()
        XCTAssertFalse(record.confirmTestingPassed(with: plan, at: t0))
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testVerdictStepNumber))
    }

    func testANewBuildMeansUploadingAndTestingAgain() {
        var record = fresh()
        through(8, &record)
        passAll(&record)
        record.complete(10)
        record.confirmTestingPassed(with: plan, at: t0)
        record.complete(12); record.complete(14)

        record.resetForNewBuild(at: t0)
        XCTAssertTrue(record.results.isEmpty, "results describe the old build")
        XCTAssertEqual(record.resumeStep, ASCStep.uploadStepNumber)
        XCTAssertTrue(record.completedSteps.isSuperset(of: [1, 2, 3, 4, 5]), "Xcode setup and the app record are kept")
        XCTAssertTrue(record.completedSteps.isSuperset(of: [12, 14]), "store page work is kept")
        XCTAssertFalse(record.completedSteps.contains(ASCStep.testVerdictStepNumber))
    }

    func testTestResultsSurviveStorage() throws {
        var record = fresh()
        record.setTestResult(TestResult(outcome: .failed, note: " crashes ", at: t0), for: "main_task", in: plan, at: t0)
        let decoded = try JSONDecoder().decode(ASCSubmissionRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.results["main_task"]?.outcome, .failed)
        XCTAssertEqual(decoded.results["main_task"]?.note, "crashes", "notes are trimmed")
    }
}
