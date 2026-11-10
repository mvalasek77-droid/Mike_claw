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
        XCTAssertEqual(record.resumeStep, 16)
        XCTAssertEqual(record.review?.state, .waitingForReview)
        XCTAssertFalse(record.needsAttention, "waiting on Apple is not the user's turn")
    }

    func testReviewStepsFollowApplesStatus() {
        var record = fresh()
        record.markSubmitted(at: t0)

        XCTAssertTrue(record.applyReview(.inReview, at: t0))
        XCTAssertTrue(record.completedSteps.contains(16))
        XCTAssertFalse(record.completedSteps.contains(17))
        XCTAssertEqual(record.resumeStep, 17)

        record.applyReview(.pendingDeveloperRelease, at: t0)
        XCTAssertTrue(record.completedSteps.contains(17))
        XCTAssertEqual(record.resumeStep, 18)
        XCTAssertTrue(record.needsAttention, "the user has to press Release")

        record.applyReview(.live, at: t0)
        XCTAssertTrue(record.isComplete)
        XCTAssertEqual(record.progressFraction, 1)
    }

    func testRejectionKeepsTheUserOnTheDecisionStep() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.rejected, at: t0)
        XCTAssertEqual(record.resumeStep, 17)
        XCTAssertTrue(record.needsAttention)
        XCTAssertFalse(record.isComplete)
        XCTAssertEqual(record.statusLine, ASCReviewState.rejected.headline)
    }

    func testApprovalCanBeWithdrawnByALaterRejection() {
        var record = fresh()
        record.markSubmitted(at: t0)
        record.applyReview(.pendingDeveloperRelease, at: t0)
        record.applyReview(.rejected, at: t0)
        XCTAssertFalse(record.completedSteps.contains(17))
        XCTAssertFalse(record.completedSteps.contains(18))
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
        XCTAssertEqual(record.resumeStep, 16)
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
        through(14, &record)
        record.applyReview(.waitingForReview, at: t0)
        XCTAssertTrue(record.isSubmitted, "submitting on Apple's site without tapping here is still submitted")
        XCTAssertTrue(record.completedSteps.contains(ASCStep.submitStepNumber))
    }

    func testPrepareForSubmissionBeforeSubmittingMeansNothing() {
        var record = fresh()
        through(9, &record)
        XCTAssertFalse(record.applyReview(.notSubmitted, at: t0))
        XCTAssertFalse(record.applyReview(.unknown, at: t0))
        XCTAssertFalse(record.isSubmitted)
        XCTAssertNil(record.review)
        XCTAssertEqual(record.resumeStep, 10)
    }

    func testPhaseCompletion() {
        var record = fresh()
        through(6, &record)
        XCTAssertTrue(record.isPhaseComplete(.testflight))
        XCTAssertFalse(record.isPhaseComplete(.appStore))
    }

    // MARK: Migration from the twelve-step list

    private func legacy(completed: Set<Int>, submitted: Bool) throws -> ASCSubmissionRecord {
        let submittedField = submitted ? #","submittedAt":721692800"# : ""
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
        XCTAssertNil(record.metadata.privacyPolicyURL)
        XCTAssertEqual(record.appTitle, "Tide Times")
    }

    func testEarlyStepsKeepTheirNumbers() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: [1, 2, 3, 4, 5, 6, 7], submitted: false))
        XCTAssertEqual(migrated.completedSteps, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(migrated.resumeStep, 8)
        XCTAssertEqual(migrated.schema, ASCStep.schemaVersion)
    }

    func testPricingMovesAndInsertedStepsAreNotAssumedDone() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: Set(1...11), submitted: false))
        XCTAssertTrue(migrated.completedSteps.contains(12), "old step 11 was pricing, now step 12")
        XCTAssertFalse(migrated.completedSteps.contains(11), "age rating is new and was never confirmed")
        XCTAssertFalse(migrated.completedSteps.contains(13))
        XCTAssertFalse(migrated.completedSteps.contains(14))
        XCTAssertEqual(migrated.resumeStep, 11)
    }

    func testAnAlreadySubmittedRecordLandsInReviewNotAtTheStart() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: Set(1...12), submitted: true))
        XCTAssertTrue(migrated.isSubmitted)
        XCTAssertEqual(migrated.resumeStep, 16)
        XCTAssertEqual(migrated.review?.state, .waitingForReview)
        XCTAssertFalse(migrated.isComplete)
    }

    func testMigrationIsIdempotent() throws {
        let once = ASCSubmissionRecord.migrate(try legacy(completed: Set(1...11), submitted: false))
        XCTAssertEqual(ASCSubmissionRecord.migrate(once), once)
    }

    func testMigrationDropsStepNumbersThatNeverExisted() throws {
        let migrated = ASCSubmissionRecord.migrate(try legacy(completed: [1, 13, 40], submitted: false))
        XCTAssertEqual(migrated.completedSteps, [1])
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
}
