import SwiftUI

/// Bookmarked posts, tappable through to their threads; swipe or tap the
/// bookmark icon again to unsave.
struct SavedView: View {
    private let container: AppContainer
    @State private var model: SavedViewModel
    @State private var path: [Post] = []

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: SavedViewModel(service: container.savedService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Saved")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post, service: container.commentService,
                                    safetyService: container.safetyService,
                                    moderationService: container.moderationService)
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                   description: Text("Tap the bookmark on any post to save it for later."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let posts):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.lg) {
                    ForEach(posts) { post in
                        PostCardView(
                            post: post,
                            onVote: { _ in },
                            onSave: { Task { await model.unsave(post) } },
                            onOpen: { path.append(post) },
                            safetyService: container.safetyService
                        )
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: posts)
            }
            .refreshable { await model.load() }
        }
    }
}
