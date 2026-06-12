import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: ProjectStore
    @ObservedObject private var log = BugLog.shared
    @State private var showBugReport = false

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    brandHeader

                    GlassCard(title: "Appearance", icon: "circle.lefthalf.filled") {
                        GlassSegmented(
                            options: AppState.Appearance.allCases.map { ($0, $0.label) },
                            selection: Binding(
                                get: { appState.appearance },
                                set: { appState.appearance = $0 }
                            )
                        )
                    }

                    GlassCard(title: "Feedback", icon: "hand.tap.fill") {
                        ToggleRow(label: "Reduce haptics", systemImage: "iphone.radiowaves.left.and.right",
                                  isOn: $appState.reduceHaptics)
                        Text("Honors your system Reduce Motion setting automatically for all animations.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    }

                    GlassCard(title: "Help & feedback", icon: "questionmark.circle.fill") {
                        VStack(spacing: 4) {
                            Button { showBugReport = true } label: {
                                settingsRow(icon: "ladybug.fill", title: "Report a bug",
                                            subtitle: "Send us what went wrong")
                            }
                            .buttonStyle(.plain)

                            Divider().overlay(.white.opacity(0.1))

                            NavigationLink {
                                DiagnosticsView()
                            } label: {
                                settingsRow(icon: log.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                                            title: "Diagnostics",
                                            subtitle: log.hasFailures
                                                ? "\(log.entries.count) events · some issues recorded"
                                                : "Everything's running cleanly",
                                            tint: log.hasFailures ? LiquidGlass.warning : LiquidGlass.success)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    GlassCard(title: "Privacy", icon: "lock.shield.fill", tint: LiquidGlass.success) {
                        VStack(alignment: .leading, spacing: 8) {
                            privacyLine("Everything runs on-device.")
                            privacyLine("Screenshots never leave your iPhone.")
                            privacyLine("No accounts, no tracking, no analytics.")
                        }
                    }

                    GlassCard(title: "About", icon: "info.circle.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            row("Version", appVersion)
                            row("Saved sets", "\(store.projects.count)")
                            Divider().overlay(.white.opacity(0.1))
                            Text("Screenshot Studio turns raw iPhone screenshots into App Store Connect–ready images, rendered at exactly the pixel sizes Apple requires.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 120)
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showBugReport) {
            BugReportView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String,
                             tint: Color = LiquidGlass.accent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.3))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            StudioMark(size: 76)
            StudioWordmark()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
        }
    }

    private func privacyLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(LiquidGlass.success)
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.8))
        }
    }
}
