import SwiftUI

/// One comment in the thread, styled like Facebook: avatar, grey speech
/// bubble with name + text, and a "time · Reply · votes · ···" line below.
/// Replies indent under their parent; tapping the thread line collapses them.
struct CommentRowView: View {
    let item: ThreadedComment
    let isCollapsed: Bool
    let onVote: (VoteValue) -> Void
    let onToggleCollapse: () -> Void
    let onReply: () -> Void
    let safetyService: SafetyService

    private var comment: Comment { item.comment }
    /// Cap the indent so deep threads stay readable on a phone.
    private var indent: CGFloat { CGFloat(min(item.depth, 3)) * 36 }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            if item.depth > 0 { threadLine }

            UserAvatar(user: comment.author, size: item.depth == 0 ? 34 : 26)

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                bubble
                if !isCollapsed { actions }
            }
            Spacer(minLength: 0)
        }
        // Lets the thread line stretch to the row's full height.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, max(0, indent - 14))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Tokens.Spacing.xs) {
                Text(comment.author.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Tokens.Color.textPrimary)
                if comment.isOP {
                    Text("Author")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Tokens.Color.accent)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Tokens.Color.accent.opacity(0.15), in: Capsule())
                }
                if isCollapsed {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(Tokens.Color.textSecondary)
                }
            }
            if !isCollapsed {
                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.sm)
        .background(Tokens.Color.inputBackground,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if isCollapsed { onToggleCollapse() } }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isCollapsed ? "Collapsed. Double-tap to expand." : "")
    }

    /// Thin connector to the parent comment; tap to collapse/expand the reply.
    private var threadLine: some View {
        Button(action: onToggleCollapse) {
            Rectangle()
                .fill(Tokens.Color.separator)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .frame(width: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCollapsed ? "Expand reply" : "Collapse reply")
    }

    private var actions: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Text(comment.createdAt.relative)
                .foregroundStyle(Tokens.Color.textSecondary)
            Button("Reply", action: onReply)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(Tokens.Color.textSecondary)
            VoteControl(score: comment.score, myVote: comment.myVote.direction,
                        showsBackground: false) { dir in
                onVote(dir.value)
            }
            SafetyMenu(user: comment.author, kind: .comment, targetID: comment.id,
                       preview: comment.body, service: safetyService)
        }
        .font(.caption)
        .padding(.leading, Tokens.Spacing.md)
    }
}
