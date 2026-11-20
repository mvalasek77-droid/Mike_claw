import SwiftUI

/// A single feed post, laid out like a Facebook post: header, text, full-width
/// photo, a counts row, and an equal-width action bar. Community posts keep
/// Reddit-style voting in the first action slot; social posts get reactions.
struct PostCardView: View {
    let post: Post
    let onVote: (VoteValue) -> Void
    /// Reaction handler for social posts. Defaults to a no-op so read-only
    /// surfaces (profile, search) can render cards without wiring reactions.
    var onReact: (ReactionKind?) -> Void = { _ in }
    /// Award handler. Defaults to a no-op on read-only surfaces.
    var onAward: (AwardKind) -> Void = { _ in }
    /// Bookmark toggle. Defaults to a no-op on read-only surfaces.
    var onSave: () -> Void = {}
    /// Optional tap-to-open handler. When nil (e.g. on the detail screen itself)
    /// the content region is inert.
    var onOpen: (() -> Void)? = nil
    /// Safety service for the report/block/mute menu. Nil on previews/tests
    /// that don't wire one up, in which case the menu is omitted.
    var safetyService: SafetyService? = nil
    /// Edge-to-edge in the main feed; rounded when inset inside other screens.
    var fullBleed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.top, Tokens.Spacing.md)

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                if let title = post.title {
                    Text(title)
                        .font(Tokens.Typography.headline)
                        .foregroundStyle(Tokens.Color.textPrimary)
                }
                if !post.body.isEmpty {
                    Text(post.body)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(Tokens.Color.textPrimary)
                        .lineLimit(post.imageURL == nil ? 8 : 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.top, Tokens.Spacing.sm)
            .padding(.bottom, Tokens.Spacing.md)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }

            if let url = post.imageURL {
                PostImageView(url: url)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpen?() }
            }

            countsRow
                .padding(.horizontal, Tokens.Spacing.md)
                .padding(.vertical, Tokens.Spacing.sm)

            Divider().padding(.horizontal, Tokens.Spacing.md)

            actionBar
                .padding(.horizontal, Tokens.Spacing.xs)
                .padding(.vertical, Tokens.Spacing.xs)
        }
        .background(Tokens.Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : Tokens.Radius.md,
                                    style: .continuous))
        .overlay {
            if !fullBleed {
                RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                    .stroke(Tokens.Color.separator, lineWidth: 1)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Tokens.Spacing.sm) {
            avatar

            VStack(alignment: .leading, spacing: 1) {
                Text(primaryName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(secondaryLine)
                        .lineLimit(1)
                    Image(systemName: post.origin == .community ? "person.3.fill" : "globe.americas.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
            }

            Spacer(minLength: Tokens.Spacing.sm)

            if post.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.accent)
                    .accessibilityLabel("Pinned by mods")
            }
            if post.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .accessibilityLabel("Locked")
            }
            if post.isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Tokens.Color.accent)
                    .accessibilityLabel("Saved")
            }
            if let safetyService {
                SafetyMenu(user: post.author, kind: .post, targetID: post.id,
                           preview: post.title ?? post.body, community: post.community,
                           service: safetyService) {
                    Button(action: onSave) {
                        Label(post.isSaved ? "Unsave post" : "Save post",
                              systemImage: post.isSaved ? "bookmark.slash" : "bookmark")
                    }
                    Menu {
                        ForEach(AwardKind.allCases, id: \.self) { kind in
                            Button { onAward(kind) } label: {
                                Text("\(kind.emoji)  \(kind.label) · \(kind.cost) coins")
                            }
                        }
                    } label: {
                        Label("Give award", systemImage: "rosette")
                    }
                }
            }
        }
    }

    /// Bro-hood posts show the community avatar with the author badge on top,
    /// like a Facebook group post; social posts show the author alone.
    @ViewBuilder
    private var avatar: some View {
        if let community = post.community {
            CommunityAvatar(community: community, size: 40)
                .overlay(alignment: .bottomTrailing) {
                    UserAvatar(user: post.author, size: 20)
                        .overlay(Circle().stroke(Tokens.Color.cardBackground, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
        } else {
            UserAvatar(user: post.author, size: 40)
        }
    }

    private var primaryName: String {
        post.community?.name ?? post.author.displayName
    }

    private var secondaryLine: String {
        switch post.origin {
        case .community: "\(post.author.handle) · \(post.createdAt.relative)"
        case .social: post.createdAt.relative
        }
    }

    // MARK: Counts row

    private var countsRow: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            switch post.origin {
            case .social:
                if post.reactions.total > 0 {
                    ReactionSummaryView(summary: post.reactions)
                }
            case .community:
                if post.awardCount > 0 { awardSummary }
            }
            Spacer(minLength: 0)
            Button { onOpen?() } label: {
                Text(post.commentCount == 1 ? "1 comment" : "\(post.commentCount) comments")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .frame(minHeight: 20)
    }

    private var awardSummary: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            HStack(spacing: -4) {
                ForEach(sortedAwardKinds, id: \.self) { kind in
                    Text(kind.emoji).font(.caption)
                }
            }
            Text("\(post.awardCount) award\(post.awardCount == 1 ? "" : "s")")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(post.awardCount) awards")
    }

    private var sortedAwardKinds: [AwardKind] {
        post.awards.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    // MARK: Action bar

    /// Three equal-width slots, so no control can squeeze another.
    private var actionBar: some View {
        HStack(spacing: 0) {
            Group {
                switch post.origin {
                case .community:
                    VoteControl(score: post.score, myVote: post.myVote.direction,
                                showsBackground: false,
                                onVote: { onVote($0.value) })
                case .social:
                    ReactionButton(summary: post.reactions, onReact: onReact)
                }
            }
            .frame(maxWidth: .infinity)

            actionButton("Comment", systemImage: "bubble.left") { onOpen?() }
                .accessibilityLabel("\(post.commentCount) comments. Open discussion.")

            ShareLink(item: shareText) {
                actionLabel("Share", systemImage: "arrowshape.turn.up.right")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    private func actionButton(_ title: String, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, systemImage: systemImage) }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Tokens.Typography.caption.weight(.semibold))
            .foregroundStyle(Tokens.Color.textSecondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
    }

    private var shareText: String {
        [post.title, post.body].compactMap { $0 }.joined(separator: "\n\n")
            + "\n\n— shared from MetaBro"
    }
}

/// Full-width post photo with a stable 4:3 frame so the feed never jumps
/// while images load. Handles both remote and on-device (file://) URLs.
struct PostImageView: View {
    let url: URL

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(Tokens.Color.textSecondary)
                    default:
                        ProgressView()
                    }
                }
            }
            .background(Tokens.Color.inputBackground)
            .clipped()
            .accessibilityLabel("Photo")
    }
}

// MARK: - Vote bridging (wire value <-> UI direction)

extension VoteValue {
    var direction: VoteDirection {
        switch self {
        case .up: .up
        case .down: .down
        case .none: .none
        }
    }
}

extension VoteDirection {
    var value: VoteValue {
        switch self {
        case .up: .up
        case .down: .down
        case .none: .none
        }
    }
}

extension Date {
    /// Compact relative time, e.g. "1h", "2d".
    var relative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
