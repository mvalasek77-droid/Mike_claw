import SwiftUI

/// Single source of truth for the catalogue, the signed-in creator's account,
/// their publishing pipeline, and their purchased library.
///
/// All user-owned state (identity, entitlements, drafts, earnings) is persisted
/// encrypted-at-rest via ``EncryptedArchive``.
@MainActor
final class MarketplaceStore: ObservableObject {
    // Account (KDP-style registration)
    @Published var accountName: String = "" { didSet { persist() } }
    @Published var accountEmail: String = "" { didSet { persist() } }
    @Published var isRegistered: Bool = false { didSet { persist() } }

    // Marketplace
    @Published private(set) var catalog: [MediaItem]
    @Published var submissions: [Submission] = [] { didSet { persist() } }
    @Published private(set) var libraryIDs: Set<UUID> = []
    @Published var watchlistIDs: Set<UUID> = [] { didSet { persist() } }

    /// Simulated wallet so purchases feel real in the demo.
    @Published var walletBalance: Double = 50.00 { didSet { persist() } }
    /// Lifetime royalties paid out to the creator for their live titles.
    @Published var creatorEarnings: Double = 0 { didSet { persist() } }
    /// When on, the AI Editor may publish a passing title on its own, without
    /// the creator tapping Publish — but only when it's confident enough.
    @Published var aiAutopilotEnabled: Bool = false { didSet { persist() } }

    private let archive = EncryptedArchive()
    private var loading = false

    init(catalog: [MediaItem] = SampleData.catalog()) {
        self.catalog = catalog
        restore()
        fillEditorOriginals()
    }

    /// Lets the AI Editor top up any thin categories with its own high-quality
    /// Originals, counting whatever creators have already published.
    private func fillEditorOriginals() {
        let existing = Set(catalog.map(\.id))
        let originals = ContentFoundry.fillGaps(in: catalog).filter { !existing.contains($0.id) }
        catalog.append(contentsOf: originals)
    }

    /// Titles the AI Editor produced itself to fill open space.
    var editorOriginals: [MediaItem] {
        catalog.filter { $0.isEditorOriginal }.sorted { $0.commercialScore > $1.commercialScore }
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var accountName: String
        var accountEmail: String
        var isRegistered: Bool
        var walletBalance: Double
        var creatorEarnings: Double
        var aiAutopilotEnabled: Bool
        var libraryIDs: [UUID]
        var watchlistIDs: [UUID]
        var submissions: [Submission]
        var publishedItems: [MediaItem]
    }

    private func restore() {
        guard let state = archive.load(PersistedState.self) else { return }
        loading = true
        // Merge any user-published titles back into the live catalogue.
        let existingIDs = Set(catalog.map(\.id))
        catalog.append(contentsOf: state.publishedItems.filter { !existingIDs.contains($0.id) })
        accountName = state.accountName
        accountEmail = state.accountEmail
        isRegistered = state.isRegistered
        walletBalance = state.walletBalance
        creatorEarnings = state.creatorEarnings
        aiAutopilotEnabled = state.aiAutopilotEnabled
        libraryIDs = Set(state.libraryIDs)
        watchlistIDs = Set(state.watchlistIDs)
        submissions = state.submissions
        loading = false
    }

    private func persist() {
        guard !loading else { return }
        let publishedIDs = Set(submissions.compactMap(\.publishedItemID))
        let publishedItems = catalog.filter { publishedIDs.contains($0.id) }
        let state = PersistedState(
            accountName: accountName,
            accountEmail: accountEmail,
            isRegistered: isRegistered,
            walletBalance: walletBalance,
            creatorEarnings: creatorEarnings,
            aiAutopilotEnabled: aiAutopilotEnabled,
            libraryIDs: Array(libraryIDs),
            watchlistIDs: Array(watchlistIDs),
            submissions: submissions,
            publishedItems: publishedItems
        )
        archive.save(state)
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

    /// Per-model portfolios, ranked by reach — the AI Spotlight.
    var aiStudios: [AIStudio] { AIStudioCatalog.build(from: catalog) }

    func studio(named name: String) -> AIStudio? {
        aiStudios.first { $0.name == name }
    }

    /// Distinct genres across the catalogue, for browse-by-genre and search.
    var genres: [String] {
        Array(Set(catalog.map { $0.genre.trimmed }.filter { !$0.isEmpty })).sorted()
    }

    /// Free-text search across title, creator, genre, synopsis and AI tools.
    func search(_ query: String) -> [MediaItem] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return catalog
            .filter { item in
                item.title.lowercased().contains(q)
                || item.creator.lowercased().contains(q)
                || item.genre.lowercased().contains(q)
                || item.synopsis.lowercased().contains(q)
                || item.aiTools.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.commercialScore > $1.commercialScore }
    }

    func rank(of item: MediaItem) -> Int? {
        guard let idx = topTen.firstIndex(of: item) else { return nil }
        return idx + 1
    }

    // MARK: - Library / purchases

    func owns(_ item: MediaItem) -> Bool { libraryIDs.contains(item.id) }

    var library: [MediaItem] { catalog.filter { libraryIDs.contains($0.id) } }

    /// Grants the entitlement after a successful payment (wallet or Apple Pay).
    func grantPurchase(_ item: MediaItem, chargeWallet: Bool) {
        guard !owns(item) else { return }
        if chargeWallet { walletBalance = max(0, walletBalance - item.price) }
        libraryIDs.insert(item.id)
        bumpPurchase(item.id)
        if submissions.contains(where: { $0.publishedItemID == item.id }) {
            creatorEarnings += Commerce.creatorEarning(on: item.price)
        }
        persist()
        Haptics.success()
    }

    /// Wallet purchase. Returns false if the balance is insufficient.
    @discardableResult
    func purchase(_ item: MediaItem) -> Bool {
        guard !owns(item) else { return true }
        guard walletBalance >= item.price else { return false }
        grantPurchase(item, chargeWallet: true)
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

    @discardableResult
    func runReview(for submissionID: UUID) -> AIReviewResult? {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }) else { return nil }
        let result = AIEditor.review(submissions[idx].draft)
        submissions[idx].review = result
        submissions[idx].status = result.passed ? .accepted : .rejected
        return result
    }

    func createSubmission(_ draft: DraftWork) -> UUID {
        let submission = Submission(draft: draft, status: .reviewing)
        submissions.insert(submission, at: 0)
        return submission.id
    }

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
            addedAt: .now,
            coverImageData: d.coverImageData
        )
        catalog.insert(item, at: 0)
        submissions[idx].publishedItemID = item.id
        persist()
        Haptics.success()
    }

    func submission(withPublishedID id: UUID) -> Submission? {
        submissions.first { $0.publishedItemID == id }
    }

    /// Titles the signed-in creator has published live.
    var liveTitles: [MediaItem] {
        let ids = Set(submissions.compactMap(\.publishedItemID))
        return catalog.filter { ids.contains($0.id) }
    }
}
