import SwiftUI

/// Lists everything the current user has bookmarked, newest-saved first.
@MainActor
@Observable
final class SavedViewModel {
    enum State: Equatable {
        case loading
        case loaded([Post])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: SavedService

    init(service: SavedService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let posts = try await service.savedPosts()
            state = posts.isEmpty ? .empty : .loaded(posts)
        } catch {
            BroLog.error(error, category: "saved")
            state = .error("Couldn't load your saved posts.")
        }
    }

    /// Optimistically drops a post from the list when unsaved from this screen.
    func unsave(_ post: Post) async {
        guard case .loaded(var posts) = state else { return }
        posts.removeAll { $0.id == post.id }
        state = posts.isEmpty ? .empty : .loaded(posts)
        HapticsEngine.shared.play(.selectionChanged)

        do {
            try await service.setSaved(postID: post.id, saved: false)
        } catch {
            BroLog.error(error, category: "saved")
            await load()
            HapticsEngine.shared.play(.error)
        }
    }
}
