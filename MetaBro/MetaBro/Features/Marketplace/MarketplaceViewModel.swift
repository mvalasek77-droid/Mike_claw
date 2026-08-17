import SwiftUI

/// Drives the Bro-ket listing browser, with an optional category filter.
@MainActor
@Observable
final class MarketplaceViewModel {
    enum State: Equatable {
        case loading
        case loaded([Listing])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    var categoryFilter: ListingCategory?
    private let service: MarketplaceService

    init(service: MarketplaceService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let listings = try await service.listings()
            state = listings.isEmpty ? .empty : .loaded(listings)
        } catch {
            BroLog.error(error, category: "marketplace")
            state = .error("Couldn't load the Bro-ket.")
        }
    }

    /// Inserts a freshly-created listing at the front of the loaded list.
    func created(_ listing: Listing) {
        guard case .loaded(var listings) = state else {
            state = .loaded([listing])
            return
        }
        listings.insert(listing, at: 0)
        state = .loaded(listings)
    }

    func visible(from listings: [Listing]) -> [Listing] {
        guard let categoryFilter else { return listings }
        return listings.filter { $0.category == categoryFilter }
    }
}
