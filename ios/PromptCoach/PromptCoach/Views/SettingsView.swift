import SwiftUI

/// Settings: the model reference library, the technique library, pack version,
/// and Legal. The two libraries are what make this a "how to prompt Claude
/// correctly" tool rather than a black box — users can browse the rules the
/// coach applies, not just receive their output.
struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            List {
                if AppTier.isLite {
                    Section {
                        UpsellCard(
                            title: "Unlock all 5 models",
                            detail: "Prompt Coach Lite coaches for Haiku 4.5 and Sonnet 5. The full app adds Opus 5, Opus 4.8, and Fable 5 — plus Sharpen, token cost, and adaptive controls.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    NavigationLink { ModelReferenceView() } label: {
                        row("Model reference", "cpu",
                            "How each Claude model wants to be prompted")
                    }
                    NavigationLink { TechniqueLibraryView() } label: {
                        row("Technique library", "books.vertical",
                            "\(app.pack.techniques.library.count) prompt-engineering techniques")
                    }
                } header: { header("Learn") }
                .listRowBackground(Color.clear)

                if app.learning.isSupported {
                    Section {
                        NavigationLink { LearningView() } label: {
                            row("Adapts to you", "dial.medium",
                                app.learning.adaptations.isEmpty
                                    ? "Watching how you work — nothing adjusted yet"
                                    : "\(app.learning.adaptations.count) adjustment\(app.learning.adaptations.count == 1 ? "" : "s") learned")
                        }
                    } header: { header("Adaptive controls") }
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink { LegalView(kind: .terms) } label: {
                        row("Terms of Use", "doc.text", nil)
                    }
                    NavigationLink { LegalView(kind: .privacy) } label: {
                        row("Privacy Policy", "hand.raised", nil)
                    }
                } header: { header("Legal") }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Coaching rules", value: app.pack.packVersion)
                        .font(Type.secondary)
                    LabeledContent("App version", value: Self.appVersion)
                        .font(Type.secondary)
                } header: { header("About") } footer: {
                    Text("Everything runs on your device. No account, no analytics, no tracking — nothing you type leaves this phone.")
                        .font(Type.caption)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
    }

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Type.label)
            .foregroundStyle(Glass.primaryText.opacity(0.55))
    }

    private func row(_ title: String, _ icon: String, _ subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Type.body)
                .foregroundStyle(Glass.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Type.bodyMed)
                    .foregroundStyle(Glass.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.55))
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Model reference

/// Browsable per-model prompting guidance, straight from the pack. This is the
/// "how to prompt each model" surface.
struct ModelReferenceView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(app.pack.availableModels) { model in
                        NavigationLink { ModelDetailView(model: model) } label: {
                            card(model)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(app.pack.lockedModels) { model in
                        Link(destination: AppTier.paidAppStoreURL) {
                            lockedCard(model)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Recommendation tie-breaker: \(app.pack.recommender.tieBreaker)")
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
        .navigationTitle("Model reference")
    }

    private func card(_ model: ModelProfile) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(Glass.tint(for: model.id)).frame(width: 10, height: 10)
                    Text(model.name)
                        .font(Type.cardTitle)
                        .foregroundStyle(Glass.primaryText)
                    Spacer()
                    Text(model.priceLabel)
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.55))
                }
                Text(model.oneLiner)
                    .font(Type.secondary)
                    .foregroundStyle(Glass.primaryText.opacity(0.8))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name). \(model.oneLiner). \(model.priceLabel)")
        .accessibilityHint("Opens full prompting guidance")
    }

    /// A model Lite doesn't coach for. Shows the name so the library is
    /// still an honest map of what Claude offers, but withholds the
    /// prompting guidance itself — that's the paid app's content.
    private func lockedCard(_ model: ModelProfile) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            HStack(spacing: 10) {
                Circle().fill(Glass.tint(for: model.id).opacity(0.4)).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(Type.cardTitle)
                        .foregroundStyle(Glass.primaryText.opacity(0.6))
                    Text("In the full app")
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.45))
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(Type.caption)
                    .foregroundStyle(Glass.primaryText.opacity(0.4))
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.name), locked in Prompt Coach Lite")
        .accessibilityHint("Opens Prompt Coach on the App Store")
    }
}

// MARK: - Upsell (Lite only)

/// The one place Lite asks for the sale. No IAP, no in-app paywall flow —
/// just a link to the paid app's own App Store listing. Apple, not this
/// app, handles the transaction.
struct UpsellCard: View {
    let title: String
    let detail: String

    var body: some View {
        Link(destination: AppTier.paidAppStoreURL) {
            GlassCard(corner: Glass.cornerMedium) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(Type.body)
                        .foregroundStyle(Glass.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Type.bodyMed)
                            .foregroundStyle(Glass.primaryText)
                        Text(detail)
                            .font(Type.caption)
                            .foregroundStyle(Glass.primaryText.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.35))
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint("Opens Prompt Coach on the App Store")
    }
}

/// Full prompting guidance for one model: how to prompt it, what to avoid,
/// and its hard API facts.
struct ModelDetailView: View {
    let model: ModelProfile

    var body: some View {
        ZStack {
            GlassBackground(tint: Glass.tint(for: model.id)).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.oneLiner)
                        .font(Type.heading)
                        .foregroundStyle(Glass.primaryText)

                    metaRow

                    if let rules = model.rewriteRules, !rules.isEmpty {
                        section("How to prompt it", icon: "wand.and.stars", items: rules)
                    }
                    if let dos = model.doList, !dos.isEmpty {
                        section("Do", icon: "checkmark.circle", items: dos, tint: Glass.success)
                    }
                    if let donts = model.dontList, !donts.isEmpty {
                        section("Don't", icon: "xmark.circle", items: donts, tint: Glass.warning)
                    }
                    if !model.strengths.isEmpty {
                        section("Strengths", icon: "star", items: model.strengths)
                    }
                    if let facts = model.apiFacts {
                        apiFactsCard(facts)
                    }
                    Text("Best fit: \(model.bestFit)")
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                }
                .padding(20)
            }
        }
        .navigationTitle(model.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            chip(model.priceLabel, "dollarsign.circle")
            if let effort = model.defaultEffort {
                chip("effort \(effort)", "gauge.medium")
            } else {
                chip("no effort param", "gauge.badge.minus")
            }
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(Type.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(Glass.tint(for: model.id))
            .background(Glass.tint(for: model.id).opacity(0.15), in: Capsule())
    }

    private func section(_ title: String, icon: String, items: [String],
                         tint: Color = Glass.accent) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(Type.label)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(tint.opacity(0.5))
                            .frame(width: 5, height: 5).padding(.top, 6)
                        Text(item)
                            .font(Type.secondary)
                            .foregroundStyle(Glass.primaryText.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func apiFactsCard(_ facts: APIFacts) -> some View {
        GlassCard(corner: Glass.cornerMedium) {
            VStack(alignment: .leading, spacing: 8) {
                Label("API facts", systemImage: "terminal")
                    .font(Type.label)
                    .foregroundStyle(Glass.primaryText.opacity(0.6))
                    .textCase(.uppercase)
                if let t = facts.thinkingWhenOmitted {
                    fact("Thinking when omitted", Self.thinkingLabel(t))
                }
                if let ceiling = facts.disableThinkingEffortCeiling {
                    fact("Can disable thinking", "only at effort \(ceiling) or below")
                }
                if let levels = facts.effortLevels {
                    fact("Effort levels", levels.isEmpty ? "none (parameter unsupported)" : levels.joined(separator: ", "))
                }
                if let ctx = facts.contextWindow {
                    fact("Context window", "\(ctx / 1000)K tokens")
                }
                if let out = facts.maxOutput {
                    fact("Max output", "\(out / 1000)K tokens")
                }
                if let cache = facts.promptCacheMinTokens {
                    fact("Prompt cache minimum", "\(cache) tokens")
                }
                if let rejects = facts.rejects, !rejects.isEmpty {
                    fact("Rejects", rejects.joined(separator: ", "))
                }
                if let notes = facts.notes {
                    Text(notes)
                        .font(Type.caption)
                        .foregroundStyle(Glass.primaryText.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private static func thinkingLabel(_ raw: String) -> String {
        switch raw {
        case "on_by_default": return "on (adaptive)"
        case "always_on":     return "always on — cannot be disabled"
        case "adaptive_on":   return "on (adaptive)"
        case "off":           return "off — set it explicitly"
        default:              return raw
        }
    }

    private func fact(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(Type.caption)
                .foregroundStyle(Glass.primaryText.opacity(0.6))
            Spacer(minLength: 12)
            Text(value)
                .font(Type.caption)
                .foregroundStyle(Glass.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Adaptive controls

/// Everything the app has learned from this user, in plain language, with an
/// off switch and a one-tap reset.
///
/// The transparency here is the feature. "Self-learning" in an app usually
/// means an opaque model you can neither inspect nor undo; this is a short
/// list of counted signals, each with the threshold it must clear, and the
/// guardrails it is never allowed to cross — all of it read from the pack so
/// the screen can't drift from what the engine actually does.
struct LearningView: View {
    @EnvironmentObject private var app: AppState

    private var spec: SelfLearning? { app.pack.selfLearning }

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { app.learning.isEnabled },
                        set: { app.setLearningEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Let the controls adapt")
                                .font(Type.bodyMed)
                                .foregroundStyle(Glass.primaryText)
                            Text("Off means the coach always uses the pack's defaults.")
                                .font(Type.caption)
                                .foregroundStyle(Glass.primaryText.opacity(0.55))
                        }
                    }
                } footer: {
                    if let note = spec?.note {
                        Text(note).font(Type.caption)
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    if app.learning.adaptations.isEmpty {
                        Text(app.learning.totalSessions == 0
                             ? "Nothing yet — coach a few prompts and this fills in."
                             : "\(app.learning.totalSessions) session\(app.learning.totalSessions == 1 ? "" : "s") so far, but no signal has cleared its threshold. The app would rather do nothing than guess.")
                            .font(Type.caption)
                            .foregroundStyle(Glass.primaryText.opacity(0.6))
                    } else {
                        ForEach(app.learning.adaptations) { a in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title)
                                    .font(Type.bodyMed)
                                    .foregroundStyle(Glass.primaryText)
                                Text(a.detail)
                                    .font(Type.caption)
                                    .foregroundStyle(Glass.primaryText.opacity(0.65))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: { Text("WHAT IT HAS ADJUSTED").font(Type.captionB) }
                .listRowBackground(Color.clear)

                if let signals = spec?.signals {
                    Section {
                        ForEach(signals) { s in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.learns)
                                    .font(Type.secondary)
                                    .foregroundStyle(Glass.primaryText.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(s.adjusts) Needs \(s.threshold) observation\(s.threshold == 1 ? "" : "s").")
                                    .font(Type.caption)
                                    .foregroundStyle(Glass.primaryText.opacity(0.55))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: { Text("WHAT IT WATCHES").font(Type.captionB) }
                    .listRowBackground(Color.clear)
                }

                if let guardrails = spec?.guardrails {
                    Section {
                        ForEach(Array(guardrails.enumerated()), id: \.offset) { _, g in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lock.shield")
                                    .font(Type.caption)
                                    .foregroundStyle(Glass.success)
                                    .padding(.top, 2)
                                Text(g)
                                    .font(Type.caption)
                                    .foregroundStyle(Glass.primaryText.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } header: { Text("WHAT IT MAY NEVER DO").font(Type.captionB) }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.tap()
                        app.resetLearning()
                    } label: {
                        Label("Reset what the app has learned", systemImage: "arrow.counterclockwise")
                            .font(Type.bodyMed)
                    }
                } footer: {
                    Text("Clears the counters and every adjustment above. What you chose outright — this switch, and any techniques you muted — stays; unmute those in the technique library. Your history is untouched.")
                        .font(Type.caption)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Adapts to you")
    }
}

// MARK: - Technique library

struct TechniqueLibraryView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""

    private var grouped: [(String, [Technique])] {
        let filtered = query.isEmpty
            ? app.pack.techniques.library
            : app.pack.techniques.library.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.when.localizedCaseInsensitiveContains(query)
            }
        return Dictionary(grouping: filtered, by: \.category)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            List {
                ForEach(grouped, id: \.0) { category, items in
                    Section {
                        ForEach(items) { t in
                            NavigationLink { LearnView(technique: t) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(t.name)
                                            .font(Type.bodyMed)
                                            .foregroundStyle(Glass.primaryText)
                                        if app.learning.isMuted(t.id) {
                                            Text("MUTED")
                                                .font(Type.captionB)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .foregroundStyle(Glass.warning)
                                                .background(Glass.warning.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    Text(t.when)
                                        .font(Type.caption)
                                        .foregroundStyle(Glass.primaryText.opacity(0.6))
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(category.uppercased())
                            .font(Type.captionB)
                    }
                }

                Section {
                    ForEach(Array(app.pack.techniques.retired.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Glass.warning).font(Type.caption)
                                .padding(.top, 2)
                            Text(item)
                                .font(Type.caption)
                                .foregroundStyle(Glass.primaryText.opacity(0.8))
                        }
                    }
                    .listRowBackground(Color.clear)
                } header: {
                    Text("RETIRED — THE COACH STRIPS THESE")
                        .font(Type.captionB)
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search techniques")
        }
        .navigationTitle("Techniques")
    }
}

// MARK: - Legal

struct LegalView: View {
    enum Kind { case terms, privacy
        var title: String { self == .terms ? "Terms of Use" : "Privacy Policy" }
        var file: String { self == .terms ? "terms" : "privacy" }
    }
    let kind: Kind

    var body: some View {
        ZStack {
            GlassBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(LegalText.body(for: kind))
                        .font(Type.secondary)
                        .foregroundStyle(Glass.primaryText.opacity(0.9))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Legal copy shipped in the binary so it renders with no network access —
/// App Review opens these, and a dead link is a rejection. Mirrors
/// docs/prompt-coach-terms.html and docs/prompt-coach-privacy.html.
enum LegalText {
    static func body(for kind: LegalView.Kind) -> String {
        if AppTier.isLite {
            return kind == .terms ? termsLite : privacyLite
        }
        return kind == .terms ? terms : privacy
    }

    // MARK: Lite — free tier, no purchase at all

    static let privacyLite = """
    Effective date: July 20, 2026

    THE SHORT VERSION
    Prompt Coach Lite is a free app with no accounts, no analytics, no \
    advertising, and no tracking. Everything you type stays on your iPhone.

    WHAT WE COLLECT
    Nothing on our own servers — we don't operate any. Your rambles, the \
    rewritten prompts, and your (limited) history live only on your device.

    THE FULL APP
    Prompt Coach Lite links to "Prompt Coach" on the App Store, a separate, \
    one-time-purchase app. Tapping that link opens Apple's App Store; we \
    receive nothing about whether you view or buy it. If you do, the paid \
    app's own Privacy Policy governs it, not this one.

    WHAT WE DON'T DO
    • No third-party analytics or advertising SDKs.
    • No selling or sharing of data, ever.
    • No user accounts, sign-ins, or profiles.
    • No collection of location, contacts, or advertising identifiers.

    CHILDREN
    The app is not directed at children under 13 and collects no personal \
    information from anyone.

    YOUR CONTROL
    Because all data is on your device, you control it completely: delete \
    individual history entries or all of them from within the app, or delete \
    the app to remove everything.

    CONTACT
    mvalasek77@gmail.com
    """

    static let termsLite = """
    Effective date: July 20, 2026

    1. ACCEPTANCE
    By using Prompt Coach Lite you agree to these Terms. Apple's Standard \
    End User License Agreement also applies; where it conflicts, the terms \
    that give you greater protection govern.

    2. WHAT THE APP DOES
    Prompt Coach Lite takes rough prompts you write and rewrites them into \
    cleaner prompts tailored to Claude Haiku 4.5 or Claude Sonnet 5, and \
    explains the prompt-engineering techniques it applied. It is a free, \
    reduced version of "Prompt Coach" — see that app's own listing for the \
    full model set and feature list. Prompt Coach Lite is not affiliated \
    with, endorsed by, or sponsored by Anthropic.

    3. LICENSE
    You may use the app on devices you own or control. You may not resell, \
    redistribute, or reverse-engineer the app.

    4. NO PURCHASE, NO IAP
    Prompt Coach Lite is entirely free. It contains no in-app purchases, no \
    subscriptions, and no paywall. Any link to "Prompt Coach" opens a \
    separate App Store listing and a separate transaction, if you choose to \
    make one — Apple handles that payment, not this app.

    5. NO WARRANTY ON GENERATED PROMPTS
    The app helps you improve prompts, but prompt quality and model output \
    are inherently variable. The app is provided "as is" without \
    warranties. We do not guarantee that a rewritten prompt will produce any \
    particular result. You are responsible for reviewing prompts before \
    relying on them.

    6. ACCEPTABLE USE
    You agree not to use the app to create prompts or content that are \
    unlawful or that violate Anthropic's usage policies. The app does not \
    assist in bypassing AI safety systems.

    7. TRADEMARK NOTICE
    Prompt Coach is not affiliated with, endorsed by, or sponsored by \
    Anthropic. Claude, Sonnet, Opus, Haiku, and Fable are trademarks of \
    Anthropic. Apple and the App Store are trademarks of Apple Inc.

    8. LIMITATION OF LIABILITY
    To the maximum extent permitted by law, our total liability for any \
    claim relating to the app will not exceed $10.

    9. CHANGES
    We may update these terms; the current version ships in the app with a \
    new effective date.

    10. CONTACT
    mvalasek77@gmail.com
    """

    // MARK: Paid

    static let privacy = """
    Effective date: July 20, 2026

    THE SHORT VERSION
    Prompt Coach is a paid, one-time-purchase app with no accounts, no \
    analytics, no advertising, and no tracking. Everything you type stays on \
    your iPhone.

    WHAT WE COLLECT
    Nothing on our own servers — we don't operate any. Your rambles, the \
    rewritten prompts, and your history live only on your device.

    PAYMENTS
    Prompt Coach is a one-time purchase on the App Store with no in-app \
    purchases and no subscriptions. Apple processes your payment; we never \
    receive your name, email, or payment details.

    WHAT WE DON'T DO
    • No third-party analytics or advertising SDKs.
    • No selling or sharing of data, ever.
    • No user accounts, sign-ins, or profiles.
    • No collection of location, contacts, or advertising identifiers.

    CHILDREN
    The app is not directed at children under 13 and collects no personal \
    information from anyone.

    YOUR CONTROL
    Because all data is on your device, you control it completely: delete \
    individual history entries or all of them from within the app, or delete \
    the app to remove everything.

    CONTACT
    mvalasek77@gmail.com
    """

    static let terms = """
    Effective date: July 20, 2026

    1. ACCEPTANCE
    By using Prompt Coach you agree to these Terms. Apple's Standard End User \
    License Agreement also applies; where it conflicts, the terms that give \
    you greater protection govern.

    2. WHAT THE APP DOES
    Prompt Coach takes rough prompts you write and rewrites them into cleaner \
    prompts tailored to a Claude model you choose, and explains the \
    prompt-engineering techniques it applied. Prompt Coach is not affiliated \
    with, endorsed by, or sponsored by Anthropic.

    3. LICENSE
    Your one-time purchase grants you a personal, non-exclusive, \
    non-transferable license to use the app on devices you own or control. You \
    may not resell, redistribute, or reverse-engineer the app.

    4. ONE-TIME PURCHASE
    The app is sold for a single up-front price. There are no in-app \
    purchases or subscriptions. Apple handles all payment and refunds under \
    its own policies.

    5. NO WARRANTY ON GENERATED PROMPTS
    The app helps you improve prompts, but prompt quality and model output are \
    inherently variable. The app is provided "as is" without warranties. We do \
    not guarantee that a rewritten prompt will produce any particular result. \
    You are responsible for reviewing prompts before relying on them.

    6. ACCEPTABLE USE
    You agree not to use the app to create prompts or content that are \
    unlawful or that violate Anthropic's usage policies. The app does not \
    assist in bypassing AI safety systems.

    7. TRADEMARK NOTICE
    Prompt Coach is not affiliated with, endorsed by, or sponsored by \
    Anthropic. Claude, Sonnet, Opus, Haiku, and Fable are trademarks of \
    Anthropic. Apple and the App Store are trademarks of Apple Inc.

    8. LIMITATION OF LIABILITY
    To the maximum extent permitted by law, our total liability for any claim \
    relating to the app will not exceed the amount you paid for it.

    9. CHANGES
    We may update these terms; the current version ships in the app with a \
    new effective date.

    10. CONTACT
    mvalasek77@gmail.com
    """
}
