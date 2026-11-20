import SwiftUI

extension ReactionKind {
    /// UI tint for the reaction (kept out of the model, which stays UI-free).
    var tint: Color {
        switch self {
        case .respect: Tokens.Color.respect
        case .strong: Tokens.Color.upvote
        case .lol: .yellow
        case .like: Tokens.Color.accent
        case .sad: Tokens.Color.downvote
        case .angry: .red
        }
    }
}

/// Facebook-style "Like" button for the post action bar. Tap toggles the
/// default Respect reaction; long-press opens the full reaction picker.
struct ReactionButton: View {
    let summary: ReactionSummary
    /// Passes the tapped reaction, or nil to clear the current one.
    let onReact: (ReactionKind?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        Button {
            onReact(summary.mine == nil ? .respect : nil)
            HapticsEngine.shared.play(.vote)
            if !reduceMotion {
                withAnimation(Tokens.Motion.pop) { popped = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(Tokens.Motion.pop) { popped = false }
                }
            }
        } label: {
            HStack(spacing: Tokens.Spacing.xs) {
                if let mine = summary.mine {
                    Text(mine.emoji)
                        .scaleEffect(popped ? 1.25 : 1.0)
                } else {
                    Image(systemName: "hand.thumbsup")
                        .scaleEffect(popped ? 1.25 : 1.0)
                }
                Text(summary.mine?.label ?? "Like")
                    .lineLimit(1)
            }
            .font(Tokens.Typography.caption.weight(.semibold))
            .foregroundStyle(summary.mine?.tint ?? Tokens.Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(ReactionKind.allCases, id: \.self) { kind in
                Button { onReact(kind) } label: {
                    Text("\(kind.emoji)  \(kind.label)")
                }
            }
        }
        .accessibilityLabel(summary.mine == nil ? "Like" : "Your reaction: \(summary.mine!.label)")
        .accessibilityHint("Double-tap to react, long-press to choose a reaction")
    }
}

/// Overlapping emoji stack + total, shown in the counts row above the action bar.
struct ReactionSummaryView: View {
    let summary: ReactionSummary

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            HStack(spacing: -6) {
                ForEach(summary.top.prefix(3), id: \.self) { kind in
                    Text(kind.emoji)
                        .font(.caption)
                        .padding(2)
                        .background(Circle().fill(Tokens.Color.cardBackground))
                }
            }
            Text("\(summary.total)")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.total) reactions")
    }
}
