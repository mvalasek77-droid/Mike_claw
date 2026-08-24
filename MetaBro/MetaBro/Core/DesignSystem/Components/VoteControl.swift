import SwiftUI

/// Reddit-style up/down vote control with springy bounce + adaptive haptics.
/// Idempotent: tapping the active direction clears the vote (no double-count).
struct VoteControl: View {
    let score: Int
    let myVote: VoteDirection
    let onVote: (VoteDirection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var poppedDirection: VoteDirection? = nil

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            arrow(.up, system: "chevron.up")
            Text(score.abbreviated)
                .font(Tokens.Typography.score)
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText(value: Double(score)))
                .lineLimit(1)
            arrow(.down, system: "chevron.down")
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.sm)
        .fixedSize()
        .liquidGlass(radius: Tokens.Radius.pill)
    }

    private func arrow(_ direction: VoteDirection, system: String) -> some View {
        Button {
            let next: VoteDirection = (myVote == direction) ? .none : direction
            HapticsEngine.shared.play(.vote)
            if !reduceMotion {
                withAnimation(Tokens.Motion.pop) { poppedDirection = direction }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    withAnimation(Tokens.Motion.pop) { poppedDirection = nil }
                }
            }
            onVote(next)
        } label: {
            Image(systemName: system)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(myVote == direction ? direction.tint : Tokens.Color.textSecondary)
                .scaleEffect(poppedDirection == direction ? 1.2 : 1.0)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction == .up ? "Upvote" : "Downvote")
        .accessibilityValue(myVote == direction ? "selected" : "not selected")
    }

    private var scoreColor: Color {
        switch myVote {
        case .up: Tokens.Color.upvote
        case .down: Tokens.Color.downvote
        case .none: Tokens.Color.textPrimary
        }
    }
}

enum VoteDirection: Equatable {
    case up, down, none

    var tint: Color {
        switch self {
        case .up: Tokens.Color.upvote
        case .down: Tokens.Color.downvote
        case .none: Tokens.Color.textSecondary
        }
    }

    /// Net contribution of this vote to a score (used for optimistic updates).
    var delta: Int {
        switch self {
        case .up: 1
        case .down: -1
        case .none: 0
        }
    }
}

extension Int {
    /// 1200 -> "1.2k", 1_500_000 -> "1.5m"
    var abbreviated: String {
        let n = Double(abs(self))
        let sign = self < 0 ? "-" : ""
        switch n {
        case 1_000_000...:
            return "\(sign)\((n / 1_000_000).rounded(to: 1))m"
        case 1_000...:
            return "\(sign)\((n / 1_000).rounded(to: 1))k"
        default:
            return "\(self)"
        }
    }
}

private extension Double {
    func rounded(to places: Int) -> String {
        let formatted = String(format: "%.\(places)f", self)
        // Trim a trailing ".0" for clean display (1.0k -> 1k).
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
}
