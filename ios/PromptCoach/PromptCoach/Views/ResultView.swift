import SwiftUI
import UIKit

/// The coaching result: model recommendation (with override), the coached
/// prompt, the report card, and the named techniques with Learn links.
struct ResultView: View {
    @EnvironmentObject private var app: AppState
    @State var result: CoachResult
    @State private var copied = false
    @State private var learn: Technique?

    private var tint: Color { Glass.tint(for: result.chosenModelID) }

    var body: some View {
        ZStack {
            GlassBackground(tint: tint).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modelPicker
                    reportCard
                    promptCard
                    if let schema = result.structuredSchema { schemaCard(schema) }
                    techniques
                }
                .padding(20)
            }
        }
        .navigationTitle("Coached")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $learn) { LearnView(technique: $0) }
        .animation(Glass.motion, value: result.chosenModelID)
    }

    // MARK: Model recommendation + override

    private var modelPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Recommended", systemImage: "sparkle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Glass.primaryText.opacity(0.55))
                    Spacer()
                    if let m = app.pack.model(id: result.recommendedModelID) {
                        Text(m.priceLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Glass.primaryText.opacity(0.5))
                    }
                }
                Text("Task looks like: \(TaskType(rawValue: result.taskType)?.label ?? result.taskType)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Glass.primaryText.opacity(0.7))

                // Segmented override — user can pick any model.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(app.pack.models) { m in
                            modelChip(m)
                        }
                    }
                }
                if let m = app.pack.model(id: result.chosenModelID) {
                    Text(m.oneLiner)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Glass.primaryText.opacity(0.8))
                        .padding(.top, 2)
                }
            }
            .padding(16)
        }
    }

    private func modelChip(_ m: ModelProfile) -> some View {
        let selected = m.id == result.chosenModelID
        return Button {
            Haptics.select()
            var updated = app.coach(result.ramble, overrideModelID: m.id)
            updated.id = result.id; updated.date = result.date
            withAnimation(Glass.motion) { result = updated }
            app.save(updated) // updates history entry copy
        } label: {
            VStack(spacing: 2) {
                Text(m.name.replacingOccurrences(of: "Claude ", with: ""))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if m.id == result.recommendedModelID {
                    Text("best fit").font(.system(size: 9, weight: .bold, design: .rounded)).opacity(0.8)
                }
            }
            .foregroundStyle(selected ? .white : Glass.primaryText.opacity(0.7))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                Group {
                    if selected { Capsule().fill(Glass.tint(for: m.id)) }
                    else { Capsule().fill(.ultraThinMaterial) }
                }
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name)\(m.id == result.recommendedModelID ? ", recommended" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Report card

    private var reportCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Your ramble scored")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                    Spacer()
                    Text("\(result.reportCard.score)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text("/100").font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Glass.primaryText.opacity(0.5))
                }
                ForEach(result.reportCard.lines) { line in
                    HStack(spacing: 8) {
                        Image(systemName: line.passed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(line.passed ? Glass.success : Glass.warning)
                            .font(.system(size: 14))
                        Text(line.checks)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Glass.primaryText.opacity(line.passed ? 0.55 : 0.85))
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
    }

    private var scoreColor: Color {
        switch result.reportCard.score {
        case ..<40: return Glass.warning
        case 40..<75: return Glass.accent
        default: return Glass.success
        }
    }

    // MARK: Coached prompt

    private var promptCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model-ready prompt")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                    Spacer()
                    ShareLink(item: result.rewrittenPrompt) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = result.rewrittenPrompt
                        Haptics.tap()
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(copied ? Glass.success : tint)
                    }
                    .accessibilityLabel(copied ? "Copied" : "Copy prompt")
                }
                Text(result.rewrittenPrompt)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Glass.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    private func schemaCard(_ schema: String) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            VStack(alignment: .leading, spacing: 8) {
                Label("JSON schema (structured output)", systemImage: "curlybraces")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Glass.primaryText.opacity(0.6))
                Text(schema)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Glass.primaryText.opacity(0.85))
                    .textSelection(.enabled)
            }
            .padding(14)
        }
    }

    // MARK: Techniques (What I changed)

    private var techniques: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What I changed")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Glass.primaryText.opacity(0.55)).textCase(.uppercase)
            ForEach(result.techniquesApplied) { t in
                Button {
                    if let tech = app.pack.technique(id: t.techniqueID) { learn = tech }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(tint)
                            .font(.system(size: 14)).padding(.top, 1)
                        Text(t.label)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Glass.primaryText.opacity(0.9))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if app.pack.technique(id: t.techniqueID) != nil {
                            Image(systemName: "info.circle").foregroundStyle(Glass.primaryText.opacity(0.35))
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(app.pack.technique(id: t.techniqueID) == nil)
            }
        }
    }
}
