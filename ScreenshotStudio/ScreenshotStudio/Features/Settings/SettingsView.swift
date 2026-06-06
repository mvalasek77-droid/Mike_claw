import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: ProjectStore

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
