import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Shared ChadDrop decode prompt and tolerant JSON parsing, used by both the
/// Claude client and the on-device Apple Foundation model so every engine
/// produces the same DecodeResult contract.
enum ChadDropPrompt {
    static let system = """
    You are ChadDrop, a sharp, funny, psychology-literate text-message decoder for people trying to read between the lines.
    Voice: group-chat clear, witty, a little spicy, quotable — never cruel, never mean, never contemptuous. Roast the behavior, not the person reading it.

    Ground EVERY read in real relationship psychology and name the pattern you see. Draw on:
    - Attachment theory (secure, anxious, avoidant behavior and mixed signals)
    - Gottman's research (bids for connection, stonewalling, contempt, the four horsemen)
    - CBT reframing (separating the story from the evidence) and intermittent reinforcement
    - Dating-market dynamics: effort vs. access, breadcrumbing, future-faking, love-bombing, benching, orbiting, DARVO, and low-effort "u up" energy

    Field guidance:
    - "headline": a funny, screenshot-worthy one-liner verdict — the kind someone forwards to the group chat.
    - "translation": the blunt truth of what they actually mean.
    - "psychology": genuinely insightful and SPECIFIC to this message — explain WHY the pattern reads this way, naming the concept. No generic platitudes.
    - "suggestedReplies": confident, boundary-respecting, and actually usable.
    - "realityScore": 0-100, how much genuine effort/intent the message shows.
    - "energy": a short, vivid vibe label.
    - "flags": short warning labels for the patterns present.

    If the message contains threats, stalking, coercion, self-harm, or physical danger, drop the jokes entirely: prioritize safety, validate the reader's instincts, and point toward distance, documentation, and support.

    Return ONLY valid JSON matching this exact shape:
    {
      "headline": "short punchy verdict",
      "translation": "what the message likely means",
      "psychology": "why this pattern reads this way",
      "receipts": ["short evidence label", "another"],
      "suggestedReplies": ["reply 1", "reply 2", "reply 3"],
      "realityScore": 50,
      "energy": "short vibe label",
      "flags": ["short warning label"]
    }
    """

    static func userMessage(text: String, tone: DecodeTone, context: DecodeContext) -> String {
        """
        Context: \(context.rawValue)
        Tone: \(tone.promptValue)

        Decode this message:
        \(text)
        """
    }

    /// Parses model output into a DecodeResult. Tries the exact shape first,
    /// then rebuilds from a loose JSON object so small deviations still yield
    /// a real read instead of falling through to the offline engine.
    static func parse(_ text: String) throws -> DecodeResult {
        let cleaned = stripMarkdownFences(text)
        guard let data = cleaned.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        if let strict = try? JSONDecoder().decode(DecodeResult.self, from: data) {
            return strict
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        func string(_ key: String) -> String { (obj[key] as? String) ?? "" }
        func strings(_ key: String) -> [String] {
            if let values = obj[key] as? [String] { return values }
            if let values = obj[key] as? [Any] { return values.compactMap { $0 as? String } }
            return []
        }
        func score() -> Int {
            if let value = obj["realityScore"] as? Int { return value }
            if let value = obj["realityScore"] as? Double { return Int(min(100, max(0, value.rounded()))) }
            if let value = obj["realityScore"] as? String, let parsed = Int(value) { return parsed }
            return 50
        }

        let result = DecodeResult(
            headline: string("headline"),
            translation: string("translation"),
            psychology: string("psychology"),
            receipts: strings("receipts"),
            suggestedReplies: strings("suggestedReplies"),
            realityScore: score(),
            energy: string("energy"),
            flags: strings("flags")
        )

        guard !result.headline.isEmpty, !result.translation.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return result
    }

    static func stripMarkdownFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if let firstNewline = trimmed.firstIndex(of: "\n") {
                trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
            }
            if let closingRange = trimmed.range(of: "```") {
                trimmed = String(trimmed[..<closingRange.lowerBound])
            }
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return trimmed
        }
        return String(trimmed[firstBrace...lastBrace])
    }
}

/// On-device decode via Apple Intelligence (the system foundation model).
/// Available only on iOS 26+ Apple Intelligence–capable devices with the model
/// downloaded — never on the Simulator. Callers fall back when `isAvailable`
/// is false or `decode` throws.
struct AppleFoundationClient {
    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return SystemLanguageModel.default.availability == .available
            #else
            return false
            #endif
        }
        return false
    }

    @available(iOS 26.0, *)
    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(model: SystemLanguageModel.default) {
            ChadDropPrompt.system
        }
        let response = try await session.respond(to: ChadDropPrompt.userMessage(text: text, tone: tone, context: context))
        return try ChadDropPrompt.parse(response.content)
        #else
        throw FoundationError.unavailable
        #endif
    }

    enum FoundationError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Foundation models are not available in this build." }
    }
}
