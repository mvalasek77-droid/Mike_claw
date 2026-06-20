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

/// Facebook-style reaction control for social posts. Quick-tap toggles the
/// default "Respect"; long-press opens the full picker. Shows a summary of the
/// top reactions and total count.
struct ReactionControl: View {
    let summary: ReactionSummary
    /// Passes the tapped reaction, or nil to clear the current one.
    let onReact: (ReactionKind?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            primaryButton
            if summary.total > 0 { summaryView }
        }
    }

    private var primaryButton: some View {
        Button {
            // Tap clears your current reaction, or applies the default Respect.
            onReact(summary.mine == nil ? .respect : nil)
            if !reduceMotion { pulse.toggle() }
        } label: {
            HStack(spacing: Tokens.Spacing.xs) {
                Text(summary.mine?.emoji ?? ReactionKind.respect.emoji)
                    .scaleEffect(pulse ? 1.25 : 1.0)
                    .animation(Tokens.Motion.pop, value: pulse)
                Text(summary.mine?.label ?? "React")
                    .font(Tokens.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(summary.mine?.tint ?? Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)
            .liquidGlass(radius: Tokens.Radius.pill)
        }
        .buttonStyle(.plain)
        .contextMenu { picker }
        .accessibilityLabel(summary.mine == nil ? "React" : "Your reaction: \(summary.mine!.label)")
        .accessibilityHint("Double-tap to react, long-press to choose a reaction")
    }

    private var picker: some View {
        ForEach(ReactionKind.allCases, id: \.self) { kind in
            Button { onReact(kind) } label: {
                Text("\(kind.emoji)  \(kind.label)")
            }
        }
    }

    private var summaryView: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            HStack(spacing: -4) {
                ForEach(summary.top.prefix(3), id: \.self) { kind in
                    Text(kind.emoji).font(.caption)
                }
            }
            Text("\(summary.total)")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.textSecondary)
        }
        .accessibilityLabel("\(summary.total) reactions")
    }
}
