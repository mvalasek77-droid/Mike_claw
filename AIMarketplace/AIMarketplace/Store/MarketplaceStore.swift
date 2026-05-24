import SwiftUI

/// Single source of truth for the catalogue, the signed-in creator's account,
/// their publishing pipeline, and their purchased library.
@MainActor
final class MarketplaceStore: ObservableObject {
    // Account (KDP-style registration)
    @Published var accountName: String = ""
    @Published var accountEmail: String = ""
    @Published var isRegistered: Bool = false

    // Marketplace
    @Published private(set) var catalog: [MediaItem]
    @Published var submissions: [Submission] = []
    @Published private(set) var libraryIDs: Set<UUID> = []
    @Published var watchlistIDs: Set<UUID> = []

    /// Simulated wallet so purchases feel real in the demo.
    @Published var walletBalance: Double = 50.00
    /// Lifetime royalties paid out to the creator for their live titles.
    @Published var creatorEarnings: Double = 0

    init(catalog: [MediaItem] = SampleData.catalog()) {
        self.catalog = catalog
    }

    // MARK: - Derived feeds

    var topTen: [MediaItem] {
        Array(catalog.sorted { $0.purchases > $1.purchases }.prefix(10))
    }

    var trending: [MediaItem] {
        catalog.sorted { $0.trending > $1.trending }
    }

    var newReleases: [MediaItem] {
        catalog.sorted { $0.addedAt > $1.addedAt }
    }

    /// The marquee title for the home hero — highest momentum overall.
    var featured: MediaItem? { trending.first }

    func items(of type: MediaType) -> [MediaItem] {
        catalog.filter { $0.type == type }.sorted { $0.commercialScore > $1.commercialScore }
    }

    func rank(of item: MediaItem) -> Int? {
        guard let idx = topTen.firstIndex(of: item) else { return nil }
        return idx + 1
    }

    // MARK: - Library / purchases

    func owns(_ item: MediaItem) -> Bool { libraryIDs.contains(item.id) }

    var library: [MediaItem] { catalog.filter { libraryIDs.contains($0.id) } }

    @discardableResult
    func purchase(_ item: MediaItem) -> Bool {
        guard !owns(item) else { return true }
        guard walletBalance >= item.price else { return false }
        walletBalance -= item.price
        libraryIDs.insert(item.id)
        bumpPurchase(item.id)
        // Royalty flows to the creator if it's one of the user's own titles.
        if submissions.contains(where: { $0.publishedItemID == item.id }) {
            creatorEarnings += item.price * 0.70
        }
        Haptics.success()
        return true
    }

    func toggleWatchlist(_ item: MediaItem) {
        if watchlistIDs.contains(item.id) { watchlistIDs.remove(item.id) }
        else { watchlistIDs.insert(item.id) }
    }

    private func bumpPurchase(_ id: UUID) {
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].purchases += 1
        catalog[idx].trending = min(100, catalog[idx].trending + 1)
    }

    // MARK: - Publishing pipeline

    /// Runs the AI Editor over a draft and records the outcome on a submission.
    @discardableResult
    func runReview(for submissionID: UUID) -> AIReviewResult? {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }) else { return nil }
        let result = AIEditor.review(submissions[idx].draft)
        submissions[idx].review = result
        submissions[idx].status = result.passed ? .accepted : .rejected
        return result
    }

    /// Creates a submission record from a freshly assembled draft.
    func createSubmission(_ draft: DraftWork) -> UUID {
        let submission = Submission(draft: draft, status: .reviewing)
        submissions.insert(submission, at: 0)
        return submission.id
    }

    /// Pushes an accepted submission live to the marketplace catalogue.
    func publish(submissionID: UUID) {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }),
              let review = submissions[idx].review, review.passed,
              submissions[idx].publishedItemID == nil
        else { return }

        let d = submissions[idx].draft
        let item = MediaItem(
            title: d.title.trimmed,
            creator: d.creator.trimmed,
            type: d.type,
            genre: d.genre.trimmed,
            synopsis: d.synopsis.trimmed,
            aiTools: d.aiTools,
            commercialScore: review.overall,
            price: d.price,
            length: d.length,
            maturity: d.maturity,
            purchases: 0,
            trending: 60,
            addedAt: .now
        )
        catalog.insert(item, at: 0)
        submissions[idx].publishedItemID = item.id
        Haptics.success()
    }

    func submission(withPublishedID id: UUID) -> Submission? {
        submissions.first { $0.publishedItemID == id }
    }
}
