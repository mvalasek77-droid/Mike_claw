import Foundation

/// The "AI Editor" that examines every submission and scores how close it is
/// to commercial quality. Work must reach ``AIReviewResult/threshold`` (85)
/// to be accepted onto the marketplace.
///
/// Scoring is a transparent heuristic over signals the creator supplies in the
/// publishing flow (synopsis depth, disclosure completeness, packaging, pricing
/// fit) blended with a deterministic per-work jitter so two different titles
/// don't score identically. It is intentionally explainable: every criterion
/// reports its own number and an actionable note.
enum AIEditor {

    static func review(_ draft: DraftWork) -> AIReviewResult {
        let signals = Signals(draft)
        let names = criteriaNames(for: draft.type)

        var criteria: [CriterionScore] = []
        for (index, name) in names.enumerated() {
            let base = signals.baseScore(forCriterionAt: index, total: names.count)
            let jitter = seededJitter(draft.title + draft.synopsis + name, spread: 7)
            let score = clamp(base + jitter)
            criteria.append(CriterionScore(name: name, score: score, note: note(for: name, score: score)))
        }

        let overall = clamp(Int((Double(criteria.map(\.score).reduce(0, +)) / Double(max(criteria.count, 1))).rounded()))

        let strengths = criteria.filter { $0.score >= 88 }.map { "\($0.name) reads commercial-grade (\($0.score))." }
        let improvements = criteria.filter { $0.score < AIReviewResult.threshold }
            .map { "\($0.name): \($0.note)" }

        let summary: String
        if overall >= AIReviewResult.threshold {
            summary = "Accepted. This \(draft.type.title.lowercased()) clears the 85% commercial bar at \(overall)% — ready to publish to the marketplace."
        } else {
            let gap = AIReviewResult.threshold - overall
            summary = "Not yet. Scored \(overall)% — \(gap) point\(gap == 1 ? "" : "s") under the 85% commercial bar. Address the notes below and resubmit."
        }

        return AIReviewResult(
            overall: overall,
            criteria: criteria,
            strengths: strengths.isEmpty ? ["Solid disclosure and clean packaging."] : strengths,
            improvements: improvements,
            summary: summary
        )
    }

    // MARK: - Criteria per media type

    private static func criteriaNames(for type: MediaType) -> [String] {
        switch type {
        case .novel: return ["Narrative Craft", "Originality", "Prose & Polish", "Pacing & Hook", "Market Fit"]
        case .music: return ["Production Quality", "Composition", "Originality", "Mix & Master", "Replay Value"]
        case .movie: return ["Cinematography", "Story & Structure", "Editing & Pacing", "Sound Design", "Market Fit"]
        }
    }

    // MARK: - Signal extraction

    private struct Signals {
        let depth: Double          // synopsis richness 0…1
        let titlecraft: Double     // title quality 0…1
        let disclosure: Double     // AI-tool disclosure completeness 0…1
        let packaging: Double      // upload + length present 0…1
        let marketFit: Double      // genre + pricing sanity 0…1

        init(_ d: DraftWork) {
            let words = d.synopsis.trimmed.split { $0 == " " || $0 == "\n" }.count
            depth = mapRange(Double(words), inMin: 12, inMax: 110, outMin: 0.30, outMax: 1.0)

            let titleLen = d.title.trimmed.count
            let allCaps = !d.title.isEmpty && d.title == d.title.uppercased()
            var t = mapRange(Double(titleLen), inMin: 2, inMax: 42, outMin: 0.45, outMax: 1.0)
            if allCaps { t -= 0.2 }
            titlecraft = max(0, min(1, t))

            disclosure = min(1.0, 0.55 + Double(d.aiTools.count) * 0.18)

            var p = d.fileName == nil ? 0.2 : 0.85
            if d.length > 0 { p += 0.15 }
            packaging = min(1.0, p)

            let hasGenre = !d.genre.trimmed.isEmpty
            let priceOK = d.price >= 0.99 && d.price <= 19.99
            marketFit = (hasGenre ? 0.6 : 0.3) + (priceOK ? 0.4 : 0.1)
        }

        /// Maps the five generic signals onto a criterion slot, weighting the
        /// signals most relevant to that position.
        func baseScore(forCriterionAt index: Int, total: Int) -> Int {
            let weights: [Double]
            switch index {
            case 0: weights = [0.45, 0.10, 0.15, 0.15, 0.15] // craft-led
            case 1: weights = [0.35, 0.30, 0.10, 0.10, 0.15] // originality-led
            case 2: weights = [0.30, 0.15, 0.35, 0.10, 0.10] // polish-led
            case 3: weights = [0.40, 0.10, 0.10, 0.25, 0.15] // pacing-led
            default: weights = [0.20, 0.10, 0.10, 0.20, 0.40] // market-led
            }
            let vec = [depth, titlecraft, disclosure, packaging, marketFit]
            let blended = zip(vec, weights).map(*).reduce(0, +)
            // Map 0…1 blended signal into a realistic 55…99 commercial band.
            return Int((55 + blended * 44).rounded())
        }
    }

    // MARK: - Notes

    private static func note(for criterion: String, score: Int) -> String {
        if score >= 88 { return "Strong — no changes needed." }
        if score >= AIReviewResult.threshold { return "Meets the bar; minor tightening optional." }
        switch criterion {
        case "Narrative Craft", "Story & Structure", "Composition":
            return "Deepen the synopsis so the structure and stakes are unmistakable."
        case "Originality":
            return "Sharpen what makes this distinct from existing titles in the genre."
        case "Prose & Polish", "Mix & Master", "Editing & Pacing":
            return "Another editing/QC pass on the uploaded file will lift this."
        case "Pacing & Hook", "Replay Value":
            return "Lead with a stronger hook; clarify the payoff for the audience."
        case "Production Quality", "Cinematography", "Sound Design":
            return "Confirm the master is delivered at full commercial fidelity."
        case "Market Fit":
            return "Pick a tighter genre and a list price inside the $0.99–$19.99 sweet spot."
        default:
            return "Tighten this dimension before resubmitting."
        }
    }

    // MARK: - Helpers

    private static func seededJitter(_ key: String, spread: Int) -> Int {
        let h = stableHash(key)
        return (h % (spread * 2 + 1)) - spread
    }

    private static func clamp(_ value: Int) -> Int { max(0, min(100, value)) }
}

func mapRange(_ x: Double, inMin: Double, inMax: Double, outMin: Double, outMax: Double) -> Double {
    guard inMax != inMin else { return outMin }
    let t = max(0, min(1, (x - inMin) / (inMax - inMin)))
    return outMin + t * (outMax - outMin)
}
