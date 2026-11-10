import Foundation
import SwiftUI

/// Persists App Store Connect submission progress per app.
///
/// **Why this exists.** Submitting to the App Store is not a
/// single sitting. Step 9 alone ("wait for processing") takes 5–30
/// minutes, and steps 3 and 4 often send the user off to make an icon
/// or take screenshots. Before this, closing the guide threw away
/// every completed step and every edit the user had made to the
/// listing — they came back to a blank form and no idea where they'd
/// stopped.
///
/// Now each app gets a `Record` holding its completed steps, its live
/// metadata draft and where it stands in review, written to
/// UserDefaults on every mutation. The user can close the app
/// mid-submission, come back tomorrow, and resume on the exact step
/// they left.
@MainActor
final class ASCSubmissionStore: ObservableObject {
    static let shared = ASCSubmissionStore()

    /// The rules live in `ASCSubmissionRecord`; this type only stores.
    typealias Record = ASCSubmissionRecord

    @Published private(set) var records: [UUID: Record] = [:] {
        didSet { save() }
    }

    private static let storageKey = "codegenie.asc.submissions.v1"

    private init() {
        load()
    }

    // MARK: - Lookup

    func record(for jobID: UUID) -> Record? {
        records[jobID]
    }

    /// Every submission that isn't live yet, newest activity first.
    /// Includes ones waiting on Apple's review — that is when a
    /// first-timer most needs to find their way back.
    var inFlight: [Record] {
        records.values
            .filter { !$0.isComplete && (!$0.completedSteps.isEmpty || $0.isSubmitted) }
            .sorted { $0.lastTouchedAt > $1.lastTouchedAt }
    }

    /// The one submission Home should talk about.
    var primary: Record? {
        Journey.primarySubmission(among: Array(records.values))
    }

    // MARK: - Mutation

    /// Fetch the existing record or seed a fresh one from the app
    /// description. Seeding is idempotent — reopening the guide never
    /// clobbers edits the user already made.
    @discardableResult
    func openOrCreate(for job: BuildJob) -> Record {
        if let existing = records[job.id] { return existing }
        let fresh = Record(
            jobID: job.id,
            appTitle: job.description.title,
            metadata: AppStoreMetadata.draft(for: job.description)
        )
        records[job.id] = fresh
        return fresh
    }

    private func update(_ jobID: UUID, _ change: (inout Record) -> Void) {
        guard var record = records[jobID] else { return }
        change(&record)
        records[jobID] = record
    }

    func markStepComplete(_ step: Int, for jobID: UUID) {
        update(jobID) { $0.complete(step) }
    }

    func markStepIncomplete(_ step: Int, for jobID: UUID) {
        update(jobID) { $0.reopen(step) }
    }

    func updateMetadata(_ metadata: AppStoreMetadata, for jobID: UUID) {
        update(jobID) {
            guard $0.metadata != metadata else { return }
            $0.metadata = metadata
            $0.lastTouchedAt = .now
        }
    }

    func recordPreflight(passed: Bool, score: Double?, for jobID: UUID) {
        update(jobID) {
            $0.lastPreflightPassed = passed
            $0.lastPreflightScore = score
            $0.lastPreflightAt = .now
            $0.lastTouchedAt = .now
        }
    }

    func setChecklistItem(_ itemID: String, checked: Bool, for jobID: UUID) {
        update(jobID) {
            var items = $0.checkedItems ?? []
            if checked { items.insert(itemID) } else { items.remove(itemID) }
            $0.checkedItems = items
            $0.lastTouchedAt = .now
        }
    }

    func checkedItems(for jobID: UUID) -> Set<String> {
        records[jobID]?.checkedItems ?? []
    }

    func markSubmitted(for jobID: UUID) {
        update(jobID) { $0.markSubmitted() }
    }

    /// Fold in a review status. Returns true when it changed.
    @discardableResult
    func applyReview(_ state: ASCReviewState, version: String? = nil, for jobID: UUID) -> Bool {
        var changed = false
        update(jobID) { changed = $0.applyReview(state, version: version) }
        return changed
    }

    func markResubmitted(for jobID: UUID) {
        update(jobID) { $0.markResubmitted() }
    }

    func noteRejectionGuideline(_ guideline: String?, for jobID: UUID) {
        update(jobID) { $0.noteRejectionGuideline(guideline) }
    }

    func discard(jobID: UUID) {
        records[jobID] = nil
    }

    // MARK: - Persistence

    private func save() {
        // Set<Int> and Date are Codable; the dictionary key is a UUID
        // which JSONEncoder can't use as a dictionary key, so we
        // persist the values array and rebuild the map on load.
        let values = Array(records.values)
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Record].self, from: data)
        else { return }
        // Keyed without trapping on a duplicate: a corrupt store should
        // lose one record, not crash the app at launch.
        let migrated = decoded.map(Record.migrate)
        records = Dictionary(
            migrated.map { ($0.jobID, $0) },
            uniquingKeysWith: { a, b in a.lastTouchedAt >= b.lastTouchedAt ? a : b }
        )
    }
}
