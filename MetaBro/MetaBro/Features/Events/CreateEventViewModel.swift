import SwiftUI

@MainActor
@Observable
final class CreateEventViewModel {
    enum SubmitState: Equatable {
        case idle
        case submitting
        case success
        case failed(String)
    }

    var title: String = ""
    var details: String = ""
    var location: String = ""
    var startDate: Date = .now.addingTimeInterval(86_400)
    var community: Community?
    private(set) var submitState: SubmitState = .idle
    private(set) var communities: [Community] = []

    private let service: EventService
    private let communityService: CommunityService

    init(service: EventService, communityService: CommunityService) {
        self.service = service
        self.communityService = communityService
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        submitState != .submitting
    }

    func loadCommunities() async {
        communities = (try? await communityService.discover())?.filter(\.isJoined) ?? []
    }

    /// Submits the draft and returns the created event on success, so the
    /// presenting screen can insert it without a full reload.
    func submit() async -> Event? {
        guard canSubmit else { return nil }
        submitState = .submitting
        let draft = EventDraft(title: title, details: details, community: community,
                               location: location, startDate: startDate)
        do {
            let event = try await service.create(draft)
            submitState = .success
            HapticsEngine.shared.play(.refreshDone)
            return event
        } catch {
            BroLog.error(error, category: "events")
            submitState = .failed("Couldn't create the event. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
            return nil
        }
    }
}
