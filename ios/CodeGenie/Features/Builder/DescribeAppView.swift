import SwiftUI

struct DescribeAppView: View {
    var onSubmit: (AppDescription) -> Void

    @StateObject private var creds = Credentials.shared
    @StateObject private var billing = BillingStore.shared
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
                    preflightBlock
                    submitRow
                    Color.clear.frame(height: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .task { await billing.refresh() }
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
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmit = cleanPrompt.count >= 12 && buildAccess.canBuild
        return VStack(spacing: 10) {
            PrimaryButton(title: "Build it", systemImage: "wand.and.stars", style: .filled) {
                let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard canSubmit else { Haptics.error(); return }
                let final = AppDescription(
                    title: cleanTitle.isEmpty ? inferredTitle(from: cleanPrompt) : cleanTitle,
                    prompt: cleanPrompt, category: category, style: style
                )
                onSubmit(final)
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            Text(buildAccess.footer)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText.opacity(0.55))
                .multilineTextAlignment(.center)
        }
    }

    private var preflightBlock: some View {
        let access = buildAccess
        return GlassSurface(tier: .flat, corner: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: access.canBuild ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(access.tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(access.tint.opacity(0.18)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(access.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText)
                    Text(access.detail)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiquidGlass.primaryText.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    private var buildAccess: BuildAccess {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        switch creds.authMode {
        case .byok:
            guard creds.hasKey(for: model.provider) else {
                return BuildAccess(
                    canBuild: false,
                    title: "Add a \(model.provider.displayName) API key",
                    detail: "\(model.displayName) is selected. Add that provider key in Settings, or choose a model for a provider you already connected.",
                    footer: "Build is locked until the selected model has a key.",
                    tint: LiquidGlass.warning
                )
            }
            return BuildAccess(
                canBuild: true,
                title: "API key ready",
                detail: "\(model.displayName) will run on your selected build runner. The key is sent for this build only and not stored by the runner.",
                footer: "CodeGenie will generate the Xcode project, run tests, then report cost and status.",
                tint: LiquidGlass.success
            )
        case .subscription:
            guard !creds.backendToken.isEmpty else {
                return BuildAccess(
                    canBuild: false,
                    title: "Pair your Mac first",
                    detail: "Subscription routing needs the Mac companion so CodeGenie can use your signed-in Claude or ChatGPT session.",
                    footer: "Open Settings -> Pair your Mac to unlock subscription builds.",
                    tint: LiquidGlass.warning
                )
            }
            return BuildAccess(
                canBuild: true,
                title: "Mac companion paired",
                detail: "This build will route through your paired Mac session.",
                footer: "CodeGenie will start the paired runner and stream progress back here.",
                tint: LiquidGlass.success
            )
        case .codegenie:
            guard billing.canStartHostedBuild else {
                return BuildAccess(
                    canBuild: false,
                    title: "Hosted build limit reached",
                    detail: "Your free hosted builds are used for this month. Upgrade to Pro or Studio in Settings to continue.",
                    footer: "Upgrade or switch to API key mode to build now.",
                    tint: LiquidGlass.warning
                )
            }
            return BuildAccess(
                canBuild: true,
                title: "Hosted credits ready",
                detail: billing.hostedStatusText,
                footer: "CodeGenie will use hosted credits and stop if the backend reports a launch blocker.",
                tint: LiquidGlass.success
            )
        }
    }

    private func inferredTitle(from prompt: String) -> String {
        let words = prompt.split(separator: " ").prefix(4)
        return words.joined(separator: " ").capitalized
    }
}

private struct BuildAccess {
    let canBuild: Bool
    let title: String
    let detail: String
    let footer: String
    let tint: Color
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
