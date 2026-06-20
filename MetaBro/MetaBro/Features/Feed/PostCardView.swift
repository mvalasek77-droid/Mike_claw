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
    /// Optional tap-to-open handler. When nil (e.g. on the detail screen itself)
    /// the content region is inert.
    var onOpen: (() -> Void)? = nil

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
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.vertical, 4)
                .liquidGlass(radius: Tokens.Radius.pill)
                .accessibilityLabel("\(count) \(kind.label) award\(count == 1 ? "" : "s")")
            }
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Circle()
                .fill(Tokens.Color.accent.opacity(0.25))
                .frame(width: 36, height: 36)
                .overlay(Text(initials).font(.caption.bold()))

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
        HStack(spacing: Tokens.Spacing.lg) {
            // The hybrid: Bro-hood posts use Reddit voting, social posts use
            // Facebook-style reactions.
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
            Spacer()
            awardMenu
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Tokens.Color.textSecondary)
                .accessibilityLabel("Share")
        }
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

    private var initials: String {
        let source = post.origin == .community ? post.author.handle : post.author.displayName
        return String(source.replacingOccurrences(of: "@", with: "").prefix(1)).uppercased()
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
