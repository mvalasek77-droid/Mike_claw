import SwiftUI

/// Surfaces `ScriptDoctor`'s craft/format findings — the things a contest
/// reader or studio screener notices that neither Final Draft nor Arc Studio
/// check for automatically, since both stop at format compliance.
struct ScriptDoctorView: View {
    let screenplay: Screenplay

    private var issues: [ScriptIssue] { ScriptDoctor.analyze(screenplay) }

    private var grouped: [(category: String, issues: [ScriptIssue])] {
        let order = ["Pacing", "Dialogue", "Continuity", "Craft"]
        let dict = Dictionary(grouping: issues, by: \.category)
        return order.compactMap { key in
            guard let items = dict[key] else { return nil }
            return (key, items)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard

                if issues.isEmpty {
                    GlassCard {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(Palette.success)
                            Text("No craft flags right now")
                                .font(.headline)
                                .foregroundStyle(Palette.primaryText)
                            Text("Script Doctor re-checks every time you open this tab.")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } else {
                    ForEach(grouped, id: \.category) { group in
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(group.category)
                                ForEach(group.issues) { issue in
                                    issueRow(issue)
                                    if issue.id != group.issues.last?.id {
                                        Divider().overlay(Palette.secondaryText.opacity(0.12))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var summaryCard: some View {
        let warnings = issues.filter { $0.severity == .warning }.count
        let suggestions = issues.filter { $0.severity == .suggestion }.count
        return GlassCard(tier: .raised) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SCRIPT DOCTOR").font(.labelSmall).foregroundStyle(Palette.accent)
                Text(issues.isEmpty ? "Reads clean" : "\(issues.count) craft note\(issues.count == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                Text("A reader's-eye pass for pacing, dialogue, and continuity — not formatting. Run it before you send pages out.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                if warnings > 0 || suggestions > 0 {
                    HStack(spacing: 8) {
                        if warnings > 0 { Pill(text: "\(warnings) to fix", color: Palette.danger) }
                        if suggestions > 0 { Pill(text: "\(suggestions) worth a look", color: Palette.accent) }
                    }
                }
            }
        }
    }

    private func issueRow(_ issue: ScriptIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.symbol)
                .foregroundStyle(color(for: issue.severity))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(issue.detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for severity: ScriptIssue.Severity) -> Color {
        switch severity {
        case .warning: return Palette.danger
        case .suggestion: return Palette.accent
        case .info: return Palette.secondaryText
        }
    }
}
