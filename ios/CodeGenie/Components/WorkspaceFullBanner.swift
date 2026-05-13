import SwiftUI

/// Yellow strip in BuildScreen that surfaces the backend's
/// `workspace.full` event. Shown only when the latest event for this
/// run includes a state. Tapping the inline link opens Settings →
/// Build cost cap (the user lifts the snapshot cap there).
struct WorkspaceFullBanner: View {
    @ObservedObject var tracker: CostTracker
    var onOpenSettings: () -> Void

    var body: some View {
        if let state = tracker.workspaceFull {
            GlassSurface(tier: .deep, corner: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill.badge.exclamationmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(LiquidGlass.warning)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LiquidGlass.warning.opacity(0.18)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Snapshot too big — \(state.label)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(detail(for: state))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Settings →", action: onOpenSettings)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(12)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Snapshot \(state.label) too large; tap to open settings")
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func detail(for state: CostTracker.WorkspaceFullState) -> String {
        let size = formatMB(state.sizeBytes)
        let cap = formatMB(state.capBytes)
        return "\(size) > \(cap) cap. The label kept; files weren't persisted."
    }

    private func formatMB(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        return mb < 1 ? String(format: "%.0fKB", Double(bytes) / 1024.0)
                      : String(format: "%.1fMB", mb)
    }
}
