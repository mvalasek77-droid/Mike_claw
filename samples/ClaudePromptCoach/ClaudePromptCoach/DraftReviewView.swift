import SwiftUI

/// Shows the drafted Skill (with its mode-specific shape), runs the Taste
/// Test before saving, then offers to capture what the session taught.
struct DraftReviewView: View {
    @EnvironmentObject private var store: SkillStore

    let draft: SkillDraft
    let onFinished: () -> Void

    @State private var showingTasteTest = false
    @State private var showingCapture = false
    @State private var savedSkillID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleCard

                if let spec = draft.specDocument {
                    SectionHeader(title: "Spec first", systemImage: "doc.text")
                    Text(spec)
                        .font(.callout.monospaced())
                        .foregroundStyle(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }

                SectionHeader(title: "Instructions", systemImage: "list.number")
                numberedList(draft.instructions)

                if !draft.subPrompts.isEmpty {
                    SectionHeader(title: "Parallel sub-agents", systemImage: "square.split.2x2")
                    ForEach(Array(draft.subPrompts.enumerated()), id: \.offset) { _, prompt in
                        Text(prompt)
                            .font(.callout)
                            .foregroundStyle(Theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                    if let synth = draft.synthPrompt {
                        Text(synth)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard()
                    }
                }

                if !draft.verificationChecklist.isEmpty {
                    SectionHeader(title: "Verify before you build", systemImage: "checkmark.shield")
                    numberedList(draft.verificationChecklist)
                }

                if !draft.tools.isEmpty {
                    SectionHeader(title: "Suggested tools", systemImage: "wrench.and.screwdriver")
                    ForEach(draft.tools, id: \.self) { tool in
                        Label(tool, systemImage: "paperclip")
                            .font(.callout)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                saveButton
            }
            .padding()
        }
        .sheet(isPresented: $showingTasteTest) {
            TasteTestSheet(
                onKeepAsSkill: saveAsSkill,
                onKeepAsNote: saveAsNote
            )
            .presentationDetents([.medium])
        }
        .alert("Should we capture what we learned?", isPresented: $showingCapture) {
            Button("Capture it") { captureLearnings() }
            Button("Not this time", role: .cancel) { onFinished() }
        } message: {
            Text("The session surfaced new rules and edge cases. Add them to the Skill with a changelog entry — never silently.")
        }
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(draft.mode.title, systemImage: draft.mode.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(draft.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(draft.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func numberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var saveButton: some View {
        Button {
            Haptics.tap()
            showingTasteTest = true
        } label: {
            Label("Save — run the Taste Test", systemImage: "checkmark.seal")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save this draft")
        .accessibilityHint("Runs the two-question Taste Test before saving")
    }

    // MARK: - Saving

    private func saveAsSkill() {
        var skill = Skill(
            title: draft.title,
            summary: draft.summary,
            instructions: assembledInstructions(),
            tools: draft.tools
        )
        skill.changelog.append(ChangelogEntry(summary: "Passed the Taste Test — saved as a Skill (\(draft.mode.title))"))
        savedSkillID = skill.id
        store.add(skill)
        if draft.learnedRules.isEmpty {
            onFinished()
        } else {
            // Let the Taste Test sheet finish dismissing before presenting the alert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingCapture = true
            }
        }
    }

    private func saveAsNote() {
        let note = OneOffNote(
            title: draft.title,
            body: assembledInstructions().joined(separator: "\n")
        )
        store.add(note)
        onFinished()
    }

    private func assembledInstructions() -> [String] {
        var steps = draft.instructions
        if let spec = draft.specDocument {
            steps.insert("Spec: \(spec)", at: 0)
        }
        steps.append(contentsOf: draft.subPrompts)
        if let synth = draft.synthPrompt {
            steps.append(synth)
        }
        steps.append(contentsOf: draft.verificationChecklist.map { "Verify: \($0)" })
        return steps
    }

    private func captureLearnings() {
        guard let id = savedSkillID else {
            onFinished()
            return
        }
        store.evolve(
            skillID: id,
            newRules: draft.learnedRules,
            changeSummary: "Captured from coach session: \(draft.learnedRules.count) new rule(s)"
        )
        onFinished()
    }
}

// MARK: - Taste Test

/// Two yes/no questions before saving: keep the library free of junk.
struct TasteTestSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onKeepAsSkill: () -> Void
    let onKeepAsNote: () -> Void

    @State private var willReuse = false
    @State private var beatsManual = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("The Taste Test")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text("Both yes → it earns a place as a Skill. Otherwise it's saved as a one-off note.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)

                Toggle("Will you use this more than 3 times?", isOn: $willReuse)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.primaryText)
                    .glassCard()
                Toggle("Would the output beat the last five times you did it manually?", isOn: $beatsManual)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.primaryText)
                    .glassCard()

                Button {
                    dismiss()
                    if willReuse && beatsManual {
                        onKeepAsSkill()
                    } else {
                        onKeepAsNote()
                    }
                } label: {
                    Text(willReuse && beatsManual ? "Save as Skill" : "Save as one-off note")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(willReuse && beatsManual ? "Save as Skill" : "Save as one-off note")

                Spacer()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
