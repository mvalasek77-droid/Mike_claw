import SwiftUI

@MainActor
@Observable
final class CreateListingViewModel {
    enum SubmitState: Equatable {
        case idle
        case submitting
        case success
        case failed(String)
    }

    var title: String = ""
    var description: String = ""
    var priceText: String = ""
    var category: ListingCategory = .gear
    private(set) var submitState: SubmitState = .idle

    private let service: MarketplaceService

    init(service: MarketplaceService) {
        self.service = service
    }

    private var price: Double? {
        priceText.isEmpty ? 0 : Double(priceText)
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        price != nil &&
        price! >= 0 &&
        submitState != .submitting
    }

    /// Submits the draft and returns the created listing on success, so the
    /// presenting screen can insert it without a full reload.
    func submit() async -> Listing? {
        guard canSubmit, let price else { return nil }
        submitState = .submitting
        let draft = ListingDraft(title: title, description: description, price: price, category: category)
        do {
            let listing = try await service.create(draft)
            submitState = .success
            HapticsEngine.shared.play(.refreshDone)
            return listing
        } catch {
            BroLog.error(error, category: "marketplace")
            submitState = .failed("Couldn't post the listing. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
            return nil
        }
    }
}
