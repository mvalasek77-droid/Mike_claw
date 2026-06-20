import SwiftUI

@MainActor
@Observable
final class ConversationListViewModel {
    enum State: Equatable {
        case loading
        case loaded([Conversation])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: MessagingService

    init(service: MessagingService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let convos = try await service.conversations()
            state = convos.isEmpty ? .empty : .loaded(convos)
        } catch {
            state = .error("Couldn't load messages. Pull to refresh.")
        }
    }
}
