import SwiftUI

/// Drives the listing detail screen's "message seller" composer.
@MainActor
@Observable
final class ListingDetailViewModel {
    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    let listing: Listing
    var draft: String = ""
    private(set) var sendState: SendState = .idle
    private let service: MarketplaceService

    init(listing: Listing, service: MarketplaceService) {
        self.listing = listing
        self.service = service
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sendState != .sending
    }

    func send() async {
        guard canSend else { return }
        sendState = .sending
        do {
            try await service.contactSeller(listingID: listing.id, message: draft)
            draft = ""
            sendState = .sent
            HapticsEngine.shared.play(.refreshDone)
        } catch {
            BroLog.error(error, category: "marketplace")
            sendState = .failed("Couldn't send your message. Try again.")
            HapticsEngine.shared.play(.error)
        }
    }
}
