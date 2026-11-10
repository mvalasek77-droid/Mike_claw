import XCTest
@testable import CodeGenieLogic

final class ListingValidationTests: XCTestCase {

    private func valid() -> AppStoreMetadata {
        var m = AppStoreMetadata(
            name: "Tide Times", subtitle: "Tides for surfers", primaryCategory: "Utilities",
            keywords: ["tide", "surf"], description: "See today's tides at your beach.",
            promotionalText: "", supportURL: "https://jane.dev/support", marketingURL: "",
            ageRating: "4+", price: "Free"
        )
        m.privacyPolicyURL = "https://jane.dev/privacy"
        m.copyright = "2026 Jane Appleseed"
        m.requiresLogin = false
        return m
    }

    private func blockingFields(_ m: AppStoreMetadata) -> Set<ASCCoach.Issue.Field> {
        Set(ASCCoach.blockingIssues(m).map(\.field))
    }

    func testACompleteListingPasses() {
        XCTAssertTrue(ASCCoach.isMetadataReady(valid()), "\(ASCCoach.blockingIssues(valid()).map(\.message))")
    }

    func testLimitsAreApplesAndAreInclusive() {
        var m = valid()
        m.name = String(repeating: "a", count: 30)
        m.subtitle = String(repeating: "b", count: 30)
        m.promotionalText = String(repeating: "c", count: 170)
        m.description = String(repeating: "d", count: 4000)
        m.keywords = [String(repeating: "k", count: 100)]
        XCTAssertTrue(ASCCoach.isMetadataReady(m))

        m.name += "a"; m.subtitle += "b"; m.promotionalText += "c"; m.description += "d"
        m.keywords = [String(repeating: "k", count: 101)]
        XCTAssertEqual(blockingFields(m), [.name, .subtitle, .promotionalText, .description, .keywords])
    }

    func testKeywordBudgetCountsTheCommas() {
        var m = valid()
        m.keywords = Array(repeating: "abcd", count: 20)   // 80 letters + 19 commas = 99
        XCTAssertFalse(blockingFields(m).contains(.keywords))
        m.keywords = Array(repeating: "abcd", count: 21)   // 84 + 20 = 104
        XCTAssertTrue(blockingFields(m).contains(.keywords))
        XCTAssertEqual(ASCCoach.keywordString([" tide ", "", "surf"]), "tide,surf")
    }

    func testWhitespaceOnlyCountsAsEmpty() {
        var m = valid()
        m.name = "   "; m.supportURL = "\n"
        XCTAssertTrue(blockingFields(m).isSuperset(of: [.name, .supportURL]))
    }

    func testSupportURLMustBeRealAndReachableLooking() {
        var m = valid()
        for bad in ["", "jane.dev", "ftp://jane.dev", "https://localhost", "https://example.com/help", "not a url"] {
            m.supportURL = bad
            XCTAssertTrue(blockingFields(m).contains(.supportURL), bad)
        }
    }

    func testPrivacyPolicyIsRequiredForEveryApp() {
        var m = valid()
        m.privacyPolicyURL = nil
        XCTAssertTrue(blockingFields(m).contains(.privacyPolicyURL))
        m.privacyPolicyURL = "https://example.com/privacy"
        XCTAssertTrue(blockingFields(m).contains(.privacyPolicyURL))
        m.privacyPolicyURL = "https://jane.dev/privacy"
        XCTAssertFalse(blockingFields(m).contains(.privacyPolicyURL))
    }

    func testCopyrightNeedsAnOwnerNotJustAYear() {
        var m = valid()
        m.copyright = nil
        XCTAssertTrue(blockingFields(m).contains(.copyright))
        m.copyright = "2026 "
        XCTAssertTrue(blockingFields(m).contains(.copyright), "a year alone names no owner")
        m.copyright = "© 2026 Jane"
        XCTAssertFalse(blockingFields(m).contains(.copyright))
        XCTAssertTrue(ASCCoach.validate(m).contains { $0.field == .copyright && $0.severity == .warning })
    }

    func testAnAppWithLoginMustGiveTheReviewerAWayIn() {
        var m = valid()
        m.requiresLogin = true
        m.reviewNotes = "Open the app and tap Start."
        XCTAssertTrue(blockingFields(m).contains(.reviewNotes))
        m.reviewNotes = "Test account — username demo@jane.dev, password Tides2026"
        XCTAssertFalse(blockingFields(m).contains(.reviewNotes))
        m.requiresLogin = false
        m.reviewNotes = nil
        XCTAssertFalse(blockingFields(m).contains(.reviewNotes))
    }

    func testOptionalFieldsOnlyWarn() {
        var m = valid()
        m.subtitle = ""; m.keywords = []; m.marketingURL = "https://example.com"
        XCTAssertTrue(ASCCoach.isMetadataReady(m))
        XCTAssertEqual(Set(ASCCoach.validate(m).map(\.field)), [.subtitle, .keywords, .marketingURL])
    }

    func testBlockingIssuesSortFirst() {
        var m = valid()
        m.subtitle = ""; m.name = ""
        let issues = ASCCoach.validate(m)
        XCTAssertEqual(issues.first?.severity, .blocking)
        XCTAssertEqual(issues.last?.severity, .warning)
    }

    func testEveryIssueTellsTheUserWhatToDo() {
        for issue in ASCCoach.validate(.empty) {
            XCTAssertFalse(issue.message.isEmpty)
            XCTAssertFalse(issue.fix.isEmpty, "\(issue.field)")
        }
    }
}

final class ListingDraftTests: XCTestCase {

    func testDraftNeverExceedsApplesLimitsHoweverLongTheInput() {
        let long = String(repeating: "extraordinary ", count: 600)
        let app = AppDescription(
            title: String(repeating: "Tide ", count: 20), prompt: long,
            features: (0..<40).map { "feature number \($0) with a very long description indeed" }
        )
        let draft = AppStoreMetadata.draft(for: app, year: 2026)
        XCTAssertLessThanOrEqual(draft.name.count, ASCCoach.Limit.name)
        XCTAssertLessThanOrEqual(draft.subtitle.count, ASCCoach.Limit.subtitle)
        XCTAssertLessThanOrEqual(draft.description.count, ASCCoach.Limit.description)
        XCTAssertLessThanOrEqual(ASCCoach.keywordString(draft.keywords).count, ASCCoach.Limit.keywordsTotal)
        let lengthFields: Set<ASCCoach.Issue.Field> = [.name, .subtitle, .description, .keywords, .promotionalText]
        XCTAssertTrue(Set(ASCCoach.blockingIssues(draft).map(\.field)).isDisjoint(with: lengthFields))
    }

    func testDraftLeavesWhatOnlyTheUserKnowsEmptyAndFlagged() {
        let draft = AppStoreMetadata.draft(for: AppDescription(title: "Tide Times", prompt: "Tide tables for surfers"), year: 2026)
        XCTAssertEqual(draft.supportURL, "")
        XCTAssertEqual(draft.privacyPolicyURL, "")
        XCTAssertEqual(draft.copyright, "2026 ")
        let blocking = Set(ASCCoach.blockingIssues(draft).map(\.field))
        XCTAssertEqual(blocking, [.supportURL, .privacyPolicyURL, .copyright])
    }

    func testDraftKeywordsAreUniqueAndNonEmpty() {
        let draft = AppStoreMetadata.draft(for: AppDescription(
            title: "Tide Times", prompt: "tides tides tides for surfers", features: ["Tides", "tides"]
        ))
        XCTAssertEqual(Set(draft.keywords).count, draft.keywords.count)
        XCTAssertFalse(draft.keywords.contains(""))
        XCTAssertFalse(draft.keywords.isEmpty)
    }

    func testAnEmptyDescriptionStillProducesAUsableDraft() {
        let draft = AppStoreMetadata.draft(for: AppDescription(title: "", prompt: ""))
        XCTAssertFalse(draft.keywords.isEmpty)
        XCTAssertFalse(draft.primaryCategory.isEmpty)
        XCTAssertNotNil(draft.reviewNotes)
    }
}

final class ReviewNotesTests: XCTestCase {

    func testNotesNameTheAppAndWalkTheReviewerThroughIt() {
        let notes = ASCCoach.reviewNotesDraft(
            appName: "Tide Times", summary: "Tide tables for surfers.\nSecond line.",
            features: ["Pick a beach", "See today's tides"], requiresLogin: false
        )
        XCTAssertTrue(notes.contains("Tide Times"))
        XCTAssertTrue(notes.contains("What it does: Tide tables for surfers."))
        XCTAssertFalse(notes.contains("Second line"), "only the first line is a summary")
        XCTAssertTrue(notes.contains("2. Pick a beach"))
        XCTAssertTrue(notes.contains("3. See today's tides"))
        XCTAssertTrue(notes.contains("Sign-in: none"))
    }

    func testLoginAppsGetCredentialSlotsThatMustBeFilled() {
        let notes = ASCCoach.reviewNotesDraft(appName: "Club", summary: "Members app", features: [], requiresLogin: true)
        XCTAssertTrue(notes.contains("Username: [test username]"))
        XCTAssertTrue(notes.contains("Password: [test password]"))
        let blanks = ASCCoach.unfilledPlaceholders(in: notes)
        XCTAssertTrue(blanks.contains("test username"))
        XCTAssertTrue(blanks.contains("your email"))
    }

    func testMissingDetailsBecomeExplicitBlanksNotInventions() {
        let notes = ASCCoach.reviewNotesDraft(appName: " ", summary: "", features: [], requiresLogin: false)
        XCTAssertTrue(notes.contains("This app"))
        XCTAssertTrue(notes.contains("[one sentence describing the app]"))
    }

    func testFilledNotesHaveNoPlaceholders() {
        XCTAssertEqual(ASCCoach.unfilledPlaceholders(in: "Contact: Jane, jane@jane.dev, 555 0100"), [])
        XCTAssertEqual(ASCCoach.unfilledPlaceholders(in: "empty [] and [ ] don't count"), [])
        XCTAssertEqual(ASCCoach.unfilledPlaceholders(in: "an [unclosed blank"), [])
    }

    func testOnlyAFewFeaturesAreListed() {
        let notes = ASCCoach.reviewNotesDraft(
            appName: "A", summary: "s", features: (1...12).map { "Feature \($0)" }, requiresLogin: false
        )
        XCTAssertTrue(notes.contains("Feature 4"))
        XCTAssertFalse(notes.contains("Feature 5"))
    }
}

final class ReadinessGateTests: XCTestCase {

    private func run(_ items: [(String, String, Bool)], gate: String = "needs_setup") -> ReleaseReadinessRun {
        ReleaseReadinessRun(json: [
            "release_gate": gate, "score": 50, "summary": "",
            "items": items.map { ["key": $0.0, "title": $0.0, "status": $0.1, "required": $0.2] },
        ])
    }

    func testTestFlightOnlyNeedsWhatAnUploadNeeds() {
        let r = run([
            ("workspace", "automated", true), ("xcode_project", "automated", true),
            ("apple_credentials", "automated", true), ("testflight_upload", "assisted", true),
            ("screenshots", "needs_setup", true), ("privacy_policy", "needs_setup", true),
            ("privacy_manifest", "needs_setup", true), ("ipa", "needs_setup", true),
        ])
        XCTAssertTrue(ASCCoach.isReadyForTestFlightUpload(r))
        XCTAssertFalse(ASCCoach.isReadyForAppStoreSubmission(r))
        XCTAssertEqual(Set(ASCCoach.outstandingForAppStoreSubmission(r).map(\.key)),
                       ["screenshots", "privacy_policy", "privacy_manifest", "ipa"])
    }

    func testMissingCredentialsBlockTheUpload() {
        let r = run([("apple_credentials", "needs_setup", true)])
        XCTAssertEqual(ASCCoach.outstandingForTestFlightUpload(r).map(\.key), ["apple_credentials"])
        XCTAssertFalse(ASCCoach.isReadyForTestFlightUpload(r))
    }

    func testAMissingAuditIsNeverAPass() {
        XCTAssertFalse(ASCCoach.isReadyForTestFlightUpload(nil))
        XCTAssertFalse(ASCCoach.isReadyForAppStoreSubmission(nil))
    }

    func testOptionalItemsNeverBlock() {
        let r = run([("github", "needs_setup", false)], gate: "ready_for_testflight")
        XCTAssertTrue(ASCCoach.outstandingForAppStoreSubmission(r).isEmpty)
        XCTAssertTrue(ASCCoach.isReadyForAppStoreSubmission(r))
    }

    func testMalformedAuditDegradesToNotReady() {
        let r = ReleaseReadinessRun(json: ["items": "nonsense", "score": "high"])
        XCTAssertEqual(r.releaseGate, "needs_setup")
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertFalse(r.isReadyForTestFlight)
    }
}

final class SubmissionChecklistTests: XCTestCase {

    func testIDsAreUnique() {
        XCTAssertEqual(Set(SubmissionChecklist.all.map(\.id)).count, SubmissionChecklist.all.count)
    }

    func testEveryItemSaysWhyAppleCares() {
        for item in SubmissionChecklist.all {
            XCTAssertGreaterThan(item.why.count, 30, item.id)
        }
    }

    func testTestFlightScopeIsASubsetOfTheStoreScope() {
        let beta = Set(SubmissionChecklist.items(forAppStore: false).map(\.id))
        let store = Set(SubmissionChecklist.items(forAppStore: true).map(\.id))
        XCTAssertTrue(beta.isStrictSubset(of: store))
        XCTAssertFalse(beta.contains("screenshots_real"))
    }

    func testEveryGroupHasSomethingInTheStoreScope() {
        for group in SubmissionChecklist.Group.allCases {
            XCTAssertFalse(SubmissionChecklist.items(in: group, forAppStore: true).isEmpty, group.rawValue)
        }
    }

    func testVerifiedItemsTickThemselves() {
        let run = ReleaseReadinessRun(json: ["items": [
            ["key": "screenshots", "status": "automated", "required": true],
            ["key": "privacy_policy", "status": "needs_setup", "required": true],
        ]])
        XCTAssertEqual(SubmissionChecklist.autoSatisfied(from: run), ["screenshots_real"])
        XCTAssertEqual(SubmissionChecklist.autoSatisfied(from: nil), [])
    }

    func testCompleteOnlyWhenEverythingIsSettled() {
        let all = Set(SubmissionChecklist.items(forAppStore: true).map(\.id))
        XCTAssertTrue(SubmissionChecklist.isComplete(checked: all, autoSatisfied: [], forAppStore: true))
        var missingOne = all
        missingOne.remove("runs_on_device")
        XCTAssertEqual(
            SubmissionChecklist.outstanding(checked: missingOne, autoSatisfied: [], forAppStore: true).map(\.id),
            ["runs_on_device"]
        )
        XCTAssertTrue(SubmissionChecklist.isComplete(checked: missingOne, autoSatisfied: ["runs_on_device"], forAppStore: true))
    }

    func testStaleTicksForItemsThatNoLongerExistDoNotCount() {
        XCTAssertFalse(SubmissionChecklist.isComplete(checked: ["retired_item"], autoSatisfied: [], forAppStore: false))
    }
}
