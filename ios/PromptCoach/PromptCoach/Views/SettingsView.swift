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
                    ForEach(app.pack.models) { model in
                        NavigationLink { ModelDetailView(model: model) } label: {
                            card(model)
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
                                    Text(t.name)
                                        .font(Type.bodyMed)
                                        .foregroundStyle(Glass.primaryText)
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
        kind == .terms ? terms : privacy
    }

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
    prompt-engineering techniques it applied.

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

    7. LIMITATION OF LIABILITY
    To the maximum extent permitted by law, our total liability for any claim \
    relating to the app will not exceed the amount you paid for it.

    8. CHANGES
    We may update these terms; the current version ships in the app with a \
    new effective date.

    9. CONTACT
    mvalasek77@gmail.com
    """
}
