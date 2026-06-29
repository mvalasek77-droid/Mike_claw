import SwiftUI

/// A single group's private feed: members strip, posts, and a composer.
struct GroupDetailView: View {
    @State private var model: GroupDetailViewModel

    init(group: FriendGroup, service: GroupService) {
        _model = State(initialValue: GroupDetailViewModel(group: group, service: service))
    }

    var body: some View {
        VStack(spacing: 0) {
            membersStrip
            content
            composer
        }
        .navigationTitle(model.group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private var membersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.sm) {
                ForEach(model.group.members) { member in
                    VStack(spacing: 4) {
                        UserAvatar(user: member, size: 44)
                        Text(member.displayName)
                            .font(.caption2)
                            .foregroundStyle(Tokens.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(Tokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("No posts yet", systemImage: "bubble.left.and.bubble.right",
                                   description: Text("Say something to get this group going."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                LazyVStack(spacing: Tokens.Spacing.md) {
                    ForEach(posts) { post in
                        GroupPostCard(post: post) {
                            Task { await model.toggleLike(post) }
                        }
                    }
                }
                .padding(Tokens.Spacing.lg)
                .animation(Tokens.Motion.gentle, value: posts)
            }
            .refreshable { await model.load() }
        }
    }

    private var composer: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            TextField("Say something to the group…", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.vertical, Tokens.Spacing.sm)
                .liquidGlass(radius: Tokens.Radius.pill)

            Button {
                Task { await model.post() }
            } label: {
                if model.isPosting {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isPosting)
        }
        .padding(Tokens.Spacing.lg)
    }
}

private struct GroupPostCard: View {
    let post: GroupPost
    let onLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack(spacing: Tokens.Spacing.sm) {
                UserAvatar(user: post.author, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author.displayName)
                        .font(Tokens.Typography.caption.weight(.semibold))
                    Text(post.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
                Spacer()
            }
            Text(post.body)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.textPrimary)

            Button(action: onLike) {
                HStack(spacing: 4) {
                    Image(systemName: post.likedByMe ? "hand.thumbsup.fill" : "hand.thumbsup")
                    if post.likeCount > 0 {
                        Text("\(post.likeCount)")
                    }
                }
                .font(Tokens.Typography.caption.weight(.semibold))
                .foregroundStyle(post.likedByMe ? Tokens.Color.accent : Tokens.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.likedByMe ? "Unlike" : "Like")
        }
        .padding(Tokens.Spacing.lg)
        .liquidGlass()
    }
}
