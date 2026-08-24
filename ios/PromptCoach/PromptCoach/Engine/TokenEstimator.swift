import Foundation

/// What a coached prompt costs, approximately, on the chosen model.
///
/// Every number here is an **estimate**. An exact count needs the model's own
/// tokenizer or the `count_tokens` endpoint, and this app makes no network
/// calls at all — so the UI must always label these as approximate.
struct TokenReport: Codable, Hashable {
    let modelID: String
    /// Tokens in the raw ramble, as *this* model would tokenize it.
    let rambleTokens: Int
    /// Tokens in the core ask after the filler trim and de-duplication.
    let cleanedTokens: Int
    /// Tokens in the finished, model-ready prompt.
    let promptTokens: Int
    /// Filler phrases actually removed, for the "what I changed" line.
    let fillerRemoved: [String]
    let inputCostUSD: Double
    /// The same prompt priced on the most expensive model in the pack, so the
    /// recommender's saving is visible rather than asserted.
    let costOnPriciestUSD: Double
    let priciestModelName: String

    /// Tokens the wording trim removed from what the user actually typed.
    var wordingTokensSaved: Int { max(0, rambleTokens - cleanedTokens) }

    /// Per-run input saving from the recommended model versus the priciest.
    var costSavedUSD: Double { max(0, costOnPriciestUSD - inputCostUSD) }

    /// The coached prompt is frequently *longer* than the ramble — role,
    /// scope, and a success criterion cost tokens. Surfacing that honestly
    /// beats pretending every prompt shrinks.
    var promptIsLonger: Bool { promptTokens > rambleTokens }

    /// Sub-cent amounts are the norm here, so a plain 2-dp currency string
    /// would render every prompt as "$0.00".
    static func money(_ usd: Double) -> String {
        if usd <= 0 { return "$0" }
        if usd < 0.0001 { return "<$0.0001" }
        if usd < 0.01 { return String(format: "$%.4f", usd) }
        return String(format: "$%.2f", usd)
    }
}

/// On-device token estimation and the filler trim that makes prompts cheaper
/// without changing what they mean. Driven entirely by the pack's
/// `token_estimation` block; with that block absent the estimator degrades to
/// "unavailable" rather than guessing.
struct TokenEstimator {
    let config: TokenEstimation?

    var isAvailable: Bool { config != nil }

    private var charsPerToken: Double { max(1.0, config?.charsPerToken ?? 3.8) }

    /// Tokenizer multiplier for a model. Unknown ids fall back to 1.0 — an
    /// under-stated estimate is safer than an invented one.
    func multiplier(for modelID: String?) -> Double {
        guard let modelID, let m = config?.multipliers[modelID], m > 0 else { return 1.0 }
        return m
    }

    func estimate(_ text: String, modelID: String?) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let raw = Double(trimmed.count) / charsPerToken * multiplier(for: modelID)
        return max(1, Int(raw.rounded()))
    }

    func inputCost(tokens: Int, model: ModelProfile?) -> Double {
        guard let model else { return 0 }
        return Double(tokens) / 1_000_000.0 * model.priceInPerMtok
    }

    // MARK: Filler trim

    /// Drops throat-clearing phrases, and *only* those.
    ///
    /// A phrase is removed only where it leads a clause — the start of the
    /// input, or right after `.` `!` `?` `;` `,` or a newline. That single
    /// rule is what keeps "what kind of file" and "do you know the answer"
    /// intact while still catching "ok so, I was wondering if you could…".
    /// Text inside fenced code blocks is never touched.
    ///
    /// - Returns: the trimmed text and the phrases that were actually removed.
    func stripFiller(_ text: String) -> (text: String, removed: [String]) {
        guard let phrases = config?.fillerPhrases, !phrases.isEmpty,
              !text.isEmpty else { return (text, []) }

        // Odd-indexed segments are inside ``` fences — pass them through
        // untouched so code and pasted data survive verbatim.
        let segments = text.components(separatedBy: "```")
        // Longest first, so "so basically" is tried before "basically".
        let ordered = phrases.sorted { $0.count > $1.count }
        var removed: [String] = []
        var out: [String] = []

        for (index, segment) in segments.enumerated() {
            guard index % 2 == 0 else { out.append(segment); continue }
            var working = segment
            // Removing one phrase can expose the next ("ok so basically…"),
            // so sweep until stable. Bounded, therefore always terminating.
            var rounds = 0
            var changed = true
            while changed && rounds < 4 {
                changed = false
                rounds += 1
                for phrase in ordered {
                    let (next, hit) = removeClauseLeading(phrase, in: working)
                    guard hit else { continue }
                    working = next
                    changed = true
                    if !removed.contains(phrase) { removed.append(phrase) }
                }
            }
            out.append(working)
        }

        let joined = out.joined(separator: "```")
        return (joined.trimmingCharacters(in: .whitespacesAndNewlines), removed)
    }

    private func removeClauseLeading(_ phrase: String, in s: String) -> (String, Bool) {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        // (start-of-input | clause punctuation) + phrase + word boundary.
        // The trailing \b stops "basically" from biting into "basic".
        let pattern = "(?i)(\\A|[.!?;,\\n][ \\t]*)\(escaped)\\b,?[ \\t]*"
        guard let rx = try? NSRegularExpression(pattern: pattern) else { return (s, false) }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard rx.firstMatch(in: s, options: [], range: full) != nil else { return (s, false) }
        let out = rx.stringByReplacingMatches(in: s, options: [], range: full, withTemplate: "$1")
        return (out, true)
    }
}
