import SwiftUI

/// Discover Bro-hoods and join/leave them, with search across communities and
/// posts. Each row is a Liquid Glass card with a springy join toggle.
struct CommunitiesView: View {
    private let container: AppContainer
    @State private var model: CommunitiesViewModel
    @State private var search: SearchViewModel
    @State private var searchText = ""
    @State private var path: [Post] = []
    @State private var isShowingModQueue = false
    @State private var isShowingEvents = false
    @State private var isShowingGroups = false
    @State private var pendingMatureCommunity: Community?

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: CommunitiesViewModel(service: container.communityService))
        _search = State(initialValue: SearchViewModel(service: container.searchService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if searchText.isEmpty {
                    content
                } else {
                    SearchResultsView(state: search.state, onOpenPost: { path.append($0) },
                                       safetyService: container.safetyService)
                }
            }
            .navigationTitle("Bro-hoods")
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post, service: container.commentService,
                                safetyService: container.safetyService,
                                moderationService: container.moderationService)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingEvents = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Events")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingGroups = true } label: {
                        Image(systemName: "person.3.sequence")
                    }
                    .accessibilityLabel("Groups")
                }
                if isModerator {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isShowingModQueue = true } label: {
                            Image(systemName: "shield")
                        }
                        .accessibilityLabel("Mod queue")
                    }
                }
            }
            .sheet(isPresented: $isShowingModQueue) {
                NavigationStack {
                    ModQueueView(service: container.moderationService)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingModQueue = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingEvents) {
                EventsView(container: container)
            }
            .sheet(isPresented: $isShowingGroups) {
                GroupsView(container: container)
            }
            .confirmationDialog(
                "Mature content",
                isPresented: Binding(
                    get: { pendingMatureCommunity != nil },
                    set: { if !$0 { pendingMatureCommunity = nil } }
                ),
                presenting: pendingMatureCommunity
            ) { community in
                Button("I'm 18 or older — Join") {
                    Task { await model.toggleMembership(community) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { community in
                Text("\(community.name) contains mature content meant for adults.")
            }
        }
        .searchable(text: $searchText, prompt: "Search Bro-hoods and posts")
        .onChange(of: searchText) { _, text in search.query(text) }
        .task { await model.load() }
    }

    /// Gates the mod queue entry point — true when at least one loaded
    /// Bro-hood lists the current user as a moderator.
    private var isModerator: Bool {
        guard case .loaded(let communities) = model.state else { return false }
        return communities.contains { $0.isModerator }
    }

    /// Routes a join/leave tap — mature, not-yet-joined Bro-hoods get an age
    /// confirmation first; leaving or joining a non-mature Bro-hood is immediate.
    private func requestJoin(_ community: Community) {
        if community.isMature && !community.isJoined {
            pendingMatureCommunity = community
        } else {
            Task { await model.toggleMembership(community) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No Bro-hoods yet",
                                   systemImage: "person.3",
                                   description: Text("Check back soon."))
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let communities):
            ScrollView {
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach(communities) { community in
                        CommunityRow(community: community) {
                            requestJoin(community)
                        }
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: communities)
            }
            .refreshable { await model.load() }
        }
    }
}

private struct CommunityRow: View {
    let community: Community
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous)
                .fill(Tokens.Color.accent.opacity(0.25))
                .frame(width: 44, height: 44)
                .overlay(Text(String(community.name.prefix(1))).font(.headline.bold()))

            VStack(alignment: .leading, spacing: 2) {
                Text(community.name).font(Tokens.Typography.headline)
                Text("\(community.memberCount.abbreviated) bros · b/\(community.slug)")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            Spacer()
            joinButton
        }
        .padding(Tokens.Spacing.md)
        .liquidGlass()
        .accessibilityElement(children: .combine)
    }

    private var joinButton: some View {
        Button(action: onToggle) {
            Text(community.isJoined ? "Joined" : "Join")
                .font(Tokens.Typography.caption.weight(.bold))
                .foregroundStyle(community.isJoined ? Tokens.Color.textSecondary : .white)
                .padding(.horizontal, Tokens.Spacing.lg)
                .padding(.vertical, Tokens.Spacing.sm)
                .background {
                    Capsule().fill(community.isJoined
                                   ? AnyShapeStyle(.ultraThinMaterial)
                                   : AnyShapeStyle(Tokens.Color.accent))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(community.isJoined ? "Leave \(community.name)" : "Join \(community.name)")
    }
}
