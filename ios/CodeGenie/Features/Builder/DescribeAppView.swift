import SwiftUI

struct DescribeAppView: View {
    var onSubmit: (AppDescription) -> Void

    @StateObject private var creds = Credentials.shared
    @StateObject private var billing = BillingStore.shared
    @State private var title: String
    @State private var prompt: String
    @State private var category: AppDescription.Category
    @State private var style: AppDescription.Style
    @State private var showCostConfirm: Bool = false
    @FocusState private var focused: Field?

    private enum Field { case title, prompt }

    private let suggestions: [String] = [
        "Warm habit tracker with a candle-like streak, lock-screen widget, kind recovery copy, and a soft haptic when the flame grows",
        "Pastel mood journal with one nightly reflection, private weekly patterns, breathing haptics, offline storage, and no streak pressure",
        "Tide times app for surfers with Apple Watch glance, next-low-tide haptic, calm ocean UI, and offline beach favorites",
        "Podcast note taker where a Watch tap marks the moment and a daily digest turns highlights into one-line takeaways",
        "Camera helper that makes cinematic focus pulls feel simple with haptics, presets, and accessible large controls"
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
                    experienceDNAReadout
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
            Text("Shape the experience").font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidGlass.primaryText)
            Text("Brief the feeling, ritual, native Apple moments, accessibility, and trust story before CodeGenie writes code.")
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
                            Text("Describe the ritual, feeling, native hooks, and trust details...")
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

    private var experienceDNAReadout: some View {
        let cues = experienceCues
        let matched = cues.filter(\.matched).count
        return GlassSurface(tier: .raised, corner: 18) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(LiquidGlass.accentSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(LiquidGlass.accentSecondary.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Experience DNA")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                        Text("\(matched) of \(cues.count) signals detected")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.66))
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(experienceScore)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Text("/10")
                            .font(.system(size: 8, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(experienceTint)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(experienceTint.opacity(0.14)))
                    .overlay(Circle().strokeBorder(experienceTint.opacity(0.34)))
                    .accessibilityHidden(true)
                }
                Text(experienceGradeLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(cues) { cue in
                        ExperienceCueRow(cue: cue)
                    }
                }
            }
            .padding(15)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Experience DNA score \(experienceScore) out of 10")
        .accessibilityValue(cues.map { "\($0.title): \($0.matched ? "ready" : "missing")" }.joined(separator: ", "))
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
                guard canSubmit else { Haptics.error(); return }
                showCostConfirm = true
                Haptics.selection()
            }
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            Text(buildAccess.footer)
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

    private var estimatedCost: Double {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        return model.estimatedBuildCostUSD()
    }

    private var costConfirmSheet: some View {
        let model = ModelCatalogue.model(id: creds.preferredModelID) ?? ModelCatalogue.all[0]
        return ZStack {
            LiquidGlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LiquidGlass.success)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    VStack(spacing: 6) {
                        Text(confirmTitle)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.75))
                        Text(confirmHeadline)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText)
                            .multilineTextAlignment(.center)
                        Text(confirmDetail(modelName: model.displayName))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    GlassCard(title: "Safety cap", icon: "shield.lefthalf.filled", tint: LiquidGlass.warning) {
                        Text(costCapCopy)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(LiquidGlass.primaryText.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PrimaryButton(title: "Confirm and build", systemImage: "wand.and.stars", style: .filled) {
                        submitConfirmedBuild()
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

    private var confirmTitle: String {
        switch creds.authMode {
        case .byok: "This build will cost about"
        case .subscription: "This build will use"
        case .codegenie: "This build will use"
        }
    }

    private var confirmHeadline: String {
        switch creds.authMode {
        case .byok:
            String(format: "$%.2f", estimatedCost)
        case .subscription:
            "Your paired Mac"
        case .codegenie:
            billing.activePlan == .free ? "1 hosted credit" : "\(billing.activePlan.label) hosting"
        }
    }

    private func confirmDetail(modelName: String) -> String {
        switch creds.authMode {
        case .byok:
            return "Estimated with \(modelName). Final provider cost depends on complexity and token use."
        case .subscription:
            return "CodeGenie routes through your existing Claude or ChatGPT session on the Mac companion."
        case .codegenie:
            return billing.activePlan == .free
                ? "\(billing.hostedStatusText). CodeGenie stops if the backend reports a launch blocker."
                : "\(billing.hostedStatusText). CodeGenie still applies backend safety gates."
        }
    }

    private var costCapCopy: String {
        if let cap = creds.costCapUSD {
            return String(format: "Builds halt automatically at $%.2f. You can lift the cap mid-build if the backend pauses before completion.", cap)
        }
        return "No cap is set. Turn on Build cost cap in Settings if you want a hard ceiling before starting."
    }

    private func submitConfirmedBuild() {
        showCostConfirm = false
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = AppDescription(
            title: cleanTitle.isEmpty ? inferredTitle(from: cleanPrompt) : cleanTitle,
            prompt: cleanPrompt,
            category: category,
            style: style
        )
        Haptics.experienceStart()
        onSubmit(final)
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

    private var experienceCues: [ExperienceCue] {
        [
            .init(
                title: "Emotional payoff",
                detail: "Name the feeling users get first.",
                icon: "heart.fill",
                tint: Color(red: 1.00, green: 0.47, blue: 0.66),
                matched: briefContains(["calm", "warm", "confidence", "delight", "joy", "kind", "relief", "focus", "reflection", "authentic", "play"])
            ),
            .init(
                title: "Return ritual",
                detail: "Give people a reason to come back.",
                icon: "repeat.circle.fill",
                tint: LiquidGlass.warning,
                matched: briefContains(["daily", "nightly", "weekly", "streak", "ritual", "check-in", "reminder", "digest", "routine", "journal"])
            ),
            .init(
                title: "Native craft",
                detail: "Use iPhone, Watch, camera, widgets, or haptics.",
                icon: "iphone.gen3.radiowaves.left.and.right",
                tint: LiquidGlass.accent,
                matched: briefContains(["watch", "widget", "haptic", "camera", "shortcut", "lock-screen", "lock screen", "live activity", "siri", "offline"])
            ),
            .init(
                title: "Accessible feedback",
                detail: "Plan VoiceOver, contrast, motion, and tap feel.",
                icon: "accessibility.fill",
                tint: Color(red: 0.22, green: 0.78, blue: 0.65),
                matched: briefContains(["accessibility", "voiceover", "large type", "contrast", "reduce motion", "haptic", "captions", "screen reader"])
            ),
            .init(
                title: "Trust story",
                detail: "Say how privacy and failure are handled.",
                icon: "lock.shield.fill",
                tint: LiquidGlass.success,
                matched: briefContains(["private", "privacy", "offline", "secure", "no ads", "local", "encrypted", "forgiveness", "no feeds", "no streak pressure"])
            )
        ]
    }

    private var experienceScore: Int {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleanPrompt.count >= 12 ? 5 : 3
        return min(10, base + experienceCues.filter(\.matched).count)
    }

    private var experienceGradeLabel: String {
        switch experienceScore {
        case 9...10:
            return "This is starting to feel like a product experience, not a feature list."
        case 7...8:
            return "Strong shape. Add one more native, accessible, or emotional signal."
        case 5...6:
            return "The utility is visible. Sharpen the moment people will remember."
        default:
            return "Start with the feeling, then name the daily loop and device magic."
        }
    }

    private var experienceTint: Color {
        switch experienceScore {
        case 9...10: return LiquidGlass.success
        case 7...8: return LiquidGlass.warning
        default: return LiquidGlass.accentSecondary
        }
    }

    private func briefContains(_ terms: [String]) -> Bool {
        let haystack = "\(title) \(prompt)".lowercased()
        return terms.contains { haystack.contains($0) }
    }
}

private struct BuildAccess {
    let canBuild: Bool
    let title: String
    let detail: String
    let footer: String
    let tint: Color
}

private struct ExperienceCue: Identifiable {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let matched: Bool
    var id: String { title }
}

private struct ExperienceCueRow: View {
    let cue: ExperienceCue

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: cue.matched ? "checkmark.circle.fill" : cue.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(cue.matched ? LiquidGlass.success : cue.tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill((cue.matched ? LiquidGlass.success : cue.tint).opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(cue.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText)
                Text(cue.detail)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(LiquidGlass.primaryText.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cue.title), \(cue.matched ? "ready" : "missing")")
        .accessibilityHint(cue.detail)
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
