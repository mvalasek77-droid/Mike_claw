import SwiftUI

/// A single feed post rendered on a Liquid Glass card. Visually distinguishes
/// the two halves of the hybrid: community posts carry a Bro-hood chip, social
/// posts carry the author's display name.
struct PostCardView: View {
    let post: Post
    let onVote: (VoteValue) -> Void

    var body: some View {
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

            footer
        }
        .padding(Tokens.Spacing.lg)
        .liquidGlass()
        .accessibilityElement(children: .combine)
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
            VoteControl(
                score: post.score,
                myVote: post.myVote.direction,
                onVote: { onVote($0.value) }
            )
            Label("\(post.commentCount)", systemImage: "bubble.right")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(Tokens.Color.textSecondary)
                .accessibilityLabel("Share")
        }
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
