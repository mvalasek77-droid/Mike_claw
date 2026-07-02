import SwiftUI

/// Full Skill view: description, instructions, tools, changelog, a Use
/// button (with the capture-what-we-learned dialog), and a Chain button.
struct SkillDetailView: View {
    @EnvironmentObject private var store: SkillStore

    let skillID: UUID

    @State private var showingChain = false
    @State private var showingCapture = false
    @State private var newRule = ""
    @State private var showingCopied = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let skill = store.skill(withID: skillID) {
                content(for: skill)
            } else {
                ContentUnavailableView("Skill not found", systemImage: "questionmark.circle")
            }
        }
        .navigationTitle(store.skill(withID: skillID)?.title ?? "Skill")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChain) {
            if let skill = store.skill(withID: skillID) {
                ChainView(baseSkill: skill)
            }
        }
        .alert("Should we capture what we learned?", isPresented: $showingCapture) {
            TextField("New rule, example, or edge case", text: $newRule)
            Button("Add to Skill") { capture() }
            Button("Not this time", role: .cancel) { newRule = "" }
        } message: {
            Text("Anything this use taught you gets appended with a changelog entry — the Skill is never modified silently.")
        }
    }

    private func content(for skill: Skill) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(for: skill)
                actionRow(for: skill)

                SectionHeader(title: "Instructions", systemImage: "list.number")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(skill.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                            Text(step)
                                .font(.callout)
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()

                if !skill.tools.isEmpty {
                    SectionHeader(title: "Tools", systemImage: "wrench.and.screwdriver")
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(skill.tools, id: \.self) { tool in
                            Label(tool, systemImage: "paperclip")
                                .font(.callout)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                }

                SectionHeader(title: "Changelog", systemImage: "clock.arrow.circlepath")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(skill.changelog.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.summary)
                                .font(.callout)
                                .foregroundStyle(Theme.primaryText)
                            Text(entry.date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            .padding()
            .accentPulse(on: store.evolutionPulse)
        }
    }

    private func header(for skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(skill.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if skill.recentlyEvolved {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, options: .repeating)
                        .accessibilityLabel("Recently evolved")
                }
            }
            if !skill.chainedFrom.isEmpty {
                Label("Chained from: \(skill.chainedFrom.joined(separator: ", "))", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
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

    private func actionRow(for skill: Skill) -> some View {
        HStack(spacing: 12) {
            Button {
                useSkill(skill)
            } label: {
                Label(showingCopied ? "Copied" : "Use", systemImage: showingCopied ? "checkmark" : "doc.on.clipboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use this Skill")
            .accessibilityHint("Copies the Skill as a paste-ready prompt, then asks whether to capture what you learned")

            Button {
                Haptics.tap()
                showingChain = true
            } label: {
                Label("Chain", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chain with other Skills")
            .accessibilityHint("Compose this Skill with others into one prompt")
        }
    }

    private func useSkill(_ skill: Skill) {
        UIPasteboard.general.string = CoachEngine.renderedPrompt(for: skill)
        store.recordUse(of: skill.id)
        Haptics.success()
        withAnimation { showingCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { showingCopied = false }
            showingCapture = true
        }
    }

    private func capture() {
        store.evolve(
            skillID: skillID,
            newRules: [newRule],
            changeSummary: "Captured after use: \(newRule.prefix(60))"
        )
        newRule = ""
    }
}
