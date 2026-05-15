import SwiftUI

struct DescribeAppView: View {
    var onSubmit: (AppDescription) -> Void

    @StateObject private var creds = Credentials.shared
    @State private var title: String = ""
    @State private var prompt: String = ""
    @State private var category: AppDescription.Category = .productivity
    @State private var style: AppDescription.Style = .liquidGlass
    @State private var showCostConfirm: Bool = false
    @FocusState private var focused: Field?

    private enum Field { case title, prompt }

    /// Plain-English explanation of why a build is or isn't possible
    /// right now, plus the safety check that prevents the user from
    /// committing money before they've set up an auth path.
    private var preflight: Preflight {
        switch creds.authMode {
        case .byok:
            let hasAnyKey = !creds.anthropicKey.isEmpty || !creds.openaiKey.isEmpty
            return hasAnyKey
                ? .ready("You're paying the AI provider directly per token. See estimate below.")
                : .blocked("Add an Anthropic or OpenAI key in Settings → Costs & keys first.")
        case .subscription:
            return .ready("Routed through your existing Claude / ChatGPT subscription via the paired Mac.")
        case .codegenie:
            return .ready("Charged against your CodeGenie hosted plan. Free tier covers 3 builds/month.")
        }
    }

    private var estimatedCost: Double {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        return model.estimatedBuildCostUSD()
    }

    private enum Preflight {
        case ready(String)
        case blocked(String)
        var isReady: Bool { if case .ready = self { return true } else { return false } }
        var message: String {
            switch self {
            case .ready(let s), .blocked(let s): return s
            }
        }
    }

    private let suggestions: [String] = [
        "A tide times app for surfers with a clean Apple-style UI",
        "Daily habit tracker with streaks and a calm, minimal look",
        "AI-powered pantry that suggests recipes from photos of my fridge",
        "Read-it-later for podcasts with chapter summaries",
        "Liquid-glass weather widget collection, no ads"
    ]

    var body: some View {
        ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    titleField
                    promptField
                    suggestionRow
                    categoryPicker
                    stylePicker
                    submitRow
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Describe your app").font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Be specific — like you're briefing a designer. CodeGenie scaffolds a full Xcode project from this.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleField: some View {
        GlassSurface(tier: .flat, corner: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("App name").font(.caption).foregroundStyle(LiquidGlass.primaryText.opacity(0.65)).textCase(.uppercase)
                TextField("e.g. TideRider", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .submitLabel(.next)
                    .focused($focused, equals: .title)
                    .onSubmit { focused = .prompt }
                    .accessibilityLabel("App name")
            }
            .padding(14)
        }
    }

    private var promptField: some View {
        GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should it do?").font(.caption).foregroundStyle(LiquidGlass.primaryText.opacity(0.65)).textCase(.uppercase)
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                    .focused($focused, equals: .prompt)
                    .accessibilityLabel("App description")
                    .overlay(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Describe screens, features, the vibe…")
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.45))
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(14)
        }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        prompt = s
                        if title.isEmpty { title = inferredTitle(from: s) }
                        Haptics.tap()
                    } label: {
                        Text(s)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category").font(.caption).foregroundStyle(LiquidGlass.primaryText.opacity(0.65)).textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppDescription.Category.allCases) { cat in
                        Chip(label: cat.label, icon: cat.systemImage, selected: cat == category) {
                            category = cat; Haptics.selection()
                        }
                    }
                }
            }
        }
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visual style").font(.caption).foregroundStyle(LiquidGlass.primaryText.opacity(0.65)).textCase(.uppercase)
            HStack(spacing: 8) {
                ForEach(AppDescription.Style.allCases) { s in
                    Chip(label: s.label, icon: nil, selected: s == style) {
                        style = s; Haptics.selection()
                    }
                }
            }
        }
    }

    private var submitRow: some View {
        VStack(spacing: 10) {
            preflightBanner
            PrimaryButton(title: "Build it", systemImage: "wand.and.stars", style: .filled) {
                let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanPrompt.count >= 12, preflight.isReady else { Haptics.error(); return }
                showCostConfirm = true
                Haptics.selection()
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 || !preflight.isReady)
            .opacity((prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 || !preflight.isReady) ? 0.5 : 1)
            Text("CodeGenie will generate the Xcode project, ask follow-ups, then run a build.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .sheet(isPresented: $showCostConfirm) {
            costConfirmSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var preflightBanner: some View {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        let blocked = !preflight.isReady
        GlassSurface(tier: .flat, corner: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: blocked ? "exclamationmark.triangle.fill" : "dollarsign.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(blocked ? LiquidGlass.warning : LiquidGlass.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(blocked ? "Can't build yet" : "Estimated cost · \(String(format: "$%.2f", estimatedCost))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(blocked
                         ? preflight.message
                         : "with \(model.displayName). Real cost depends on complexity — you can cap it.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    /// Pre-build confirmation sheet. Shows estimated cost, the model
    /// that'll be used, the current cap, and explains in plain English
    /// what happens next so the user knows what they're agreeing to.
    private var costConfirmSheet: some View {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        let cap = creds.costCapUSD
        return ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                        .padding(.top, 12)
                    VStack(spacing: 6) {
                        Text("This build will cost about")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                        Text(String(format: "$%.2f", estimatedCost))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("using \(model.displayName). Final cost depends on how complex your app turns out.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    GlassCard(title: "Your safety cap", icon: "shield.lefthalf.filled", tint: LiquidGlass.warning) {
                        if let cap {
                            Text("Build halts automatically at \(String(format: "$%.2f", cap)). You can lift the cap mid-build if you choose.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        } else {
                            Text("No cap set — the build will run until done. Set one in Settings → Build cost cap if you want a hard ceiling.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                        }
                    }
                    PrimaryButton(title: "Confirm and build", systemImage: "wand.and.stars", style: .filled) {
                        showCostConfirm = false
                        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        let final = AppDescription(
                            title: cleanTitle.isEmpty ? inferredTitle(from: cleanPrompt) : cleanTitle,
                            prompt: cleanPrompt, category: category, style: style
                        )
                        onSubmit(final)
                    }
                    Button("Cancel") {
                        Haptics.selection()
                        showCostConfirm = false
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func inferredTitle(from prompt: String) -> String {
        let words = prompt.split(separator: " ").prefix(4)
        return words.joined(separator: " ").capitalized
    }
}

private struct Chip: View {
    let label: String
    let icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(label).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? .white : LiquidGlass.primaryText.opacity(0.7))
            .background(
                selected
                ? AnyShapeStyle(LiquidGlass.auroraGradient)
                : AnyShapeStyle(Color.white.opacity(0.06))
            , in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.4 : 0.12)))
        }
        .buttonStyle(.plain)
    }
}
