import SwiftUI

/// Identifiable text wrapper so a report string can drive `.sheet(item:)`.
private struct ShareText: Identifiable {
    let id = UUID()
    let text: String
}

/// A developer-facing log of anything that failed at runtime. Privacy-first:
/// it lives only on this device and is shared only when the user chooses to.
struct DiagnosticsView: View {
    @ObservedObject private var log = BugLog.shared
    @State private var share: ShareText?
    @State private var confirmClear = false

    private var ordered: [BugLog.Entry] { log.entries.reversed() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary

                if log.entries.isEmpty {
                    empty
                } else {
                    ForEach(ordered) { entry in
                        row(entry)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .background(LiquidGlassBackground().ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        share = ShareText(text: shareableLog())
                    } label: { Label("Share log", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: { Label("Clear log", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Log actions")
                .disabled(log.entries.isEmpty)
            }
        }
        .confirmationDialog("Clear the diagnostics log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) {
                log.clear()
                Haptics.warning()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $share) { item in
            ShareSheet(items: [item.text])
        }
    }

    private var summary: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: log.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(log.hasFailures ? LiquidGlass.warning : LiquidGlass.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.hasFailures ? "Some issues were recorded" : "No failures recorded")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text("\(log.entries.count) event\(log.entries.count == 1 ? "" : "s") logged on this device.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LiquidGlass.success)
            Text("Nothing to report")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Failures and warnings show up here if they ever happen.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func row(_ entry: BugLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.level.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(for: entry.level))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.category)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Spacer(minLength: 0)
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
                }
                Text(entry.message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidGlass.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(LiquidGlass.hairline, lineWidth: 0.5))
    }

    private func color(for level: BugLog.Level) -> Color {
        switch level {
        case .info: return LiquidGlass.accent
        case .warning: return LiquidGlass.warning
        case .error: return Color(red: 1.0, green: 0.42, blue: 0.42)
        }
    }

    private func shareableLog() -> String {
        BugLog.deviceSummary() + "\n\nDiagnostics:\n" + log.recentLogText()
    }
}

/// A friendly, user-facing "Report a bug" composer. It assembles a plain-text
/// report (description + optional diagnostics) and hands it to the share sheet,
/// so the user controls exactly what's sent and to whom.
struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var log = BugLog.shared

    @State private var description = ""
    @State private var includeDiagnostics = true
    @State private var share: ShareText?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tell us what went wrong and what you expected to happen. The more detail, the faster we can fix it.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Describe the bug…", text: $description, axis: .vertical)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                        .lineLimit(4...10)
                        .padding(14)
                        .background(LiquidGlass.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LiquidGlass.hairline, lineWidth: 0.5))

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ToggleRow(label: "Include diagnostics", systemImage: "stethoscope",
                                      isOn: $includeDiagnostics)
                            Text("Attaches your device model, app version and the recent on-device log. No screenshots or personal data are included.")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PrimaryButton(title: "Compose report", systemImage: "square.and.arrow.up") {
                        share = ShareText(text: log.makeReport(userDescription: description,
                                                               includeLog: includeDiagnostics))
                        Haptics.tap()
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(LiquidGlassBackground().ignoresSafeArea())
            .navigationTitle("Report a bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $share) { item in
                ShareSheet(items: [item.text])
            }
        }
    }
}
