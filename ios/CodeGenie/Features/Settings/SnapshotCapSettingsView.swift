import SwiftUI

/// Sheet shown from the WorkspaceFullBanner. The user lifts the
/// snapshot-bytes cap or disables it entirely; the value is sent on
/// every subsequent build's `startBuild` request. Backend default is
/// 256 MiB when nothing is set here.
struct SnapshotCapSettingsView: View {
    @StateObject private var creds = Credentials.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    capCard
                    explainerCard
                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Snapshot storage cap")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Per-build ceiling for snapshot files saved to the workspace. Stages above the cap keep their label but their bytes aren't persisted.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var capCard: some View {
        GlassCard(title: "Cap", icon: "externaldrive.fill", tint: LiquidGlass.warning) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { creds.snapshotCapMB != nil },
                    set: { on in
                        creds.setSnapshotCap(mb: on ? (creds.snapshotCapMB ?? 256) : nil)
                        Haptics.selection()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Override the backend default")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("Default is 256 MiB. Lower it to halt growth sooner; raise it for big projects.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                    }
                }
                .tint(LiquidGlass.warning)

                if let mb = creds.snapshotCapMB {
                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .foregroundStyle(LiquidGlass.warning)
                        Slider(
                            value: Binding(
                                get: { Double(mb) },
                                set: { creds.setSnapshotCap(mb: Int($0.rounded())) }
                            ),
                            in: 16...2048,
                            step: 16
                        )
                        .tint(LiquidGlass.warning)
                        Text("\(mb) MiB")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .frame(width: 84, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var explainerCard: some View {
        GlassCard(title: "What changes when the cap is hit", icon: "info.circle.fill", tint: LiquidGlass.accent) {
            VStack(alignment: .leading, spacing: 6) {
                explainerRow("Stage labels", "still recorded — resume() can skip them")
                explainerRow("File contents", "dropped from disk for the over-cap stage")
                explainerRow("Restore", "transcript still rewinds; files only roll back when the snapshot has bytes")
                explainerRow("Crash recovery", "unaffected; restores from the latest in-memory checkpoint")
            }
        }
    }

    private func explainerRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .padding(.top, 7)
                .foregroundStyle(LiquidGlass.accent.opacity(0.7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(k)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                Text(v)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
