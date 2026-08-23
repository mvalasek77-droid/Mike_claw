import SwiftUI

struct FeedView: View {
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var notifications: NotificationsService
    @ObservedObject var moderation = ModerationService.shared
    @State private var commentSheet: SocialPost?
    @State private var showInbox = false
    @State private var copyBlocked = false

    var visibleFeed: [SocialPost] { moderation.filter(feed: social.feed) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    FeaturedCritics()
                        .padding(.horizontal)
                        .padding(.top, 4)
                    Divider().padding(.horizontal)
                    ForEach(visibleFeed) { post in
                        PostCard(post: post,
                                 onComment: { commentSheet = post },
                                 onCopyBlocked: { copyBlocked = true })
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Hot Takes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showInbox = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifications.unreadCount > 0 ? "bell.badge.fill" : "bell")
                                .foregroundStyle(notifications.unreadCount > 0 ? .orange : .primary)
                            if notifications.unreadCount > 0 {
                                Text("\(min(notifications.unreadCount, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Circle().fill(.red))
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                }
            }
            .sheet(item: $commentSheet) { post in
                CommentSheet(post: post)
            }
            .sheet(isPresented: $showInbox) {
                NotificationInboxView()
            }
            .alert("Can't copy this call", isPresented: $copyBlocked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The movie has already opened or that strike is no longer on the chain.")
            }
        }
    }
}

struct PostCard: View {
    let post: SocialPost
    let onComment: () -> Void
    let onCopyBlocked: () -> Void
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var coordinator: TradeCoordinator
    @ObservedObject var moderation = ModerationService.shared
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            headerRow
            callLine
            if let take = post.hotTake {
                Text(take).font(.callout)
            }
            if let outcome = post.outcome {
                outcomeBanner(outcome)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            actionBar
        }
        .padding(Theme.Space.lg)
        .glassSurface(radius: Theme.Radius.md,
                      tint: post.side == .call ? Theme.bull : Theme.bear)
        .animation(Theme.Motion.smooth, value: post.outcome)
        .animation(Theme.Motion.snap, value: post.isLikedByMe)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            avatarCircle
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(post.authorHandle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(post.authorTier >= .insider ? Color.yellow : .primary)
                    if post.authorTier >= .analyst {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(post.authorTier.color)
                            .font(.caption)
                    }
                }
                Text("\(post.authorTier.name) · \(relativeTime(post.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !post.authorIsCurrentUser {
                followButton
                Menu {
                    Button {
                        showReport = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        moderation.block(handle: post.authorHandle)
                    } label: {
                        Label("Block @\(post.authorHandle)", systemImage: "hand.raised")
                    }
                    Button {
                        moderation.hide(postId: post.id)
                    } label: {
                        Label("Not interested", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(kind: .post, targetId: post.id.uuidString,
                        authorHandle: post.authorHandle)
        }
    }

    private var avatarCircle: some View {
        Circle()
            .fill(post.authorTier.color.opacity(0.25))
            .frame(width: 38, height: 38)
            .overlay(
                Text(String(post.authorHandle.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundStyle(post.authorTier.color)
            )
    }

    private var followButton: some View {
        let following = social.isFollowing(post.authorHandle)
        return Button(following ? "Following" : "Follow") {
            following ? social.unfollow(handle: post.authorHandle)
                      : social.follow(handle: post.authorHandle)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(following ? .gray : .orange)
    }

    private var callLine: some View {
        HStack(spacing: 10) {
            Text(post.moviePosterEmoji).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.movieTitle).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    tag(post.side.display, color: post.side == .call ? .green : .red)
                    Text("$\(Int(post.strikeMillions))M strike").font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text("\(post.quantity) contracts @ \(post.entryPremium, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func outcomeBanner(_ o: SocialPost.PostOutcome) -> some View {
        let win = o.netProfit > 0
        return HStack {
            Image(systemName: win ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(win ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(win ? "Called it." : "Missed.")
                    .font(.caption.weight(.bold))
                Text("Opened at $\(o.actualMillions, specifier: "%.1f")M · net \(o.netProfit, specifier: "%+.0f") RC")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill((win ? Color.green : Color.red).opacity(0.12)))
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            Button {
                social.toggleLike(postId: post.id)
            } label: {
                Label("\(post.likes)", systemImage: post.isLikedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(post.isLikedByMe ? .pink : .secondary)
            }
            Button(action: onComment) {
                Label("\(post.comments.count)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if !coordinator.requestCopy(fromPost: post) { onCopyBlocked() }
            } label: {
                Label("Copy", systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(post.outcome == nil ? .orange : .secondary)
            }
            .disabled(post.outcome != nil)
            Button {
                sharePost()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    @MainActor
    private func sharePost() {
        let outcomeText: String? = post.outcome.map {
            $0.netProfit >= 0
                ? "Called it. +\(Int($0.netProfit)) RC"
                : "Missed by \(Int(-$0.netProfit)) RC"
        }
        let card = ShareCard(
            title: post.movieTitle,
            side: post.side,
            strikeMillions: post.strikeMillions,
            quantity: post.quantity,
            entryPremium: post.entryPremium,
            handle: post.authorHandle,
            tier: post.authorTier,
            outcomeText: outcomeText,
            poster: post.moviePosterEmoji
        )
        let message = "\(post.side.display) $\(Int(post.strikeMillions))M on \(post.movieTitle) — via BoxCall"
        Sharer.share(card, message: message)
    }
}

struct CommentSheet: View {
    let post: SocialPost
    @EnvironmentObject var social: SocialService
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var live: SocialPost {
        social.feed.first(where: { $0.id == post.id }) ?? post
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(live.comments) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("@\(c.authorHandle)").font(.caption.weight(.semibold))
                                    Text(c.authorTier.name).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(c.body).font(.callout)
                            }
                        }
                        if live.comments.isEmpty {
                            Text("Be the first to weigh in.").foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    TextField("Add a hot take…", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        social.addComment(postId: post.id, body: t)
                        draft = ""
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Replies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
