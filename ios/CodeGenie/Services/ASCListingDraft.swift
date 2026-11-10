import Foundation

// A first draft of the store page, built from what the user typed when
// they described the app. Lives apart from the views so the limits it
// promises to respect can be checked without a device.

extension AppStoreMetadata {
    static let empty = AppStoreMetadata(
        name: "", subtitle: "", primaryCategory: "", keywords: [],
        description: "", promotionalText: "", supportURL: "",
        marketingURL: "", ageRating: "4+", price: "Free"
    )

    static func draft(for app: AppDescription, year: Int? = nil) -> AppStoreMetadata {
        let featureWords = app.features
            .flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
            .map { String($0).lowercased() }
        let promptWords = app.prompt
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0).lowercased() }
            .filter { $0.count > 3 }

        // Keywords is a single 100-char field, so build up to the cap
        // instead of taking a fixed count and blowing the limit.
        var keywords: [String] = []
        var budget = ASCCoach.Limit.keywordsTotal
        for word in (featureWords + promptWords + [app.category.rawValue])
            .map({ $0.replacingOccurrences(of: " ", with: "") })
            .filter({ !$0.isEmpty })
            .uniqued() {
            let cost = word.count + (keywords.isEmpty ? 0 : 1)
            guard budget - cost >= 0 else { continue }
            keywords.append(word)
            budget -= cost
        }

        var draft = AppStoreMetadata(
            name: String(app.title.prefix(ASCCoach.Limit.name)),
            subtitle: String(app.subtitleDraft.prefix(ASCCoach.Limit.subtitle)),
            primaryCategory: app.category.label,
            keywords: keywords.isEmpty ? [app.category.rawValue] : keywords,
            description: String(app.descriptionDraft.prefix(ASCCoach.Limit.description)),
            promotionalText: "",
            // Deliberately empty rather than example.com — a placeholder
            // URL passes a naive check and then fails Apple's review.
            // The coach flags empty as blocking so the user supplies a
            // real one.
            supportURL: "",
            marketingURL: "",
            ageRating: "4+",
            price: "Free"
        )
        // Same reasoning for the policy URL and the copyright owner:
        // only the user knows them, so they start empty and flagged.
        draft.privacyPolicyURL = ""
        let currentYear = year ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        draft.copyright = "\(currentYear) "
        draft.requiresLogin = false
        draft.reviewNotes = ASCCoach.reviewNotesDraft(
            appName: app.title,
            summary: app.prompt,
            features: app.features,
            requiresLogin: false
        )
        return draft
    }
}

private extension AppDescription {
    var subtitleDraft: String {
        if let first = features.first, !first.isEmpty {
            return String(first.prefix(30))
        }
        return switch category {
        case .utility: "Fast, focused everyday help"
        case .productivity: "Plan, build, and finish faster"
        case .lifestyle: "A calmer daily ritual"
        case .finance: "Money clarity at a glance"
        case .social: "Share what matters now"
        case .health: "Healthier habits, gently"
        case .education: "Learn with less friction"
        case .games: "Playful moments, polished"
        case .photo: "Create standout visuals"
        }
    }

    var descriptionDraft: String {
        let base = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "\(title)\n\n\(base)"
        if !features.isEmpty {
            out += "\n\nWhat's inside:\n"
            out += features.map { "• \($0)" }.joined(separator: "\n")
        }
        return out
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
