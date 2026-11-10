import XCTest
@testable import CodeGenieLogic

final class ReviewStateTests: XCTestCase {

    func testMapsBothOfApplesVocabularies() {
        let expected: [String: ASCReviewState] = [
            "PREPARE_FOR_SUBMISSION": .notSubmitted,
            "READY_FOR_REVIEW": .notSubmitted,
            "WAITING_FOR_REVIEW": .waitingForReview,
            "IN_REVIEW": .inReview,
            "REJECTED": .rejected,
            "METADATA_REJECTED": .metadataRejected,
            "INVALID_BINARY": .invalidBinary,
            "DEVELOPER_REJECTED": .developerRejected,
            "WAITING_FOR_EXPORT_COMPLIANCE": .waitingForExportCompliance,
            "PENDING_DEVELOPER_RELEASE": .pendingDeveloperRelease,
            "ACCEPTED": .pendingDeveloperRelease,
            "PENDING_APPLE_RELEASE": .pendingAppleRelease,
            "PROCESSING_FOR_APP_STORE": .processingForDistribution,
            "PROCESSING_FOR_DISTRIBUTION": .processingForDistribution,
            "READY_FOR_SALE": .live,
            "READY_FOR_DISTRIBUTION": .live,
            "REMOVED_FROM_SALE": .removedFromSale,
            "REPLACED_WITH_NEW_VERSION": .removedFromSale,
        ]
        for (raw, state) in expected {
            XCTAssertEqual(ASCReviewState(apple: raw), state, raw)
            XCTAssertEqual(ASCReviewState(apple: raw.lowercased()), state, "case-insensitive \(raw)")
        }
    }

    func testUnrecognisedStatusIsUnknownNotACrashOrAGuess() {
        XCTAssertEqual(ASCReviewState(apple: "SOME_FUTURE_STATE"), .unknown)
        XCTAssertEqual(ASCReviewState(apple: ""), .unknown)
    }

    func testEveryStateExplainsItselfAndSaysWhatToDo() {
        for state in ASCReviewState.allCases {
            XCTAssertFalse(state.headline.isEmpty, "\(state)")
            XCTAssertFalse(state.meaning.isEmpty, "\(state)")
            XCTAssertFalse(state.appleLabel.isEmpty, "\(state)")
            XCTAssertFalse(state.nextActions.isEmpty, "\(state) leaves the user with nothing to do")
        }
    }

    func testApprovedAndNeedsFixNeverOverlap() {
        for state in ASCReviewState.allCases {
            XCTAssertFalse(state.isApproved && state.needsFix, "\(state)")
            if state.isApproved { XCTAssertTrue(state.hasLeftQueue, "\(state)") }
            if state.needsFix { XCTAssertEqual(state.tone, .problem, "\(state)") }
        }
        XCTAssertEqual(ASCReviewState.live.tone, .good)
    }

    func testWaitingStatesGiveATimeExpectation() {
        XCTAssertNotNil(ASCReviewState.waitingForReview.typicalWait)
        XCTAssertNotNil(ASCReviewState.inReview.typicalWait)
    }

    func testMetadataRejectionSaysNoRebuild() {
        XCTAssertTrue(ASCReviewState.metadataRejected.meaning.lowercased().contains("no rebuilding"))
        XCTAssertTrue(ASCReviewState.invalidBinary.nextActions.joined().lowercased().contains("new build"))
    }

    func testReportableStatesCanAllBeChosenByHand() {
        XCTAssertFalse(ASCReviewState.reportable.contains(.unknown))
        XCTAssertFalse(ASCReviewState.reportable.contains(.notSubmitted))
        XCTAssertEqual(Set(ASCReviewState.reportable).count, ASCReviewState.reportable.count)
    }

    // MARK: Progress

    func testObservingTheSameStateOnlyUpdatesTheTimestamp() {
        let start = Date(timeIntervalSince1970: 1_000)
        var progress = ASCReviewProgress(state: .waitingForReview, at: start)
        let later = start.addingTimeInterval(600)
        XCTAssertFalse(progress.observe(.waitingForReview, at: later))
        XCTAssertEqual(progress.history.count, 1)
        XCTAssertEqual(progress.lastCheckedAt, later)
        XCTAssertEqual(progress.stateSince, start)
    }

    func testStateChangesAreRecordedInOrder() {
        var progress = ASCReviewProgress()
        XCTAssertTrue(progress.observe(.inReview, version: "1.0"))
        XCTAssertTrue(progress.observe(.rejected))
        XCTAssertEqual(progress.history.map(\.state), [.waitingForReview, .inReview, .rejected])
        XCTAssertEqual(progress.versionString, "1.0")
        XCTAssertTrue(progress.wasEverRejected)
    }

    func testUnknownNeverOverwritesAKnownState() {
        var progress = ASCReviewProgress()
        progress.observe(.pendingDeveloperRelease)
        XCTAssertFalse(progress.observe(.unknown))
        XCTAssertEqual(progress.state, .pendingDeveloperRelease)
    }

    func testResubmittingClearsTheGuidelineAndCounts() {
        var progress = ASCReviewProgress()
        progress.observe(.rejected)
        progress.rejectionGuideline = "2.1"
        progress.markResubmitted()
        XCTAssertEqual(progress.state, .waitingForReview)
        XCTAssertNil(progress.rejectionGuideline)
        XCTAssertEqual(progress.resubmissions, 1)
        XCTAssertTrue(progress.wasEverRejected, "history keeps the rejection")
    }

    func testApprovalClearsAStaleGuideline() {
        var progress = ASCReviewProgress()
        progress.observe(.rejected)
        progress.rejectionGuideline = "4.3"
        progress.observe(.inReview)
        XCTAssertNil(progress.rejectionGuideline)
    }

    func testProgressSurvivesEncoding() throws {
        var progress = ASCReviewProgress()
        progress.observe(.metadataRejected, version: "1.2")
        progress.rejectionGuideline = "2.3"
        let data = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(ASCReviewProgress.self, from: data), progress)
    }

    // MARK: Parsing Apple

    func testAnUpdateInFlightWinsOverTheLiveVersionWhateverTheOrder() {
        let live: [String: Any] = ["attributes": ["versionString": "1.0", "appStoreState": "READY_FOR_SALE"]]
        let pending: [String: Any] = ["attributes": ["versionString": "1.1", "appVersionState": "REJECTED"]]
        for rows in [[live, pending], [pending, live]] {
            let version = ASCReviewParser.currentVersion(in: ["data": rows])
            XCTAssertEqual(version?.state, .rejected)
            XCTAssertEqual(version?.versionString, "1.1")
        }
        XCTAssertEqual(ASCReviewParser.currentVersion(in: ["data": [live]])?.state, .live)
    }

    func testPrefersTheNewerOfApplesTwoStateFields() {
        let body: [String: Any] = ["data": [
            ["attributes": [
                "versionString": "1.0",
                "appVersionState": "IN_REVIEW",
                "appStoreState": "WAITING_FOR_REVIEW",
            ]],
            ["attributes": ["versionString": "0.9", "appStoreState": "READY_FOR_SALE"]],
        ]]
        let version = ASCReviewParser.currentVersion(in: body)
        XCTAssertEqual(version?.state, .inReview)
        XCTAssertEqual(version?.versionString, "1.0")
        XCTAssertEqual(version?.rawState, "IN_REVIEW")
    }

    func testFallsBackToTheOlderField() {
        let body: [String: Any] = ["data": [["attributes": ["appStoreState": "REJECTED"]]]]
        XCTAssertEqual(ASCReviewParser.currentVersion(in: body)?.state, .rejected)
    }

    func testNoVersionsIsNilNotAState() {
        XCTAssertNil(ASCReviewParser.currentVersion(in: ["data": [[String: Any]]()]))
        XCTAssertNil(ASCReviewParser.currentVersion(in: [:]))
        XCTAssertNil(ASCReviewParser.currentVersion(in: ["data": "nonsense"]))
    }

    func testMissingAttributesDegradeToUnknown() {
        let body: [String: Any] = ["data": [["id": "1"]]]
        XCTAssertEqual(ASCReviewParser.currentVersion(in: body)?.state, .unknown)
    }

    func testParsesRealJSONBytes() throws {
        let json = #"{"data":[{"type":"appStoreVersions","id":"x","attributes":{"platform":"IOS","versionString":"1.0","appVersionState":"PENDING_DEVELOPER_RELEASE"}}]}"#
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(ASCReviewParser.currentVersion(in: body)?.state, .pendingDeveloperRelease)
    }
}

final class RejectionGuideTests: XCTestCase {

    func testEveryGuideIsCompleteEnoughToActOn() {
        XCTAssertGreaterThanOrEqual(ASCRejectionGuide.all.count, 10)
        XCTAssertEqual(Set(ASCRejectionGuide.all.map(\.id)).count, ASCRejectionGuide.all.count)
        for guide in ASCRejectionGuide.all {
            XCTAssertFalse(guide.title.isEmpty, guide.id)
            XCTAssertFalse(guide.meaning.isEmpty, guide.id)
            XCTAssertFalse(guide.usualCause.isEmpty, guide.id)
            XCTAssertGreaterThanOrEqual(guide.fixes.count, 2, guide.id)
            XCTAssertTrue(guide.replyTemplate.contains("Thank you"), "\(guide.id) reply should open politely")
        }
    }

    func testCoversTheGuidelinesFirstAppsHit() {
        for id in ["2.1", "2.3", "4.2", "4.3", "5.1.1"] {
            XCTAssertNotNil(ASCRejectionGuide.guide(for: id), id)
        }
    }

    func testSubsectionsFallBackToTheirFamily() {
        XCTAssertEqual(ASCRejectionGuide.guide(for: "2.3.3")?.id, "2.3")
        XCTAssertEqual(ASCRejectionGuide.guide(for: "5.1.1(v)")?.id, "5.1.1")
        XCTAssertEqual(ASCRejectionGuide.guide(for: "Guideline 4.3 - Design - Spam")?.id, "4.3")
        XCTAssertEqual(ASCRejectionGuide.guide(for: "2.1.0")?.id, "2.1")
    }

    func testUnknownGuidelineIsNilRatherThanAWrongAnswer() {
        XCTAssertNil(ASCRejectionGuide.guide(for: "9.9"))
        XCTAssertNil(ASCRejectionGuide.guide(for: ""))
        XCTAssertNil(ASCRejectionGuide.guide(for: "no numbers here"))
    }

    func testStorePageRejectionsDoNotDemandARebuild() {
        XCTAssertEqual(ASCRejectionGuide.guide(for: "2.3")?.needsNewBuild, .no)
        XCTAssertEqual(ASCRejectionGuide.guide(for: "1.5")?.needsNewBuild, .no)
        XCTAssertEqual(ASCRejectionGuide.guide(for: "4.2")?.needsNewBuild, .yes)
    }

    func testSpamGuidanceIsHonestThatAReplyAloneWillNotWork() {
        let guide = ASCRejectionGuide.guide(for: "4.3")!
        XCTAssertTrue(guide.fixes.joined().lowercased().contains("not enough"))
    }

    func testFindsGuidelineNumbersInPastedRejectionText() {
        let text = """
        Guideline 2.1 - Performance - App Completeness
        We were unable to sign in. Next Steps...
        Guideline 5.1.1 - Legal - Privacy - Data Collection and Storage
        We reviewed on iPhone 15 running iOS 18.1 on 12.03.2026 at 10.30.
        Guideline 2.1 again.
        """
        XCTAssertEqual(ASCRejectionGuide.guidelines(mentionedIn: text), ["2.1", "5.1.1"])
    }

    func testIgnoresVersionNumbersAndPrices() {
        XCTAssertEqual(ASCRejectionGuide.guidelines(mentionedIn: "iOS 18.1, build 104, costs 9.99 or 0.99"), [])
        XCTAssertEqual(ASCRejectionGuide.guidelines(mentionedIn: ""), [])
    }
}
