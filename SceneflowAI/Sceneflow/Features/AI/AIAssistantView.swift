import SwiftUI
import UIKit

/// The per-script AI panel. Pick a tool, it runs against the right slice of the
/// script (whole document or current scene), and the result can be copied or
/// inserted straight into the screenplay.
struct AIAssistantView: View {
    @Binding var screenplay: Screenplay
    @EnvironmentObject private var ai: AIService
    @EnvironmentObject private var entitlements: Entitlements

    @State private var activeTool: AITool?
    @State private var result: String = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var focusCharacter: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !ai.isConfigured {
                    GlassCard(tier: .raised) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(Palette.warning)
                            Text("Running in demo mode. Add your Anthropic API key in Settings for live results.")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }

                if !entitlements.isPro {
                    HStack {
                        Pill(text: "\(entitlements.remainingFreeAI) free AI assists left", color: Palette.ink)
                        Spacer()
                        Button("Go Pro") { showPaywall = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(AITool.allCases) { tool in
                        Button {
                            run(tool)
                        } label: { AIToolTile(tool: tool) }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("AI Tools")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeTool) { tool in
            AIResultSheet(
                tool: tool,
                result: $result,
                isRunning: $isRunning,
                errorMessage: $errorMessage,
                canInsert: tool.scope == .scene,
                onInsert: { insertIntoScript(result) },
                onRetry: { run(tool) }
            )
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Run

    private func run(_ tool: AITool) {
        guard entitlements.canUseAI else {
            showPaywall = true
            return
        }
        activeTool = tool
        result = ""
        errorMessage = nil
        isRunning = true

        let context = contextText(for: tool)
        Task { @MainActor in
            do {
                let text = try await ai.run(tool, context: context,
                                            screenplay: screenplay,
                                            focusCharacter: focusCharacter)
                result = text
                entitlements.recordAIUse()
            } catch {
                errorMessage = error.localizedDescription
            }
            isRunning = false
        }
    }

    /// Document tools see the whole script (Fountain); scene tools see the last
    /// scene so "Continue Scene" picks up where the writer is.
    private func contextText(for tool: AITool) -> String {
        switch tool.scope {
        case .document:
            let full = FountainParser.serialize(screenplay.elements)
            return String(full.prefix(16000)) // keep prompts bounded
        case .scene:
            return FountainParser.serialize(lastScene())
        }
    }

    private func lastScene() -> [ScreenplayElement] {
        guard let lastHeadingIndex = screenplay.elements.lastIndex(where: { $0.type == .sceneHeading })
        else { return screenplay.elements }
        return Array(screenplay.elements[lastHeadingIndex...])
    }

    private func insertIntoScript(_ text: String) {
        let parsed = FountainParser.parse(text)
        screenplay.elements.append(contentsOf: parsed)
        Haptics.success()
    }
}

struct AIToolTile: View {
    let tool: AITool

    var body: some View {
        GlassCard(tier: .raised, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tool.symbol)
                    .font(.title2)
                    .foregroundStyle(Palette.accent)
                Text(tool.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.primaryText)
                Text(tool.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        }
    }
}

struct AIResultSheet: View {
    let tool: AITool
    @Binding var result: String
    @Binding var isRunning: Bool
    @Binding var errorMessage: String?
    var canInsert: Bool
    var onInsert: () -> Void
    var onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Thinking…").foregroundStyle(Palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    } else if let errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle).foregroundStyle(Palette.warning)
                            Text(errorMessage)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Palette.secondaryText)
                            Button("Try again", action: onRetry)
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.accent)
                        }
                        .padding(.top, 40)
                    } else {
                        Text(result)
                            .font(.callout)
                            .textSelection(.enabled)
                            .foregroundStyle(Palette.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isRunning && errorMessage == nil {
                        Menu {
                            Button {
                                UIPasteboard.general.string = result
                                Haptics.success()
                            } label: { Label("Copy", systemImage: "doc.on.doc") }
                            if canInsert {
                                Button {
                                    onInsert(); dismiss()
                                } label: { Label("Insert into script", systemImage: "text.insert") }
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
