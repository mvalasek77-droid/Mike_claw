import SwiftUI

// MARK: - Mode pills

/// The four coaching modes as pill buttons on the session screen.
struct ModePillRow: View {
    @Binding var selection: CoachMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoachMode.allCases) { mode in
                    Button {
                        Haptics.tap()
                        selection = mode
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selection == mode ? Theme.accent.opacity(0.25) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selection == mode ? Theme.accent : Color.white.opacity(0.12),
                                    lineWidth: 1
                                )
                            )
                            .foregroundStyle(selection == mode ? Theme.accent : Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.title) mode")
                    .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Heat trail

/// Small bars showing how recently a Skill was updated: one bar per day
/// for the last ten days, brighter when an update happened that day.
struct HeatTrailView: View {
    let updateDates: [Date]
    private let days = 10

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<days, id: \.self) { offset in
                let daysAgo = days - 1 - offset
                let active = hasUpdate(daysAgo: daysAgo)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? Theme.accent : Color.white.opacity(0.12))
                    .frame(width: 4, height: active ? 14 : 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Update heat trail, \(recentCount) updates in the last \(days) days")
    }

    private func hasUpdate(daysAgo: Int) -> Bool {
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { return false }
        return updateDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    private var recentCount: Int {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: .now) else { return 0 }
        return updateDates.filter { $0 > cutoff }.count
    }
}

// MARK: - Skill card

struct SkillCardView: View {
    let skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(skill.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if skill.recentlyEvolved {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityLabel("Recently evolved")
                }
            }
            Text(skill.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            HStack {
                Label("Used \(skill.timesUsed)×", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                HeatTrailView(updateDates: skill.updateDates)
            }
        }
        .glassCard()
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}
