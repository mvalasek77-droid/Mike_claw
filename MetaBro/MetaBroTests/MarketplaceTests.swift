import Testing
import Foundation
@testable import MetaBro

/// Coverage for this slice: Bro-ket listing creation, the listings list view
/// model with category filtering, and the listing detail "message seller"
/// composer.
@MainActor
struct MockMarketplaceServiceTests {

    @Test func createInsertsListingAtFront() async throws {
        let service = MockMarketplaceService(listings: [])
        let draft = ListingDraft(title: "Bench press", description: "Solid steel.",
                                  price: 150, category: .gear)

        let listing = try await service.create(draft)
        #expect(listing.seller.id == Session.me.id)

        let all = try await service.listings()
        #expect(all.first?.id == listing.id)
    }

    @Test func createRejectsEmptyTitle() async {
        let service = MockMarketplaceService(listings: [])
        let draft = ListingDraft(title: "   ", description: "", price: 10, category: .gear)
        await #expect(throws: APIError.self) {
            _ = try await service.create(draft)
        }
    }

    @Test func listingsSortsActiveBeforeSold() async throws {
        let service = MockMarketplaceService()
        let listings = try await service.listings()
        let firstSoldIndex = listings.firstIndex(where: \.isSold)
        let lastActiveIndex = listings.lastIndex(where: { !$0.isSold })
        if let firstSoldIndex, let lastActiveIndex {
            #expect(lastActiveIndex < firstSoldIndex)
        }
    }

    @Test func setSoldMarksListingSold() async throws {
        let service = MockMarketplaceService()
        let listing = try #require(try await service.listings().first { !$0.isSold })

        try await service.setSold(listingID: listing.id, sold: true)
        let updated = try #require(try await service.listings().first { $0.id == listing.id })
        #expect(updated.isSold)
    }

    @Test func contactSellerRejectsEmptyMessage() async throws {
        let service = MockMarketplaceService()
        let listing = try #require(try await service.listings().first)
        await #expect(throws: APIError.self) {
            try await service.contactSeller(listingID: listing.id, message: "   ")
        }
    }

    @Test func contactSellerRecordsInquiry() async throws {
        let service = MockMarketplaceService()
        let listing = try #require(try await service.listings().first)

        try await service.contactSeller(listingID: listing.id, message: "Still available?")
        let inquiries = await service.inquiriesByListing[listing.id]
        #expect(inquiries == ["Still available?"])
    }
}

@MainActor
struct MarketplaceViewModelTests {

    @Test func loadPopulatesListings() async {
        let model = MarketplaceViewModel(service: MockMarketplaceService())
        await model.load()
        guard case .loaded = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = MarketplaceViewModel(service: MockMarketplaceService(listings: []))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func createdInsertsAtFront() async {
        let model = MarketplaceViewModel(service: MockMarketplaceService())
        await model.load()
        let fresh = Listing(id: UUID(), title: "Fresh listing", description: "", price: 1,
                             category: .other, seller: Session.me, imageURL: nil, createdAt: .now)
        model.created(fresh)

        guard case .loaded(let listings) = model.state else {
            Issue.record("expected .loaded"); return
        }
        #expect(listings.first?.id == fresh.id)
    }

    @Test func categoryFilterNarrowsVisibleListings() async {
        let gear = Listing(id: UUID(), title: "Gear item", description: "", price: 1,
                            category: .gear, seller: Session.me, imageURL: nil, createdAt: .now)
        let vehicle = Listing(id: UUID(), title: "Vehicle item", description: "", price: 1,
                               category: .vehicles, seller: Session.me, imageURL: nil, createdAt: .now)
        let model = MarketplaceViewModel(service: MockMarketplaceService(listings: [gear, vehicle]))
        await model.load()

        model.categoryFilter = .gear
        guard case .loaded(let listings) = model.state else {
            Issue.record("expected .loaded"); return
        }
        let visible = model.visible(from: listings)
        #expect(visible.map(\.id) == [gear.id])
    }
}

@MainActor
struct ListingDetailViewModelTests {

    @Test func sendDeliversMessageAndClearsDraft() async throws {
        let service = MockMarketplaceService()
        let listing = try #require(try await service.listings().first)
        let model = ListingDetailViewModel(listing: listing, service: service)

        model.draft = "Is this still for sale?"
        await model.send()

        #expect(model.draft.isEmpty)
        #expect(model.sendState == .sent)
    }

    @Test func sendRollsBackToFailedOnError() async {
        let listing = Listing(id: UUID(), title: "Test listing", description: "", price: 10,
                               category: .gear, seller: Session.me, imageURL: nil, createdAt: .now)
        let model = ListingDetailViewModel(listing: listing, service: FailingMarketplaceService())

        model.draft = "Interested!"
        await model.send()

        guard case .failed = model.sendState else {
            Issue.record("expected .failed, got \(model.sendState)"); return
        }
        #expect(model.draft == "Interested!") // not cleared on failure
    }
}

private struct FailingMarketplaceService: MarketplaceService {
    func listings() async throws -> [Listing] { [] }
    func create(_ draft: ListingDraft) async throws -> Listing {
        throw APIError.server(status: 500)
    }
    func setSold(listingID: UUID, sold: Bool) async throws {
        throw APIError.server(status: 500)
    }
    func contactSeller(listingID: UUID, message: String) async throws {
        throw APIError.server(status: 500)
    }
}
