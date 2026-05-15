import SwiftUI

/// Compact running-cost pill. Shows total $, total tokens, and per-agent
/// breakdown when tapped.
struct CostBadge: View {
    @ObservedObject var tracker: CostTracker
    @State private var expanded = false

    var body: some View {
        Button {
            Motion.run(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tracker.capHit ? "exclamationmark.triangle.fill" : "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tracker.capHit ? LiquidGlass.warning : LiquidGlass.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text(spendLabel)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .contentTransition(.numericText())
                    Text(capCaption)
                        .font(.caption2)
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(tracker.capHit ? LiquidGlass.warning.opacity(0.5) : .white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            breakdown
                .padding(16)
                .frame(minWidth: 240)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spend so far").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text(tracker.totalLabel).font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            Divider()
            if tracker.perAgent.isEmpty {
                Text("Waiting for first agent to finish…")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tracker.perAgent.values.sorted(by: { $0.usd > $1.usd })) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.agent).font(.system(size: 12, weight: .semibold, design: .rounded))
                        Spacer()
                        Text(String(format: "$%.3f", row.usd))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("(\(row.inputTokens + row.outputTokens))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var formattedTokens: String {
        let total = tracker.inputTokens + tracker.outputTokens
        if total < 1_000 { return "\(total)" }
        if total < 1_000_000 { return String(format: "%.1fk", Double(total) / 1_000) }
        return String(format: "%.1fM", Double(total) / 1_000_000)
    }

    /// Prefer the backend's authoritative spend when it has reported a
    /// `cost.update`. Otherwise fall back to the local computation
    /// (which matters during simulated builds).
    private var spendLabel: String {
        if tracker.backendSpendUSD > 0 {
            return String(format: "$%.3f", tracker.backendSpendUSD)
        }
        return tracker.totalLabel
    }

    /// Caption shows the cap when one is set, otherwise token count.
    private var capCaption: String {
        if let cap = tracker.backendCapUSD {
            return tracker.capHit
                ? String(format: "cap $%.2f hit", cap)
                : String(format: "of $%.2f cap", cap)
        }
        return "\(formattedTokens) tok"
    }
}
