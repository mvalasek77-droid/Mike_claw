import Foundation

/// One app's progress through App Store Connect, from the first sign-in
/// to live on the store.
///
/// A plain value with no storage of its own, so every rule about what
/// counts as done — including what a status from Apple implies — can be
/// exercised without a device.
struct ASCSubmissionRecord: Codable, Identifiable, Hashable {
    /// The iOS-side BuildJob id this submission belongs to.
    let jobID: UUID
    var appTitle: String
    var completedSteps: Set<Int>
    var metadata: AppStoreMetadata
    var startedAt: Date
    var lastTouchedAt: Date
    /// Set once the user has confirmed they pressed Submit in ASC.
    var submittedAt: Date?
    var lastPreflightPassed: Bool?
    var lastPreflightScore: Double?
    var lastPreflightAt: Date?
    /// Submission-checklist items the user has personally ticked.
    ///
    /// Optional, not a defaulted non-optional: Swift's synthesized
    /// decoder throws on a missing key rather than using the default,
    /// and one bad record would discard every saved submission.
    var checkedItems: Set<String>?
    /// Which numbering `completedSteps` uses. Absent means the original
    /// twelve-step list.
    var schema: Int?
    /// Present from the moment the version is submitted.
    var review: ASCReviewProgress?
    /// What the user found when they worked through the test plan,
    /// keyed by test id.
    var testResults: [String: TestResult]?
    /// The opening tutorial has been read (or deliberately skipped).
    var tutorialSeen: Bool?
    /// The "what happens now" explanation was shown after submitting.
    var afterSubmissionSeen: Bool?

    var id: UUID { jobID }

    init(
        jobID: UUID,
        appTitle: String,
        metadata: AppStoreMetadata,
        now: Date = Date()
    ) {
        self.jobID = jobID
        self.appTitle = appTitle
        self.completedSteps = []
        self.metadata = metadata
        self.startedAt = now
        self.lastTouchedAt = now
        self.submittedAt = nil
        self.lastPreflightPassed = nil
        self.lastPreflightScore = nil
        self.lastPreflightAt = nil
        self.checkedItems = []
        self.schema = ASCStep.schemaVersion
        self.review = nil
        self.testResults = [:]
        self.tutorialSeen = false
        self.afterSubmissionSeen = false
    }

    // MARK: - Reading

    var isSubmitted: Bool { submittedAt != nil }

    /// Finished means live on the store, not merely submitted. A record
    /// used to count as complete the moment the user pressed Submit,
    /// which dropped it from Home exactly when review began.
    var isComplete: Bool {
        review?.state == .live || completedSteps.count >= ASCStep.all.count
    }

    var progressFraction: Double {
        min(1, Double(completedSteps.count) / Double(ASCStep.all.count))
    }

    /// The step the user should land on when they resume.
    var resumeStep: Int {
        (1...ASCStep.all.count).first { !completedSteps.contains($0) } ?? ASCStep.all.count
    }

    func isPhaseComplete(_ phase: ASCPhase) -> Bool {
        ASCStep.steps(in: phase).allSatisfy { completedSteps.contains($0.number) }
    }

    /// One line for Home and the Apps tab.
    var statusLine: String {
        if let review, isSubmitted { return review.state.headline }
        return "Step \(resumeStep) of \(ASCStep.all.count)"
    }

    /// The user has something to do, as opposed to waiting on Apple.
    var needsAttention: Bool {
        guard let review, isSubmitted else { return !isComplete }
        return review.state.tone == .action || review.state.tone == .problem
    }

    // MARK: - Changing

    mutating func complete(_ step: Int, at date: Date = Date()) {
        guard ASCStep.step(step) != nil else { return }
        completedSteps.insert(step)
        lastTouchedAt = date
    }

    // MARK: - Testing

    var results: [String: TestResult] { testResults ?? [:] }

    /// Record one test's outcome, then let the testing steps follow
    /// from the results. Passing nil clears a result.
    mutating func setTestResult(
        _ result: TestResult?,
        for testID: String,
        in plan: [TestCase],
        at date: Date = Date()
    ) {
        var all = testResults ?? [:]
        all[testID] = result
        testResults = all
        lastTouchedAt = date
        syncTestSteps(with: plan)
    }

    /// The test steps are never ticked on trust: the first is done
    /// when the required tests have all been tried and none is
    /// failing, and the verdict cannot stand once something fails.
    mutating func syncTestSteps(with plan: [TestCase]) {
        let summary = TestPlan.summary(of: plan, results: results)
        if summary.isPassing {
            completedSteps.insert(ASCStep.testPlanStepNumber)
        } else {
            completedSteps.remove(ASCStep.testPlanStepNumber)
            completedSteps.remove(ASCStep.testVerdictStepNumber)
        }
    }

    /// The user declares testing finished. Refused while anything is
    /// untested or failing. Returns whether it was accepted.
    @discardableResult
    mutating func confirmTestingPassed(with plan: [TestCase], at date: Date = Date()) -> Bool {
        guard TestPlan.summary(of: plan, results: results).isPassing else { return false }
        completedSteps.insert(ASCStep.testPlanStepNumber)
        completedSteps.insert(ASCStep.testVerdictStepNumber)
        lastTouchedAt = date
        return true
    }

    /// A fresh build replaces the one that was tested, so what was
    /// learned about the old one no longer counts. The upload has to
    /// be repeated too.
    mutating func resetForNewBuild(at date: Date = Date()) {
        testResults = [:]
        let stale = [
            ASCStep.uploadStepNumber, ASCStep.processingStepNumber, 8,
            ASCStep.testPlanStepNumber, 10, ASCStep.testVerdictStepNumber,
            ASCStep.buildSelectionStepNumber,
        ]
        completedSteps.subtract(stale)
        lastTouchedAt = date
    }

    var isTestingComplete: Bool { isPhaseComplete(.testing) }

    mutating func reopen(_ step: Int, at date: Date = Date()) {
        completedSteps.remove(step)
        lastTouchedAt = date
    }

    /// The user confirms they pressed Submit for Review.
    mutating func markSubmitted(at date: Date = Date()) {
        submittedAt = date
        completedSteps.formUnion(1...ASCStep.submitStepNumber)
        if review == nil { review = ASCReviewProgress(state: .waitingForReview, at: date) }
        lastTouchedAt = date
    }

    /// Fold in a status from Apple, or one the user read off the page.
    ///
    /// The review steps are never ticked by hand: they follow from the
    /// status, so the guide cannot claim "approved" while Apple says
    /// "rejected". Returns true when the status changed.
    @discardableResult
    mutating func applyReview(
        _ state: ASCReviewState,
        version: String? = nil,
        at date: Date = Date()
    ) -> Bool {
        if !isSubmitted {
            // Before submission "Prepare for Submission" is simply
            // where every version starts, and tells us nothing.
            guard state != .notSubmitted, state != .unknown else { return false }
            // Apple says it is in the pipeline, so it was submitted —
            // from the website, say, without coming back to tap here.
            markSubmitted(at: date)
        }

        var progress = review ?? ASCReviewProgress(state: .waitingForReview, at: date)
        let changed = progress.observe(state, version: version, at: date)
        review = progress
        lastTouchedAt = date
        syncReviewSteps()
        return changed
    }

    mutating func markResubmitted(at date: Date = Date()) {
        var progress = review ?? ASCReviewProgress(state: .waitingForReview, at: date)
        progress.markResubmitted(at: date)
        review = progress
        if submittedAt == nil { submittedAt = date }
        completedSteps.formUnion(1...ASCStep.submitStepNumber)
        lastTouchedAt = date
        syncReviewSteps()
    }

    mutating func noteRejectionGuideline(_ guideline: String?, at date: Date = Date()) {
        guard var progress = review else { return }
        progress.rejectionGuideline = guideline
        review = progress
        lastTouchedAt = date
    }

    private mutating func syncReviewSteps() {
        guard let state = review?.state else { return }
        let queue = ASCStep.queueStepNumber
        let decision = ASCStep.decisionStepNumber
        let release = ASCStep.releaseStepNumber

        // Withdrawn, or bounced back to the start: Submit has to be
        // pressed again, so the submit step reopens too.
        if state == .notSubmitted || state == .developerRejected {
            completedSteps.subtract([ASCStep.submitStepNumber, queue, decision, release])
            return
        }
        set(queue, done: state.hasLeftQueue)
        set(decision, done: state.isApproved)
        set(release, done: state == .live)
    }

    private mutating func set(_ step: Int, done: Bool) {
        if done { completedSteps.insert(step) } else { completedSteps.remove(step) }
    }

    // MARK: - Migration

    /// Bring a saved record up to the current step numbering.
    ///
    /// The list has been renumbered twice: once when the store steps
    /// and review were added, and again when the Mac part became a
    /// walkthrough in Xcode and testing became its own phase. Each hop
    /// is applied in turn, so a record from any version lands correctly.
    static func migrate(_ record: ASCSubmissionRecord) -> ASCSubmissionRecord {
        var out = record
        var version = record.schema ?? 1
        guard version < ASCStep.schemaVersion else { return record }

        if version == 1 {
            // Twelve steps → eighteen: pricing moved from 11 to 12 and
            // submit from 12 to 15.
            let moved: [Int: Int] = [11: 12, 12: 15]
            out.completedSteps = Set(out.completedSteps.compactMap { old in
                (1...12).contains(old) ? (moved[old] ?? old) : nil
            })
            if out.submittedAt != nil { out.completedSteps.formUnion(1...15) }
            version = 2
        }

        if version == 2 {
            // Eighteen → twenty-three. The single "upload" step became
            // five Xcode steps, and testing gained two steps of its own.
            var next: Set<Int> = []
            for old in out.completedSteps {
                switch old {
                case 1: break                       // sign-in, now part of step 5
                case 2: next.insert(5)              // app record
                case 3: next.formUnion([1, 2, 3, 4, ASCStep.uploadStepNumber])
                case 4: next.insert(ASCStep.processingStepNumber)
                case 5: next.insert(8)              // TestFlight install
                case 6: next.insert(10)             // invite testers
                case 7...15: next.insert(old + 5)   // store steps
                default: break                      // review steps follow the status
                }
            }
            out.completedSteps = next
            version = 3
        }

        if let submitted = out.submittedAt {
            // Already with Apple: everything before Submit happened,
            // including testing, which there is no way to re-prove.
            out.completedSteps.formUnion(1...ASCStep.submitStepNumber)
            if out.review == nil {
                out.review = ASCReviewProgress(state: .waitingForReview, at: submitted)
            }
            out.afterSubmissionSeen = true
        }
        out.schema = ASCStep.schemaVersion
        if out.review != nil { out.syncReviewSteps() }
        return out
    }
}
