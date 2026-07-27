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
                    if let report = result.tokenReport { tokenCard(report) }
                    promptCard
                    sharpenButton
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
                        .font(Type.label)
                        .foregroundStyle(Glass.primaryText.opacity(0.55))
                    Spacer()
                    if let m = app.pack.model(id: result.recommendedModelID) {
                        Text(m.priceLabel)
                            .font(Type.caption)
                            .foregroundStyle(Glass.primaryText.opacity(0.5))
                    }
                }
                Text("Task looks like: \(TaskType(rawValue: result.taskType)?.label ?? result.taskType)")
                    .font(Type.caption)
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
                        .font(Type.caption)
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
            let updated = app.recoach(result, modelID: m.id)
            withAnimation(Glass.motion) { result = updated }
            app.save(updated) // updates history entry copy
        } label: {
            VStack(spacing: 2) {
                Text(m.name.replacingOccurrences(of: "Claude ", with: ""))
                    .font(Type.label)
                if m.id == result.recommendedModelID {
                    Text("best fit").font(Type.captionB).opacity(0.8)
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
                        .font(Type.label)
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                    Spacer()
                    Text("\(result.reportCard.score)")
                        .font(Type.title)
                        .foregroundStyle(scoreColor)
                    Text("/100").font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.5))
                }
                ForEach(result.reportCard.lines) { line in
                    HStack(spacing: 8) {
                        Image(systemName: line.passed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(line.passed ? Glass.success : Glass.warning)
                            .font(Type.secondary)
                        Text(line.checks)
                            .font(Type.caption)
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

    // MARK: Token & cost

    /// What this prompt costs, approximately, on the chosen model.
    ///
    /// Deliberately honest in two directions: the numbers are labelled as
    /// estimates (no tokenizer runs on device and the app makes no network
    /// calls), and when structure makes the prompt *longer* than the ramble it
    /// says so and explains the trade rather than hiding it.
    private func tokenCard(_ report: TokenReport) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tokens & cost")
                        .font(Type.label)
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                    Text("approx.")
                        .font(Type.captionB)
                        .foregroundStyle(Glass.primaryText.opacity(0.4))
                    Spacer()
                    Text(TokenReport.money(report.inputCostUSD) + " / run")
                        .font(Type.label)
                        .foregroundStyle(tint)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("≈ \(report.promptTokens)")
                        .font(Type.title)
                        .foregroundStyle(Glass.primaryText)
                    Text("input tokens on \(app.pack.model(id: result.chosenModelID)?.shortName ?? "this model")")
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.6))
                }

                if report.wordingTokensSaved > 0 {
                    tokenRow("scissors", Glass.success,
                             "Trimmed ≈\(report.wordingTokensSaved) tokens of filler and repetition from your wording")
                }
                if report.promptIsLonger {
                    tokenRow("plus.forwardslash.minus", Glass.primaryText.opacity(0.55),
                             "Structure added tokens on top of your ≈\(report.rambleTokens). That's the trade: one vague round-trip costs far more than a scope line.")
                }
                if report.costSavedUSD > 0 {
                    tokenRow("arrow.down.circle", Glass.success,
                             "\(TokenReport.money(report.costSavedUSD)) per run cheaper than running this on \(report.priciestModelName)")
                }

                Text("Estimated on device from character counts and \(app.pack.model(id: result.chosenModelID)?.shortName ?? "the model")'s tokenizer ratio — not an exact count. Output tokens are billed separately.")
                    .font(Type.caption)
                    .foregroundStyle(Glass.primaryText.opacity(0.45))
                    .padding(.top, 2)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Approximately \(report.promptTokens) input tokens on the chosen model, about \(TokenReport.money(report.inputCostUSD)) per run")
    }

    private func tokenRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(Type.caption)
                .foregroundStyle(color)
                .padding(.top, 2)
            Text(text)
                .font(Type.caption)
                .foregroundStyle(Glass.primaryText.opacity(0.75))
            Spacer(minLength: 0)
        }
    }

    // MARK: Coached prompt

    private var promptCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Model-ready prompt")
                        .font(Type.label)
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                    Spacer()
                    ShareLink(item: result.rewrittenPrompt) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .simultaneousGesture(TapGesture().onEnded { app.noteAccepted(result) })
                    Button {
                        UIPasteboard.general.string = result.rewrittenPrompt
                        app.noteAccepted(result)
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
                    .font(Type.mono)
                    .foregroundStyle(Glass.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }

    /// Meta-prompting: a second pass that restructures the prompt into tagged
    /// sections and fills the gaps the first pass only flagged.
    @ViewBuilder
    private var sharpenButton: some View {
        if result.isSharpened {
            Label("Sharpened — restructured into tagged sections", systemImage: "checkmark.seal.fill")
                .font(Type.caption)
                .foregroundStyle(Glass.success)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button {
                Haptics.success()
                let sharper = app.sharpen(result)
                withAnimation(Glass.motion) { result = sharper }
                app.save(sharper)
            } label: {
                Label("Sharpen it further", systemImage: "sparkles")
                    .font(Type.bodyMed)
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(tint.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: Glass.cornerMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Glass.cornerMedium, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Runs a second pass that adds XML structure, examples, and explicit constraints")
        }
    }

    private func schemaCard(_ schema: String) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            VStack(alignment: .leading, spacing: 8) {
                Label("JSON schema (structured output)", systemImage: "curlybraces")
                    .font(Type.label)
                    .foregroundStyle(Glass.primaryText.opacity(0.6))
                Text(schema)
                    .font(Type.mono)
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
                .font(Type.label)
                .foregroundStyle(Glass.primaryText.opacity(0.55)).textCase(.uppercase)
            ForEach(result.techniquesApplied) { t in
                Button {
                    if let tech = app.pack.technique(id: t.techniqueID) { learn = tech }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(tint)
                            .font(Type.secondary).padding(.top, 1)
                        Text(t.label)
                            .font(Type.secondary)
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
