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
/// Now each app gets a `Record` holding its completed steps and its
/// live metadata draft, written to UserDefaults on every mutation. The
/// user can close the app mid-submission, come back tomorrow, and
/// resume on the exact step they left.
@MainActor
final class ASCSubmissionStore: ObservableObject {
    static let shared = ASCSubmissionStore()

    struct Record: Codable, Identifiable, Hashable {
        /// The iOS-side BuildJob id this submission belongs to.
        let jobID: UUID
        var appTitle: String
        var completedSteps: Set<Int>
        var metadata: AppStoreMetadata
        var startedAt: Date
        var lastTouchedAt: Date
        /// Set once the user has confirmed they pressed Submit in ASC.
        var submittedAt: Date?
        /// Result of the last mandatory pre-flight check (Perfection
        /// Mode). Recorded so the guide can show "last checked" even
        /// before a fresh recheck completes, and so Home's callout can
        /// tell the difference between "hasn't started" and "was
        /// blocked last time".
        var lastPreflightPassed: Bool?
        var lastPreflightScore: Double?
        var lastPreflightAt: Date?

        var id: UUID { jobID }

        var isComplete: Bool { submittedAt != nil }

        var progressFraction: Double {
            Double(completedSteps.count) / Double(ASCStep.all.count)
        }

        /// The step the user should land on when they resume.
        var resumeStep: Int {
            (1...ASCStep.all.count).first { !completedSteps.contains($0) }
                ?? ASCStep.all.count
        }
    }

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

    /// Every in-flight submission, newest activity first. Drives the
    /// "Continue submission" callout on Home.
    var inFlight: [Record] {
        records.values
            .filter { !$0.isComplete && !$0.completedSteps.isEmpty }
            .sorted { $0.lastTouchedAt > $1.lastTouchedAt }
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
            completedSteps: [],
            metadata: AppStoreMetadata.draft(for: job.description),
            startedAt: .now,
            lastTouchedAt: .now,
            submittedAt: nil,
            lastPreflightPassed: nil,
            lastPreflightScore: nil,
            lastPreflightAt: nil
        )
        records[job.id] = fresh
        return fresh
    }

    func markStepComplete(_ step: Int, for jobID: UUID) {
        guard var r = records[jobID] else { return }
        r.completedSteps.insert(step)
        r.lastTouchedAt = .now
        records[jobID] = r
    }

    func markStepIncomplete(_ step: Int, for jobID: UUID) {
        guard var r = records[jobID] else { return }
        r.completedSteps.remove(step)
        r.lastTouchedAt = .now
        records[jobID] = r
    }

    func updateMetadata(_ metadata: AppStoreMetadata, for jobID: UUID) {
        guard var r = records[jobID] else { return }
        r.metadata = metadata
        r.lastTouchedAt = .now
        records[jobID] = r
    }

    func recordPreflight(passed: Bool, score: Double?, for jobID: UUID) {
        guard var r = records[jobID] else { return }
        r.lastPreflightPassed = passed
        r.lastPreflightScore = score
        r.lastPreflightAt = .now
        r.lastTouchedAt = .now
        records[jobID] = r
    }

    func markSubmitted(for jobID: UUID) {
        guard var r = records[jobID] else { return }
        r.submittedAt = .now
        r.completedSteps = Set(1...ASCStep.all.count)
        r.lastTouchedAt = .now
        records[jobID] = r
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
        records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.jobID, $0) })
    }
}
