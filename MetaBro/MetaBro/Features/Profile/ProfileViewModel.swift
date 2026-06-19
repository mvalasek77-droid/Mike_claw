import SwiftUI

@MainActor
@Observable
final class ProfileViewModel {
    enum State: Equatable {
        case loading
        case loaded(Profile)
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: ProfileService

    init(service: ProfileService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.myProfile())
        } catch {
            state = .error("Couldn't load your profile. Pull to refresh.")
        }
    }
}

extension Profile: Equatable {
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.user == rhs.user
        && lhs.postKarma == rhs.postKarma
        && lhs.commentKarma == rhs.commentKarma
        && lhs.joinedCommunities == rhs.joinedCommunities
        && lhs.posts == rhs.posts
    }
}
