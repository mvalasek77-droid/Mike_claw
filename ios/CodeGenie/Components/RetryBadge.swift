import SwiftUI

/// Tiny pill that appears in the build header when the swarm is
/// looping Coder + Integrator after a red Unit Tester. Reads its data
/// from `CostTracker` which already aggregates `retry.attempt` events
/// from the SSE stream.
struct RetryBadge: View {
    @ObservedObject var tracker: CostTracker

    var body: some View {
        if tracker.retryAttempts > 0 {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LiquidGlass.warning)
                    .symbolEffect(.rotate, options: .repeating, isActive: tracker.retryAttempts < tracker.maxRetries)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Retry")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(tracker.retryAttempts) / \(max(tracker.maxRetries, tracker.retryAttempts))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(LiquidGlass.warning.opacity(0.4)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Retry attempt \(tracker.retryAttempts) of \(max(tracker.maxRetries, tracker.retryAttempts))")
            .transition(.scale.combined(with: .opacity))
        }
    }
}
