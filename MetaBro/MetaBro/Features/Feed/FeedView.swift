import SwiftUI

/// The unified MetaBro feed: social posts and Bro-hood posts fused into one
/// scroll, with a sort control and full loading / empty / error handling.
struct FeedView: View {
    private let container: AppContainer
    @State private var model: FeedViewModel
    @State private var stories: StoriesViewModel
    @State private var notifications: NotificationsViewModel
    @State private var path: [Post] = []
    @State private var viewingStoryAt: StoryStart?
    @State private var showingFriends = false
    @State private var showingNotifications = false

    /// Identifiable wrapper so `fullScreenCover(item:)` can carry a start index.
    private struct StoryStart: Identifiable { let value: Int; var id: Int { value } }

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: FeedViewModel(service: container.feedService))
        _stories = State(initialValue: StoriesViewModel(service: container.storyService))
        _notifications = State(initialValue: NotificationsViewModel(service: container.notificationsService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("MetaBro")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { friendsButton }
                    ToolbarItem(placement: .topBarTrailing) { notificationsButton }
                    ToolbarItem(placement: .topBarTrailing) { sortMenu }
                }
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post, service: container.commentService,
                                    safetyService: container.safetyService,
                                    moderationService: container.moderationService)
                }
        }
        .task { await model.load() }
        .task { await stories.load() }
        .task { await notifications.load() }
        .fullScreenCover(item: $viewingStoryAt) { start in
            StoryViewerView(
                stories: stories.stories,
                index: start.value,
                onSeen: { id in Task { await stories.markSeen(id) } },
                onClose: { viewingStoryAt = nil }
            )
        }
        .sheet(isPresented: $showingFriends) {
            FriendsView(service: container.friendsService)
        }
        .sheet(isPresented: $showingNotifications) {
            NotificationsView(model: notifications)
        }
    }

    private var friendsButton: some View {
        Button { showingFriends = true } label: {
            Image(systemName: "person.2.fill")
        }
        .accessibilityLabel("Your Bros")
    }

    private var notificationsButton: some View {
        Button { showingNotifications = true } label: {
            Image(systemName: "bell.fill")
                .overlay(alignment: .topTrailing) {
                    if notifications.unreadCount > 0 {
                        Circle().fill(.red).frame(width: 8, height: 8).offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityLabel(notifications.unreadCount > 0
            ? "Notifications, \(notifications.unreadCount) unread"
            : "Notifications")
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: Tokens.Spacing.lg) {
                SloganView()
                ProgressView()
            }
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
                    if !stories.stories.isEmpty {
                        StoriesStrip(stories: stories.stories) { index in
                            viewingStoryAt = StoryStart(value: index)
                        }
                    }
                    ForEach(posts) { post in
                        PostCardView(
                            post: post,
                            onVote: { value in Task { await model.vote(on: post, value: value) } },
                            onReact: { reaction in Task { await model.react(on: post, reaction: reaction) } },
                            onAward: { award in Task { await model.giveAward(on: post, award: award) } },
                            onOpen: { path.append(post) },
                            safetyService: container.safetyService
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
