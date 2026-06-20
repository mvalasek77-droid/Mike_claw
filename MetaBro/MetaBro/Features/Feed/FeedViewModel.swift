import SwiftUI

/// Drives the unified (social + community) feed. Owns explicit view state so
/// the View never has to guess between loading / empty / error / loaded.
@MainActor
@Observable
final class FeedViewModel {
    enum State: Equatable {
        case loading
        case loaded([Post])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    var sort: FeedSort = .hot {
        didSet { guard sort != oldValue else { return }
            Task { await load() } }
    }

    private let service: FeedService

    init(service: FeedService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let page = try await service.feed(sort: sort, cursor: nil)
            state = page.posts.isEmpty ? .empty : .loaded(page.posts)
        } catch {
            state = .error(Self.message(for: error))
        }
    }

    func refresh() async {
        // Keep current content visible during pull-to-refresh; swap on success.
        do {
            let page = try await service.feed(sort: sort, cursor: nil)
            state = page.posts.isEmpty ? .empty : .loaded(page.posts)
            HapticsEngine.shared.play(.refreshDone)
        } catch {
            HapticsEngine.shared.play(.error)
            // Only surface an error screen if we have nothing to show.
            if case .loaded = state { return }
            state = .error(Self.message(for: error))
        }
    }

    /// Optimistic vote: update the UI immediately, reconcile with the server,
    /// and roll back on failure. Idempotent and safe against rapid taps.
    func vote(on post: Post, value: VoteValue) async {
        guard case .loaded(var posts) = state,
              let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }

        let previous = posts[idx]
        posts[idx].score += value.rawValue - previous.myVote.rawValue
        posts[idx].myVote = value
        state = .loaded(posts)

        do {
            try await service.vote(postID: post.id, value: value)
        } catch {
            // Roll back to the pre-vote snapshot.
            if case .loaded(var current) = state,
               let i = current.firstIndex(where: { $0.id == post.id }) {
                current[i] = previous
                state = .loaded(current)
            }
            HapticsEngine.shared.play(.error)
        }
    }

    /// Optimistic Facebook-style reaction on a social post, rolled back on
    /// failure. Tapping your current reaction clears it.
    func react(on post: Post, reaction: ReactionKind?) async {
        guard case .loaded(var posts) = state,
              let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }

        let previous = posts[idx]
        posts[idx].reactions.apply(reaction)
        state = .loaded(posts)
        HapticsEngine.shared.play(reaction == nil ? .selectionChanged : .reaction)

        do {
            try await service.react(postID: post.id, reaction: reaction)
        } catch {
            if case .loaded(var current) = state,
               let i = current.firstIndex(where: { $0.id == post.id }) {
                current[i] = previous
                state = .loaded(current)
            }
            HapticsEngine.shared.play(.error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case APIError.offline: "You're offline. We'll catch you up when you reconnect."
        case APIError.server: "MetaBro is having a moment. Pull to try again."
        default: "Something went sideways. Pull to refresh."
        }
    }
}
