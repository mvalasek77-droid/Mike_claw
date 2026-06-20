import SwiftUI

/// The unified MetaBro feed: social posts and Bro-hood posts fused into one
/// scroll, with a sort control and full loading / empty / error handling.
struct FeedView: View {
    private let container: AppContainer
    @State private var model: FeedViewModel
    @State private var path: [Post] = []

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: FeedViewModel(service: container.feedService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("MetaBro")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { sortMenu }
                }
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post, service: container.commentService)
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading the bros…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            ContentUnavailableView(
                "You're all caught up",
                systemImage: "checkmark.seal.fill",
                description: Text("Join a few Bro-hoods to fill your feed.")
            )

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
                            onVote: { value in Task { await model.vote(on: post, value: value) } },
                            onReact: { reaction in Task { await model.react(on: post, reaction: reaction) } },
                            onOpen: { path.append(post) }
                        )
                    }
                }
                .padding(Tokens.Spacing.lg)
            }
            .refreshable { await model.refresh() }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(FeedSort.allCases, id: \.self) { sort in
                    Text(sort.title).tag(sort)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .accessibilityLabel("Sort feed")
        }
    }
}
