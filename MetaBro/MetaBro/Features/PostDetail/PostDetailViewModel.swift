import SwiftUI

/// Owns the comment thread for one post: load, collapse/expand, optimistic
/// voting with rollback, and replying. Exposes a flat, depth-annotated list so
/// the View renders a `LazyVStack` (cheap, virtualized) instead of recursion.
@MainActor
@Observable
final class PostDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var post: Post
    private(set) var state: State = .loading
    private(set) var comments: [Comment] = []
    private var collapsed: Set<UUID> = []

    /// Display-ready list: depth-annotated and honoring collapsed subtrees.
    var visible: [ThreadedComment] {
        CommentTree.flatten(comments, collapsed: collapsed)
    }

    private let service: CommentService
    private let moderationService: ModerationService

    init(post: Post, service: CommentService, moderationService: ModerationService) {
        self.post = post
        self.service = service
        self.moderationService = moderationService
    }

    /// Mods can pin/lock their own Bro-hood's posts.
    var canModerate: Bool { post.community?.isModerator == true }

    func togglePin() async {
        let wasPinned = post.isPinned
        post.isPinned.toggle()
        HapticsEngine.shared.play(.selectionChanged)
        do {
            if post.isPinned { try await moderationService.pin(postID: post.id) }
            else { try await moderationService.unpin(postID: post.id) }
        } catch {
            BroLog.error(error, category: "moderation")
            post.isPinned = wasPinned
            HapticsEngine.shared.play(.error)
        }
    }

    func toggleLock() async {
        let wasLocked = post.isLocked
        post.isLocked.toggle()
        HapticsEngine.shared.play(.selectionChanged)
        do {
            if post.isLocked { try await moderationService.lock(postID: post.id) }
            else { try await moderationService.unlock(postID: post.id) }
        } catch {
            BroLog.error(error, category: "moderation")
            post.isLocked = wasLocked
            HapticsEngine.shared.play(.error)
        }
    }

    func load() async {
        state = .loading
        do {
            comments = try await service.comments(for: post.id)
            state = comments.isEmpty ? .empty : .loaded
        } catch {
            BroLog.error(error, category: "postDetail")
            state = .error(message(for: error))
        }
    }

    func isCollapsed(_ id: UUID) -> Bool { collapsed.contains(id) }

    func toggleCollapse(_ id: UUID) {
        HapticsEngine.shared.play(.selectionChanged)
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    /// Optimistic vote on a comment, rolled back on failure.
    func vote(on comment: Comment, value: VoteValue) async {
        guard let idx = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let previous = comments[idx]
        comments[idx].score += value.rawValue - previous.myVote.rawValue
        comments[idx].myVote = value

        do {
            try await service.vote(commentID: comment.id, value: value)
        } catch {
            BroLog.error(error, category: "postDetail")
            if let i = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[i] = previous
            }
            HapticsEngine.shared.play(.error)
        }
    }

    /// Posts a reply and inserts it locally on success.
    func reply(to parentID: UUID?, body: String) async {
        do {
            let new = try await service.reply(to: post.id, parentID: parentID, body: body)
            comments.append(new)
            state = .loaded
            HapticsEngine.shared.play(.reaction)
        } catch {
            BroLog.error(error, category: "postDetail")
            HapticsEngine.shared.play(.error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case APIError.offline: "You're offline. Reconnect to see the discussion."
        default: "Couldn't load the thread. Pull to refresh."
        }
    }
}
