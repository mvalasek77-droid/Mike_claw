import SwiftUI

/// Drives a single group's private feed: load, post, and an optimistic like
/// toggle with rollback.
@MainActor
@Observable
final class GroupDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded([GroupPost])
        case empty
        case error(String)
    }

    let group: FriendGroup
    private(set) var state: State = .loading
    var draft: String = ""
    private(set) var isPosting = false
    private let service: GroupService

    init(group: FriendGroup, service: GroupService) {
        self.group = group
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let posts = try await service.posts(in: group.id)
            state = posts.isEmpty ? .empty : .loaded(posts)
        } catch {
            BroLog.error(error, category: "groups")
            state = .error("Couldn't load this group's posts.")
        }
    }

    func post() async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let post = try await service.createPost(in: group.id, body: trimmed)
            draft = ""
            if case .loaded(var posts) = state {
                posts.insert(post, at: 0)
                state = .loaded(posts)
            } else {
                state = .loaded([post])
            }
            HapticsEngine.shared.play(.refreshDone)
        } catch {
            BroLog.error(error, category: "groups")
            HapticsEngine.shared.play(.error)
        }
    }

    /// Optimistic like toggle, rolled back on failure.
    func toggleLike(_ post: GroupPost) async {
        guard case .loaded(var posts) = state,
              let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }

        let previous = posts[idx]
        let liked = !previous.likedByMe
        posts[idx].likedByMe = liked
        posts[idx].likeCount += liked ? 1 : -1
        state = .loaded(posts)
        HapticsEngine.shared.play(.selectionChanged)

        do {
            try await service.setLiked(groupID: group.id, postID: post.id, liked: liked)
        } catch {
            BroLog.error(error, category: "groups")
            if case .loaded(var current) = state,
               let i = current.firstIndex(where: { $0.id == post.id }) {
                current[i] = previous
                state = .loaded(current)
            }
            HapticsEngine.shared.play(.error)
        }
    }
}
