import SwiftUI

/// A single feed post rendered on a Liquid Glass card. Visually distinguishes
/// the two halves of the hybrid: community posts carry a Bro-hood chip, social
/// posts carry the author's display name.
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

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            // Tappable content region — opens the post. Vote/share controls in
            // the footer keep their own actions and are not part of this target.
            VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                header
                if let title = post.title {
                    Text(title)
                        .font(Tokens.Typography.headline)
                        .foregroundStyle(Tokens.Color.textPrimary)
                }
                Text(post.body)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .lineLimit(6)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }

            if post.awardCount > 0 { awardChips }

            footer
        }
        .padding(Tokens.Spacing.lg)
        .liquidGlass()
    }

    /// Reddit-style award badges, highest count first.
    private var sortedAwardKinds: [AwardKind] {
        post.awards.filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    private var awardChips: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ForEach(sortedAwardKinds, id: \.self) { kind in
                let count = post.awards[kind] ?? 0
                HStack(spacing: 2) {
                    Text(kind.emoji).font(.caption)
                    Text("\(count)").font(.caption2).foregroundStyle(Tokens.Color.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.vertical, 4)
                .fixedSize()
                .liquidGlass(radius: Tokens.Radius.pill)
                .accessibilityLabel("\(count) \(kind.label) award\(count == 1 ? "" : "s")")
            }
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            // Community posts lead with the Bro-hood icon, social posts with the
            // author's avatar — both AI-generated and refreshed daily.
            Group {
                if let community = post.community {
                    CommunityAvatar(community: community, size: 36)
                } else {
                    UserAvatar(user: post.author, size: 36)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                switch post.origin {
                case .community:
                    Text(post.community?.name ?? "")
                        .font(Tokens.Typography.caption.weight(.semibold))
                    Text("\(post.author.handle) · \(post.createdAt.relative)")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textSecondary)
                case .social:
                    Text(post.author.displayName)
                        .font(Tokens.Typography.caption.weight(.semibold))
                    Text(post.createdAt.relative)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
            }
            Spacer()
            if post.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.accent)
                    .accessibilityLabel("Pinned by mods")
            }
            if post.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .accessibilityLabel("Locked")
            }
            if post.origin == .community {
                Text("Bro-hood")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .liquidGlass(radius: Tokens.Radius.pill)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.md) {
            switch post.origin {
            case .community:
                VoteControl(
                    score: post.score,
                    myVote: post.myVote.direction,
                    onVote: { onVote($0.value) }
                )
            case .social:
                ReactionControl(summary: post.reactions, onReact: onReact)
            }
            Button { onOpen?() } label: {
                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .font(Tokens.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Color.textSecondary)
            .accessibilityLabel("\(post.commentCount) comments. Open discussion.")
            .lineLimit(1)
            .fixedSize()
            Spacer(minLength: 0)
            HStack(spacing: Tokens.Spacing.sm) {
                awardMenu
                saveButton
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .accessibilityLabel("Share")
                if let safetyService {
                    SafetyMenu(user: post.author, kind: .post, targetID: post.id,
                               preview: post.title ?? post.body, community: post.community,
                               service: safetyService)
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: post.isSaved ? "bookmark.fill" : "bookmark")
                .foregroundStyle(post.isSaved ? Tokens.Color.accent : Tokens.Color.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(post.isSaved ? "Unsave post" : "Save post")
    }

    private var awardMenu: some View {
        Menu {
            ForEach(AwardKind.allCases, id: \.self) { kind in
                Button { onAward(kind) } label: {
                    Text("\(kind.emoji)  Give \(kind.label) · \(kind.cost)")
                }
            }
        } label: {
            Image(systemName: "rosette")
                .foregroundStyle(Tokens.Color.textSecondary)
        }
        .accessibilityLabel("Give award")
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
