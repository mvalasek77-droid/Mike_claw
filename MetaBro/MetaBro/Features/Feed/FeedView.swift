import SwiftUI

/// The unified MetaBro feed: social posts and Bro-hood posts fused into one
/// scroll, with a sort control and full loading / empty / error handling.
struct FeedView: View {
    @State private var model: FeedViewModel

    init(service: FeedService) {
        _model = State(initialValue: FeedViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("MetaBro")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { sortMenu }
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
                        PostCardView(post: post) { value in
                            Task { await model.vote(on: post, value: value) }
                        }
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
