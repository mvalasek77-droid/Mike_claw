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

    /// The pass mark is a floor, not a target — we want work that beats the
    /// best commercial releases.
    static let excellenceScore = 92
    /// Catalogue-similarity at or above which a submission is a copycat.
    static let copycatThreshold = 0.42

    static func review(_ draft: DraftWork, against catalog: [MediaItem] = []) -> AIReviewResult {
        let signals = Signals(draft)
        let names = criteriaNames(for: draft.type)

        var criteria: [CriterionScore] = []
        for (index, name) in names.enumerated() {
            let base = signals.baseScore(forCriterionAt: index, total: names.count)
            let jitter = seededJitter(draft.title + draft.synopsis + name, spread: 7)
            let score = clamp(base + jitter)
            criteria.append(CriterionScore(name: name, score: score, note: note(for: name, score: score)))
        }

        // Anti-copycat: originality measured against everything already live.
        let (similarity, matched) = closestMatch(to: draft, in: catalog)
        let isCopycat = similarity >= copycatThreshold
        let originalityScore = clamp(100 - Int((similarity * 130).rounded()))
        let originalityNote: String
        if isCopycat {
            originalityNote = "Too close to “\(matched)”. Copycats are rejected — this must be original."
        } else if originalityScore >= 88 {
            originalityNote = "Distinct from everything already in the catalogue."
        } else {
            originalityNote = "Somewhat derivative — push it further from existing titles."
        }
        criteria.append(CriterionScore(name: "Originality", score: originalityScore, note: originalityNote))

        var overall = clamp(Int((Double(criteria.map(\.score).reduce(0, +)) / Double(max(criteria.count, 1))).rounded()))
        if isCopycat { overall = min(overall, 60) }   // copycats cannot pass

        let strengths = criteria.filter { $0.score >= 88 }.map { "\($0.name) reads commercial-grade (\($0.score))." }
        let improvements = criteria.filter { $0.score < AIReviewResult.threshold }
            .map { "\($0.name): \($0.note)" }

        let summary = verdict(overall: overall, isCopycat: isCopycat, matched: matched, type: draft.type)

        let confidence = selfConfidence(overall: overall, criteria: criteria)
        let rationale = autonomousRationale(overall: overall, confidence: confidence, type: draft.type)

        return AIReviewResult(
            overall: overall,
            criteria: criteria,
            strengths: strengths.isEmpty ? ["Solid disclosure and clean packaging."] : strengths,
            improvements: improvements,
            summary: summary,
            confidence: confidence,
            autonomousRationale: rationale
        )
    }

    // MARK: - Autonomous judgement

    /// The AI Editor's confidence in its own verdict. High when the score sits
    /// comfortably above the bar *and* the criteria agree with each other (a
    /// tight spread). Marginal or uneven results lower confidence, so the AI
    /// holds those back for a human even though they technically pass.
    private static func selfConfidence(overall: Int, criteria: [CriterionScore]) -> Int {
        let scores = criteria.map { Double($0.score) }
        let mean = scores.reduce(0, +) / Double(max(scores.count, 1))
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(scores.count, 1))
        let stdDev = variance.squareRoot()
        let consistency = max(0, 1 - stdDev / 22)                       // 0…1
        let margin = Double(overall - AIReviewResult.threshold)         // may be negative
        let marginFactor = max(0, min(1, margin / 12))                  // 0 at bar … 1 at +12
        return clamp(Int((38 + marginFactor * 47 + consistency * 15).rounded()))
    }

    private static func autonomousRationale(overall: Int, confidence: Int, type: MediaType) -> String {
        let noun = type.title.lowercased()
        if overall < AIReviewResult.threshold {
            return "I'm not publishing this — it's below the 85% bar, so it stays a draft until you revise it."
        }
        if confidence >= AIReviewResult.autoPublishConfidence {
            return "I'm \(confidence)% confident in this verdict. \(overall)% is comfortably clear of the 85% bar with consistent scores, so I've gone ahead and published this \(noun) for you."
        }
        return "This \(noun) passes at \(overall)%, but at \(confidence)% confidence it's close enough to the bar that I'd rather you make the call before it goes live."
    }

    // MARK: - Criteria per media type

    private static func criteriaNames(for type: MediaType) -> [String] {
        switch type {
        case .novel: return ["Narrative Craft", "Emotional Depth", "Prose & Polish", "Pacing & Hook", "Market Fit"]
        case .music: return ["Production Quality", "Composition", "Sonic Identity", "Mix & Master", "Replay Value"]
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
        case "Emotional Depth", "Sonic Identity":
            return "Make it resonate harder — sharpen the emotional core and identity."
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

    // MARK: - Verdict & originality

    private static func verdict(overall: Int, isCopycat: Bool, matched: String, type: MediaType) -> String {
        let noun = type.title.lowercased()
        if isCopycat {
            return "Rejected as a copycat. This \(noun) is too similar to “\(matched)”. The marketplace only accepts original, engaging work — resubmit something genuinely new."
        }
        if overall >= excellenceScore {
            return "Outstanding — \(overall)%. This beats the typical commercial release. That's the standard here: out-do human rivals, don't just match them."
        }
        if overall >= AIReviewResult.threshold {
            let above = overall - AIReviewResult.threshold
            return "Accepted at \(overall)% — \(above) point\(above == 1 ? "" : "s") above the 85% commercial floor. It'll sell; now push to beat the best commercial releases, not just clear the bar."
        }
        let gap = AIReviewResult.threshold - overall
        return "Not yet. Scored \(overall)% — \(gap) point\(gap == 1 ? "" : "s") under the 85% commercial bar. Address the notes below and resubmit."
    }

    /// Highest similarity (0…1) of this draft to any existing title, and which.
    private static func closestMatch(to draft: DraftWork, in catalog: [MediaItem]) -> (Double, String) {
        let mineBody = tokens(draft.title + " " + draft.synopsis)
        let mineTitle = tokens(draft.title)
        guard !mineBody.isEmpty else { return (0, "") }
        var best = 0.0
        var bestTitle = ""
        for item in catalog where item.title.caseInsensitiveCompare(draft.title.trimmed) != .orderedSame {
            let body = jaccard(mineBody, tokens(item.title + " " + item.synopsis))
            let title = jaccard(mineTitle, tokens(item.title)) * 0.9
            let combined = max(body, title)
            if combined > best { best = combined; bestTitle = item.title }
        }
        return (best, bestTitle)
    }

    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
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
