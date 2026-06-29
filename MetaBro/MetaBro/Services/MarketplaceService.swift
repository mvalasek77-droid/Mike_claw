import Foundation

protocol MarketplaceService: Sendable {
    /// Active listings first (newest first), sold listings last.
    func listings() async throws -> [Listing]
    /// Creates a listing posted by the current user and returns it.
    func create(_ draft: ListingDraft) async throws -> Listing
    func setSold(listingID: UUID, sold: Bool) async throws
    /// Sends an in-app message to the seller — no contact info is exposed.
    func contactSeller(listingID: UUID, message: String) async throws
}

/// Deterministic in-memory listings for previews, tests, and offline demo.
actor MockMarketplaceService: MarketplaceService {
    private var listings: [Listing]
    private(set) var inquiriesByListing: [UUID: [String]] = [:]

    init(listings: [Listing] = MockMarketplaceService.seed()) {
        self.listings = listings
    }

    func listings() async throws -> [Listing] {
        try await Task.sleep(nanoseconds: 200_000_000)
        let active = listings.filter { !$0.isSold }.sorted { $0.createdAt > $1.createdAt }
        let sold = listings.filter(\.isSold).sorted { $0.createdAt > $1.createdAt }
        return active + sold
    }

    func create(_ draft: ListingDraft) async throws -> Listing {
        guard draft.isValid else { throw APIError.server(status: 422) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let listing = Listing(
            id: UUID(),
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            price: draft.price,
            category: draft.category,
            seller: Session.me,
            imageURL: nil,
            createdAt: .now
        )
        listings.insert(listing, at: 0)
        return listing
    }

    func setSold(listingID: UUID, sold: Bool) async throws {
        guard let idx = listings.firstIndex(where: { $0.id == listingID }) else { return }
        listings[idx].isSold = sold
    }

    func contactSeller(listingID: UUID, message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, listings.contains(where: { $0.id == listingID }) else {
            throw APIError.server(status: 422)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        inquiriesByListing[listingID, default: []].append(trimmed)
    }

    static func seed() -> [Listing] {
        let coach = User(id: UUID(), handle: "@coachdave", displayName: "Dave", avatarURL: nil, broCred: 9_300)
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus", avatarURL: nil, broCred: 4_820)
        return [
            Listing(id: UUID(), title: "Power rack, barely used", description: "Moving, must go this weekend.",
                    price: 350, category: .gear, seller: coach, imageURL: nil,
                    createdAt: .now.addingTimeInterval(-3_600)),
            Listing(id: UUID(), title: "Truck bed tool box", description: "Fits full-size beds, some surface rust.",
                    price: 75, category: .vehicles, seller: marcus, imageURL: nil,
                    createdAt: .now.addingTimeInterval(-7_200)),
            Listing(id: UUID(), title: "Free firewood, you haul", description: "Seasoned oak, pickup only.",
                    price: 0, category: .free, seller: coach, imageURL: nil,
                    createdAt: .now.addingTimeInterval(-10_800)),
            Listing(id: UUID(), title: "Old PS4 + 2 controllers", description: "Already sold, leaving as an example.",
                    price: 120, category: .electronics, seller: marcus, imageURL: nil,
                    createdAt: .now.addingTimeInterval(-86_400), isSold: true),
        ]
    }
}
