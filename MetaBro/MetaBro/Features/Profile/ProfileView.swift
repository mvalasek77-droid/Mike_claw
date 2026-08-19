import SwiftUI

/// The signed-in user's profile: identity header, Bro Cred (karma) breakdown,
/// joined Bro-hoods, and authored posts (tappable through to their threads).
struct ProfileView: View {
    private let container: AppContainer
    let onSignOut: () -> Void
    @State private var model: ProfileViewModel
    @State private var path: [Post] = []
    @State private var showingBugReport = false
    @State private var showingSaved = false
    @State private var showingHistory = false
    @State private var showDeleteConfirm = false

    init(container: AppContainer, onSignOut: @escaping () -> Void) {
        self.container = container
        self.onSignOut = onSignOut
        _model = State(initialValue: ProfileViewModel(service: container.profileService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("You")
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post, service: container.commentService,
                                    safetyService: container.safetyService,
                                    moderationService: container.moderationService)
                }
        }
        .task { await model.load() }
        .sheet(isPresented: $showingBugReport) {
            BugReportView(service: container.bugReportService)
        }
        .sheet(isPresented: $showingSaved) {
            SavedView(container: container)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(historyService: container.historyService)
        }
        .confirmationDialog("Delete Account",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task {
                    await container.authService.signOut()
                    Session.shared.signOut()
                    UserDefaults.standard.removeObject(forKey: "metabro.tutorial.seen")
                    onSignOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account data, handle, posts, and Bro Cred from this device. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded(let profile):
            ScrollView {
                VStack(spacing: Tokens.Spacing.lg) {
                    ProfileHeader(profile: profile)
                    if !profile.joinedCommunities.isEmpty {
                        joinedStrip(profile.joinedCommunities)
                    }
                    postsSection(profile.posts)
                    savedPostsRow
                    historyRow
                    reportProblemRow
                    signOutRow
                    deleteAccountRow
                    SloganView(showsMark: false)
                        .padding(.top, Tokens.Spacing.xl)
                        .frame(maxWidth: .infinity)
                }
                .padding(Tokens.Spacing.lg)
            }
            .refreshable { await model.load() }
        }
    }

    private func joinedStrip(_ communities: [Community]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text("Your Bro-hoods").font(Tokens.Typography.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Spacing.sm) {
                    ForEach(communities) { c in
                        HStack(spacing: Tokens.Spacing.sm) {
                            CommunityAvatar(community: c, size: 28)
                            Text(c.name)
                                .font(Tokens.Typography.caption.weight(.semibold))
                        }
                        .padding(.horizontal, Tokens.Spacing.md)
                        .padding(.vertical, Tokens.Spacing.sm)
                        .liquidGlass(radius: Tokens.Radius.pill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyRow: some View {
        Button { showingHistory = true } label: {
            HStack {
                Label("Recently viewed", systemImage: "clock.arrow.circlepath")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            .padding(Tokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .liquidGlass()
        .frame(maxWidth: .infinity)
    }

    private var savedPostsRow: some View {
        Button { showingSaved = true } label: {
            HStack {
                Label("Saved posts", systemImage: "bookmark")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            .padding(Tokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .liquidGlass()
        .frame(maxWidth: .infinity)
    }

    private var reportProblemRow: some View {
        Button { showingBugReport = true } label: {
            HStack {
                Label("Report a problem", systemImage: "exclamationmark.bubble")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
            .padding(Tokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .liquidGlass()
        .frame(maxWidth: .infinity)
    }

    private var signOutRow: some View {
        Button(role: .destructive) {
            Task {
                await container.authService.signOut()
                Session.shared.signOut()
                onSignOut()
            }
        } label: {
            HStack {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                Spacer()
            }
            .padding(Tokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .liquidGlass()
        .frame(maxWidth: .infinity)
    }

    private var deleteAccountRow: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                Spacer()
            }
            .padding(Tokens.Spacing.md)
        }
        .buttonStyle(.plain)
        .liquidGlass()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func postsSection(_ posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text("Your posts").font(Tokens.Typography.headline)
            if posts.isEmpty {
                ContentUnavailableView("No posts yet",
                                       systemImage: "square.and.pencil",
                                       description: Text("Head to the + tab to share something."))
            } else {
                ForEach(posts) { post in
                    PostCardView(post: post, onVote: { _ in }, onOpen: { path.append(post) },
                                 safetyService: container.safetyService)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileHeader: View {
    let profile: Profile

    var body: some View {
        VStack(spacing: Tokens.Spacing.md) {
            UserAvatar(user: profile.user, size: 84)

            VStack(spacing: 2) {
                Text(profile.user.displayName).font(Tokens.Typography.title)
                Text(profile.user.handle)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
            }

            HStack(spacing: Tokens.Spacing.xl) {
                stat("\(profile.broCred.abbreviated)", "Bro Cred")
                stat("\(profile.postKarma.abbreviated)", "Post")
                stat("\(profile.commentKarma.abbreviated)", "Comment")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Spacing.xl)
        .liquidGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.user.displayName), \(profile.broCred) Bro Cred")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Tokens.Typography.headline).monospacedDigit()
            Text(label).font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
        }
    }
}

private struct HistoryView: View {
    let historyService: HistoryService
    @State private var viewedCount = 0
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewedCount == 0 {
                    ContentUnavailableView("No history yet",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Posts you view will appear here."))
                } else {
                    VStack(spacing: Tokens.Spacing.lg) {
                        HStack(spacing: Tokens.Spacing.md) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                                .foregroundStyle(Tokens.Color.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(viewedCount) posts viewed")
                                    .font(Tokens.Typography.headline)
                                Text("Posts you open are tracked here.")
                                    .font(Tokens.Typography.caption)
                                    .foregroundStyle(Tokens.Color.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(Tokens.Spacing.lg)
                        .liquidGlass()
                        Spacer()
                    }
                    .padding(Tokens.Spacing.lg)
                }
            }
            .navigationTitle("Recently Viewed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                viewedCount = try await historyService.viewedPostIDs().count
            } catch {
                BroLog.error(error, category: "history")
            }
            isLoading = false
        }
    }
}
