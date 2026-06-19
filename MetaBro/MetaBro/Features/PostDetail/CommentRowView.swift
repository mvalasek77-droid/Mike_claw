import SwiftUI

/// One comment in the thread. Depth drives a left indent + a colored thread
/// spine (Reddit-style). Tapping the spine collapses/expands the subtree.
struct CommentRowView: View {
    let item: ThreadedComment
    let isCollapsed: Bool
    let onVote: (VoteValue) -> Void
    let onToggleCollapse: () -> Void
    let onReply: () -> Void

    private var comment: Comment { item.comment }
    private var indent: CGFloat { CGFloat(item.depth) * Tokens.Spacing.lg }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            if item.depth > 0 { spine }

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                header
                if !isCollapsed {
                    Text(comment.body)
                        .font(Tokens.Typography.body)
                        .foregroundStyle(Tokens.Color.textPrimary)
                    actions
                }
            }
            .padding(Tokens.Spacing.md)
            .liquidGlass(radius: Tokens.Radius.md)
        }
        .padding(.leading, indent)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isCollapsed ? "Collapsed thread. Double-tap to expand."
                                        : "Double-tap the spine to collapse.")
    }

    /// Colored vertical thread line; tappable to collapse the subtree.
    private var spine: some View {
        Button(action: onToggleCollapse) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Tokens.Color.accent.opacity(0.45))
                .frame(width: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand replies" : "Collapse replies")
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text(comment.author.handle)
                .font(Tokens.Typography.caption.weight(.semibold))
            if comment.isOP {
                Text("OP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Tokens.Color.accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Tokens.Color.accent.opacity(0.15),
                                in: Capsule())
            }
            Text("· \(comment.createdAt.relative)")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
            Spacer()
            if isCollapsed {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(Tokens.Color.textSecondary)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Tokens.Spacing.lg) {
            VoteControl(score: comment.score, myVote: comment.myVote.direction) { dir in
                onVote(dir.value)
            }
            Button(action: onReply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
                    .font(Tokens.Typography.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Color.textSecondary)
        }
    }
}
