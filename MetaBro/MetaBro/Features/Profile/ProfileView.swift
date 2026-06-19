import SwiftUI

/// The signed-in user's profile: identity header, Bro Cred (karma) breakdown,
/// joined Bro-hoods, and authored posts (tappable through to their threads).
struct ProfileView: View {
    private let container: AppContainer
    @State private var model: ProfileViewModel
    @State private var path: [Post] = []

    init(container: AppContainer) {
        self.container = container
        _model = State(initialValue: ProfileViewModel(service: container.profileService))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("You")
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
                        Text(c.name)
                            .font(Tokens.Typography.caption.weight(.semibold))
                            .padding(.horizontal, Tokens.Spacing.md)
                            .padding(.vertical, Tokens.Spacing.sm)
                            .liquidGlass(radius: Tokens.Radius.pill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    PostCardView(post: post, onVote: { _ in }, onOpen: { path.append(post) })
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
            Circle()
                .fill(Tokens.Color.accent.opacity(0.25))
                .frame(width: 84, height: 84)
                .overlay(Text(String(profile.user.displayName.prefix(1)))
                    .font(.largeTitle.bold()))

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
