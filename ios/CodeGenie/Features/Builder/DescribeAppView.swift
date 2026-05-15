import SwiftUI

struct DescribeAppView: View {
    var onSubmit: (AppDescription) -> Void

    @State private var title: String
    @State private var prompt: String
    @State private var category: AppDescription.Category
    @State private var style: AppDescription.Style
    @FocusState private var focused: Field?

    private enum Field { case title, prompt }

    private let suggestions: [String] = [
        "A tide times app for surfers with a clean Apple-style UI",
        "Daily habit tracker with streaks and a calm, minimal look",
        "AI-powered pantry that suggests recipes from photos of my fridge",
        "Read-it-later for podcasts with chapter summaries",
        "Liquid-glass weather widget collection, no ads"
    ]

    init(initial: AppDescription? = nil, onSubmit: @escaping (AppDescription) -> Void) {
        self.onSubmit = onSubmit
        _title = State(initialValue: initial?.title ?? "")
        _prompt = State(initialValue: initial?.prompt ?? "")
        _category = State(initialValue: initial?.category ?? .productivity)
        _style = State(initialValue: initial?.style ?? .liquidGlass)
    }

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
            PrimaryButton(title: "Build it", systemImage: "wand.and.stars", style: .filled) {
                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanPrompt.count >= 12 else { Haptics.error(); return }
                let final = AppDescription(
                    title: cleanTitle.isEmpty ? inferredTitle(from: cleanPrompt) : cleanTitle,
                    prompt: cleanPrompt, category: category, style: style
                )
                onSubmit(final)
            }
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 12 ? 0.5 : 1)
            Text("CodeGenie will generate the Xcode project, ask follow-ups, then run a build.")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .multilineTextAlignment(.center)
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
