import Foundation

/// The AI guidance layer for App Store Connect submission.
///
/// **Why this exists.** A first-time submitter does not know that
/// Apple silently truncates a 31-character subtitle, that keywords are
/// a single 100-char comma-joined string (not a list), or that a
/// missing support URL is a hard rejection. Before this, CodeGenie
/// drafted metadata and hoped. Now the coach validates every field
/// against Apple's real limits, tells the user exactly what is wrong
/// in plain English, and refuses to advance a step that would produce
/// a rejection.
///
/// The coach is deterministic — no LLM call. Apple's limits are fixed
/// and public, so a rules engine gives a faster, cheaper, and more
/// reliable answer than a model would, and it works offline.
enum ASCCoach {

    // MARK: - Apple's real field limits
    //
    // Sourced from App Store Connect Help → "Reference → App
    // information". These are hard server-side limits: exceed them and
    // the form refuses to save (or silently truncates, which is worse
    // because the user does not notice until review).

    enum Limit {
        static let name = 30
        static let subtitle = 30
        static let promotionalText = 170
        static let description = 4000
        /// Keywords is ONE field: a comma-separated string capped at
        /// 100 characters total, including the commas. Users routinely
        /// assume it's 100 chars per keyword.
        static let keywordsTotal = 100
        static let descriptionMinimum = 10
    }

    // MARK: - Issues

    struct Issue: Identifiable, Hashable {
        let id = UUID()
        let field: Field
        let severity: Severity
        let message: String
        /// What the user should actually do about it.
        let fix: String

        enum Severity: Int, Comparable {
            case blocking = 2
            case warning = 1

            static func < (a: Severity, b: Severity) -> Bool {
                a.rawValue < b.rawValue
            }
        }

        enum Field: String, Hashable {
            case name, subtitle, keywords, description
            case promotionalText, supportURL, marketingURL
            case category, ageRating, price
        }
    }

    // MARK: - Validation

    /// Validate a metadata draft against Apple's rules.
    /// Returns issues sorted blocking-first.
    static func validate(_ m: AppStoreMetadata) -> [Issue] {
        var issues: [Issue] = []

        // --- Name (required, ≤30) ---
        let name = m.name.trimmed
        if name.isEmpty {
            issues.append(.init(
                field: .name, severity: .blocking,
                message: "App name is empty.",
                fix: "Every app needs a name. This is what shows under the icon on the Home Screen."
            ))
        } else if name.count > Limit.name {
            issues.append(.init(
                field: .name, severity: .blocking,
                message: "App name is \(name.count) characters — Apple's limit is \(Limit.name).",
                fix: "Trim \(name.count - Limit.name) character\(name.count - Limit.name == 1 ? "" : "s"). Short names also look better on the Home Screen."
            ))
        }

        // --- Subtitle (optional but strongly recommended, ≤30) ---
        let subtitle = m.subtitle.trimmed
        if subtitle.isEmpty {
            issues.append(.init(
                field: .subtitle, severity: .warning,
                message: "No subtitle.",
                fix: "The subtitle sits under your name in search results. Apps with one get noticeably more taps."
            ))
        } else if subtitle.count > Limit.subtitle {
            issues.append(.init(
                field: .subtitle, severity: .blocking,
                message: "Subtitle is \(subtitle.count) characters — Apple's limit is \(Limit.subtitle).",
                fix: "Trim \(subtitle.count - Limit.subtitle) character\(subtitle.count - Limit.subtitle == 1 ? "" : "s")."
            ))
        }

        // --- Keywords (ONE comma-joined field, ≤100 total) ---
        let keywordString = m.keywords
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        if keywordString.isEmpty {
            issues.append(.init(
                field: .keywords, severity: .warning,
                message: "No keywords.",
                fix: "Keywords are how people find you in search. Add a few terms someone would actually type."
            ))
        } else if keywordString.count > Limit.keywordsTotal {
            issues.append(.init(
                field: .keywords, severity: .blocking,
                message: "Keywords total \(keywordString.count) characters — Apple's limit is \(Limit.keywordsTotal) for the whole comma-separated list.",
                fix: "Remove \(keywordString.count - Limit.keywordsTotal) character\(keywordString.count - Limit.keywordsTotal == 1 ? "" : "s"). Drop the weakest terms — this is one field, not one limit per word."
            ))
        }

        // --- Description (required, 10…4000) ---
        let description = m.description.trimmed
        if description.count < Limit.descriptionMinimum {
            issues.append(.init(
                field: .description, severity: .blocking,
                message: description.isEmpty ? "Description is empty." : "Description is too short.",
                fix: "Write at least a couple of sentences on what the app does and who it's for. Reviewers read this."
            ))
        } else if description.count > Limit.description {
            issues.append(.init(
                field: .description, severity: .blocking,
                message: "Description is \(description.count) characters — Apple's limit is \(Limit.description).",
                fix: "Trim \(description.count - Limit.description) characters."
            ))
        }

        // --- Promotional text (optional, ≤170) ---
        let promo = m.promotionalText.trimmed
        if promo.count > Limit.promotionalText {
            issues.append(.init(
                field: .promotionalText, severity: .blocking,
                message: "Promotional text is \(promo.count) characters — Apple's limit is \(Limit.promotionalText).",
                fix: "Trim \(promo.count - Limit.promotionalText) characters."
            ))
        }

        // --- Support URL (REQUIRED by Apple) ---
        let support = m.supportURL.trimmed
        if support.isEmpty {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL is missing — Apple requires one.",
                fix: "A page where users can reach you. A GitHub repo README or a simple contact page is enough."
            ))
        } else if !isPlausibleURL(support) {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL doesn't look like a valid link.",
                fix: "It must start with https:// and point at a real, reachable page."
            ))
        } else if isPlaceholderURL(support) {
            issues.append(.init(
                field: .supportURL, severity: .blocking,
                message: "Support URL is still the placeholder.",
                fix: "Replace example.com with a page you actually control — Apple checks that this loads."
            ))
        }

        // --- Marketing URL (optional) ---
        let marketing = m.marketingURL.trimmed
        if !marketing.isEmpty {
            if !isPlausibleURL(marketing) {
                issues.append(.init(
                    field: .marketingURL, severity: .warning,
                    message: "Marketing URL doesn't look like a valid link.",
                    fix: "Either fix it or clear it — this field is optional."
                ))
            } else if isPlaceholderURL(marketing) {
                issues.append(.init(
                    field: .marketingURL, severity: .warning,
                    message: "Marketing URL is still the placeholder.",
                    fix: "Clear it or point it at your real site. It's optional, so empty is better than fake."
                ))
            }
        }

        // --- Category ---
        if m.primaryCategory.trimmed.isEmpty {
            issues.append(.init(
                field: .category, severity: .blocking,
                message: "No primary category.",
                fix: "Pick the category people would browse to find an app like yours."
            ))
        }

        return issues.sorted { a, b in
            if a.severity != b.severity { return a.severity > b.severity }
            return a.field.rawValue < b.field.rawValue
        }
    }

    static func blockingIssues(_ m: AppStoreMetadata) -> [Issue] {
        validate(m).filter { $0.severity == .blocking }
    }

    static func isMetadataReady(_ m: AppStoreMetadata) -> Bool {
        blockingIssues(m).isEmpty
    }

    // MARK: - Character budget helpers (for live UI counters)

    static func remaining(_ text: String, limit: Int) -> Int {
        limit - text.trimmed.count
    }

    static func keywordString(_ keywords: [String]) -> String {
        keywords.map { $0.trimmed }.filter { !$0.isEmpty }.joined(separator: ",")
    }

    // MARK: - Step guidance

    /// Plain-English guidance for a step, adapted to live state.
    /// This is what the coach banner shows: not "step 5 of 10" but
    /// "here is what to do right now, and why".
    static func guidance(
        for step: ASCStep,
        metadata: AppStoreMetadata,
        macPaired: Bool,
        buildUploaded: Bool
    ) -> String {
        switch step.number {
        case 1:
            return macPaired
                ? "Tap below and CodeGenie will open App Store Connect in your Mac's Safari. Sign in there — we never see your password or 2FA codes."
                : "Open appstoreconnect.apple.com and sign in. Pair a Mac in Settings and CodeGenie can open it for you next time."
        case 2:
            return "Click + → New App. Use the exact bundle ID below — if it doesn't match your Xcode target, the upload in step 8 will be rejected."
        case 3:
            return "Your icon must be exactly 1024×1024, PNG, no transparency, no rounded corners. Apple rejects anything else outright."
        case 4:
            return "You need screenshots for at least one iPhone size. Review each one before uploading — Apple rejects screenshots showing placeholder or lorem-ipsum content."
        case 5:
            let blocking = blockingIssues(metadata)
            if blocking.isEmpty {
                return "Your listing passes every length check. Copy each field below into App Store Connect, or let CodeGenie fill them on your Mac."
            }
            return "Fix \(blocking.count) problem\(blocking.count == 1 ? "" : "s") in the listing before you paste anything into App Store Connect — Apple will reject or silently truncate these."
        case 6:
            return "Answer honestly. If your app stores anything on-device only and sends nothing anywhere, the answer to 'do you collect data' is No — but if you added analytics, it's Yes."
        case 7:
            return "Free with all territories is the safe default. You can change price later without a new review."
        case 8:
            return buildUploaded
                ? "Build uploaded. Apple is processing it — move to the next step."
                : "This needs a signed App Store build. CodeGenie runs Apple's validate-then-upload flow and streams every line so you see failures immediately."
        case 9:
            return "Processing usually takes 5–30 minutes. You can close CodeGenie — your progress is saved and we'll be here when you come back."
        case 10:
            return "Final step, and it has to be you: Apple requires the account holder to press Submit. Everything below is a checklist of what that screen will ask."
        default:
            return step.body
        }
    }

    /// The single most useful next action across the whole flow.
    /// Drives the coach banner at the top of the guide.
    static func nextAction(
        completed: Set<Int>,
        metadata: AppStoreMetadata,
        macPaired: Bool
    ) -> NextAction {
        let blocking = blockingIssues(metadata)

        // Listing problems outrank step order — there is no point
        // walking someone to step 8 with a name that won't save.
        if !blocking.isEmpty, completed.contains(5) == false {
            return NextAction(
                headline: "Fix your listing first",
                detail: blocking.first!.message + " " + blocking.first!.fix,
                stepNumber: 5,
                isBlocking: true
            )
        }

        let nextIncomplete = (1...10).first { !completed.contains($0) }
        guard let next = nextIncomplete else {
            return NextAction(
                headline: "Everything's done",
                detail: "You've completed all ten steps. Once Apple finishes review you'll get an email.",
                stepNumber: nil,
                isBlocking: false
            )
        }

        let step = ASCStep.all.first { $0.number == next }
        return NextAction(
            headline: "Next: \(step?.title ?? "Step \(next)")",
            detail: step.map {
                guidance(for: $0, metadata: metadata, macPaired: macPaired, buildUploaded: completed.contains(8))
            } ?? "",
            stepNumber: next,
            isBlocking: false
        )
    }

    struct NextAction {
        let headline: String
        let detail: String
        let stepNumber: Int?
        let isBlocking: Bool
    }

    // MARK: - URL heuristics

    private static func isPlausibleURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              host.contains(".")
        else { return false }
        return true
    }

    private static func isPlaceholderURL(_ s: String) -> Bool {
        let lowered = s.lowercased()
        return ["example.com", "example.org", "yoursite", "your-site",
                "changeme", "placeholder", "todo"].contains { lowered.contains($0) }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
