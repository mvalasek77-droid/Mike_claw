import SwiftUI

@MainActor
@Observable
final class CreateGroupViewModel {
    enum SubmitState: Equatable {
        case idle
        case submitting
        case success
        case failed(String)
    }

    var name: String = ""
    var description: String = ""
    var selectedFriends: Set<User> = []
    private(set) var submitState: SubmitState = .idle
    private(set) var friends: [User] = []

    private let service: GroupService
    private let friendsService: FriendsService

    init(service: GroupService, friendsService: FriendsService) {
        self.service = service
        self.friendsService = friendsService
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedFriends.isEmpty &&
        submitState != .submitting
    }

    func loadFriends() async {
        friends = (try? await friendsService.friends()) ?? []
    }

    func toggle(_ friend: User) {
        if selectedFriends.contains(friend) {
            selectedFriends.remove(friend)
        } else {
            selectedFriends.insert(friend)
        }
    }

    /// Submits the draft and returns the created group on success, so the
    /// presenting screen can insert it without a full reload.
    func submit() async -> FriendGroup? {
        guard canSubmit else { return nil }
        submitState = .submitting
        let draft = GroupDraft(name: name, description: description, members: Array(selectedFriends))
        do {
            let group = try await service.create(draft)
            submitState = .success
            HapticsEngine.shared.play(.refreshDone)
            return group
        } catch {
            BroLog.error(error, category: "groups")
            submitState = .failed("Couldn't create the group. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
            return nil
        }
    }
}
