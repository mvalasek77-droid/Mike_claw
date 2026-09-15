import SwiftUI

struct FeedView: View {
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var notifications: NotificationsService
    @ObservedObject var moderation = ModerationService.shared
    @State private var commentSheet: SocialPost?
    @State private var showInbox = false
    @State private var copyBlocked = false

    var visibleFeed: [SocialPost] { moderation.filter(feed: social.feed) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.stageBlack.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: Theme.Space.lg) {
                        MarqueeBoxOfficeHeader()
                            .padding(.horizontal)

                        BoxOfficeForecastBoard()
                            .padding(.horizontal)

                        MarqueeSectionLabel(title: "Featured critics",
                                             kicker: "This week's top traders")
                            .padding(.horizontal)
                        FeaturedCritics()
                            .padding(.horizontal)

                        MarqueeSectionLabel(title: "Audience calls",
                                             kicker: "Live from the lobby")
                            .padding(.horizontal)
                        ForEach(visibleFeed) { post in
                            PostCard(post: post,
                                     onComment: { commentSheet = post },
                                     onCopyBlocked: { copyBlocked = true })
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, Theme.Space.sm)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle("Marquee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.stageBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showInbox = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: notifications.unreadCount > 0 ? "bell.fill" : "bell")
                                .foregroundStyle(notifications.unreadCount > 0 ? Theme.marqueeGold : Theme.cream)
                            if notifications.unreadCount > 0 {
                                Text("\(min(notifications.unreadCount, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 3).fill(Theme.bear))
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

// MARK: - Box-office marquee

/// The Marquee should read like the board over a theater entrance, not
/// another generic social timeline. The double rule replaces the old
/// colored bubble decoration with the app's cinema palette.
struct MarqueeBoxOfficeHeader: View {
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                rule
                Text("BOXCALL PRESENTS")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Theme.bulbGlow)
                    .fixedSize()
                rule
            }
            Text("THE BOX OFFICE")
                .font(.system(size: 31, weight: .black, design: .serif))
                .tracking(1.2)
                .foregroundStyle(Theme.cream)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text("OPENING WEEKEND FORECAST MARKET")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Theme.marqueeGold)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.velvetRed, Theme.stageBlack],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .stroke(Theme.marqueeGold, lineWidth: 2)
            RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.45), lineWidth: 1)
                .padding(5)
        }
        .shadow(color: Theme.velvetRed.opacity(0.45), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        Rectangle()
            .fill(Theme.marqueeGold.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
    }
}

/// Ranked, tappable forecast board. It gives the social tab an actual
/// box-office center of gravity and makes the films one tap away.
struct BoxOfficeForecastBoard: View {
    @EnvironmentObject var market: MarketService

    private var rankedMovies: [Movie] {
        Array(market.movies
            .sorted { market.impliedConsensus(for: $0.id) > market.impliedConsensus(for: $1.id) }
            .prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OPENING WEEKEND BOARD")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(Theme.cream)
                    Text("Live audience-implied grosses")
                        .font(.caption2)
                        .foregroundStyle(Theme.cream.opacity(0.55))
                }
                Spacer()
                Text("FORECAST")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.marqueeGold)
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.md)

            Rectangle()
                .fill(Theme.marqueeGold.opacity(0.45))
                .frame(height: 1)

            ForEach(Array(rankedMovies.enumerated()), id: \.element.id) { index, movie in
                NavigationLink(value: movie) {
                    forecastRow(rank: index + 1, movie: movie)
                }
                .buttonStyle(.plain)

                if movie.id != rankedMovies.last?.id {
                    Rectangle()
                        .fill(Theme.cream.opacity(0.09))
                        .frame(height: 1)
                        .padding(.leading, 45)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color(red: 0.075, green: 0.06, blue: 0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.5), lineWidth: 1)
        }
    }

    private func forecastRow(rank: Int, movie: Movie) -> some View {
        let implied = market.impliedConsensus(for: movie.id)
        let delta = market.consensusDeltaPct(for: movie.id)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(Theme.marqueeGold)
                .frame(width: 23, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(movie.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.cream)
                    .lineLimit(1)
                Text("\(movie.releaseDate.formatted(.dateTime.month(.abbreviated).day()))  ·  \(movie.studio)")
                    .font(.caption2)
                    .foregroundStyle(Theme.cream.opacity(0.52))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text("$\(implied, specifier: "%.0f")M")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.cream)
                Text(delta, format: .percent.precision(.fractionLength(1)).sign(strategy: .always()))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(delta >= 0 ? Theme.marqueeGold : Theme.bear)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.marqueeGold.opacity(0.7))
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens movie market")
    }
}

struct MarqueeSectionLabel: View {
    let title: String
    let kicker: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 13, weight: .black, design: .serif))
                .tracking(1.1)
                .foregroundStyle(Theme.cream)
            Rectangle()
                .fill(Theme.marqueeGold.opacity(0.55))
                .frame(height: 1)
            Text(kicker.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(Theme.marqueeGold)
                .lineLimit(1)
        }
    }
}

/// Compact poster stand-in for Marquee cards. The ticket shape keeps
/// every identity in the cinema palette without colored avatar circles.
struct MarqueeMovieMark: View {
    let title: String
    let width: CGFloat
    let height: CGFloat

    private var monogram: String {
        title
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    var body: some View {
        let radius = min(6, width * 0.16)
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.velvetRed.opacity(0.9), Theme.stageBlack],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 4) {
                Rectangle()
                    .fill(Theme.marqueeGold.opacity(0.5))
                    .frame(height: 1)
                Text(monogram)
                    .font(.system(size: max(9, width * 0.28), weight: .black, design: .serif))
                    .foregroundStyle(Theme.cream)
                    .minimumScaleFactor(0.7)
                Rectangle()
                    .fill(Theme.marqueeGold.opacity(0.5))
                    .frame(height: 1)
            }
            .padding(.horizontal, max(4, width * 0.14))
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.65), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct PostCard: View {
    let post: SocialPost
    let onComment: () -> Void
    let onCopyBlocked: () -> Void
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var coordinator: TradeCoordinator
    @ObservedObject var moderation = ModerationService.shared
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm + 2) {
            headerRow
            callLine
            if let take = post.hotTake {
                Text(take)
                    .font(.callout)
                    .foregroundStyle(Theme.cream.opacity(0.9))
            }
            if let outcome = post.outcome {
                outcomeBanner(outcome)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            actionBar
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.velvetRed.opacity(0.3),
                                            Color(red: 0.07, green: 0.055, blue: 0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.marqueeGold.opacity(0.28), lineWidth: 1)
        }
        .animation(Theme.Motion.smooth, value: post.outcome)
        .animation(Theme.Motion.snap, value: post.isLikedByMe)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            avatarTicket
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("@\(post.authorHandle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.cream)
                    if post.authorTier >= .analyst {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Theme.marqueeGold)
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

    private var avatarTicket: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Theme.cream.opacity(0.07))
            .frame(width: 38, height: 38)
            .overlay(
                Text(String(post.authorHandle.prefix(1)).uppercased())
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Theme.marqueeGold.opacity(0.65), lineWidth: 1)
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
        .tint(following ? .gray : Theme.marqueeGold)
    }

    @ViewBuilder
    private var callLine: some View {
        if let movie = market.movie(id: post.movieId) {
            NavigationLink(value: movie) {
                callLineLabel(movie: movie)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens \(movie.title)")
        } else {
            callLineLabel(movie: nil)
        }
    }

    private func callLineLabel(movie: Movie?) -> some View {
        HStack(spacing: 10) {
            MarqueeMovieMark(title: movie?.title ?? post.movieTitle, width: 42, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(post.movieTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.cream)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.marqueeGold)
                }
                HStack(spacing: 6) {
                    tag(post.side.display,
                        color: post.side == .call ? Theme.marqueeGold : Theme.bear)
                    Text("$\(Int(post.strikeMillions))M strike").font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text("\(post.quantity) contracts @ \(post.entryPremium, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func outcomeBanner(_ o: SocialPost.PostOutcome) -> some View {
        let win = o.netProfit > 0
        return HStack {
            Image(systemName: win ? "checkmark" : "xmark")
                .foregroundStyle(win ? Theme.marqueeGold : Theme.bear)
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
        .background(RoundedRectangle(cornerRadius: 10)
            .fill((win ? Theme.marqueeGold : Theme.bear).opacity(0.12)))
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            Button {
                social.toggleLike(postId: post.id)
            } label: {
                Label("\(post.likes)", systemImage: post.isLikedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(post.isLikedByMe ? Theme.marqueeGold : .secondary)
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
                    .foregroundStyle(post.outcome == nil ? Theme.marqueeGold : .secondary)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
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
