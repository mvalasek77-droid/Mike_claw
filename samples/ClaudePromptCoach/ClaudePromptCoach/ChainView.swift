import SwiftUI

/// Compose-don't-clone: chain the base Skill with one or more others
/// into a new Skill whose instructions run in sequence. The originals
/// are untouched; the composition records where it came from so the
/// detail view can show "Chained from: …".
struct ChainView: View {
    let baseSkill: Skill

    @EnvironmentObject private var store: SkillStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID> = []
    @State private var composedTitle: String = ""

    private var candidates: [Skill] {
        store.skills.filter { $0.id != baseSkill.id }
    }

    private var selectedSkills: [Skill] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    private var defaultTitle: String {
        guard let first = selectedSkills.first else { return baseSkill.title }
        return "\(baseSkill.title) + \(first.title)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        picker
                        if !selectedSkills.isEmpty { preview }
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Chain Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save chain") { saveChain() }
                        .disabled(selectedSkills.isEmpty)
                        .accessibilityLabel("Save the chained Skill")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start from \(baseSkill.title)")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Pick the Skills to run after it. Their instructions are stitched into one new Skill — the originals stay exactly as they are.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Chain with", systemImage: "link")
            if candidates.isEmpty {
                Text("You need at least one other Skill in the Library to chain.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .glassCard()
            } else {
                ForEach(candidates) { skill in
                    Button {
                        toggle(skill)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIDs.contains(skill.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(selectedIDs.contains(skill.id) ? Theme.accent : Theme.secondaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text(skill.summary)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassCard()
                    .accessibilityLabel("\(skill.title). \(selectedIDs.contains(skill.id) ? "Selected" : "Not selected")")
                    .accessibilityHint("Toggles this Skill in the chain")
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "New Skill", systemImage: "sparkles")
            VStack(alignment: .leading, spacing: 10) {
                TextField(defaultTitle, text: $composedTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Title for the chained Skill")
                Text("Runs \(baseSkill.title), then \(selectedSkills.map(\.title).joined(separator: ", ")). \(chainedInstructions.count) steps total.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }

    private var chainedInstructions: [String] {
        var steps: [String] = ["— \(baseSkill.title) —"]
        steps.append(contentsOf: baseSkill.instructions)
        for skill in selectedSkills {
            steps.append("— then \(skill.title) —")
            steps.append(contentsOf: skill.instructions)
        }
        return steps
    }

    private func toggle(_ skill: Skill) {
        if selectedIDs.contains(skill.id) {
            selectedIDs.remove(skill.id)
        } else {
            selectedIDs.insert(skill.id)
        }
        Haptics.tap()
    }

    private func saveChain() {
        let title = composedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let chained = Skill(
            title: title.isEmpty ? defaultTitle : title,
            summary: "Chain of \(([baseSkill] + selectedSkills).map(\.title).joined(separator: " → ")).",
            instructions: chainedInstructions,
            tools: Array(Set(baseSkill.tools + selectedSkills.flatMap(\.tools))),
            chainedFrom: ([baseSkill] + selectedSkills).map(\.title)
        )
        store.add(chained)
        dismiss()
    }
}
