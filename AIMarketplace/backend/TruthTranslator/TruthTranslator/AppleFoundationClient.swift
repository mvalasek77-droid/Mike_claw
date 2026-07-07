import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleFoundationClient {

    /// On-device Apple Foundation model for ambiguous texts the local engine can't confidently decode.
    /// Falls back gracefully on older iOS versions or if the model is unavailable.
    @available(iOS 26.0, *)
    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(model: model)

        let prompt = buildPrompt(text: text, tone: tone, context: context)
        let response = try await session.respond(to: prompt)
        let raw = response.content
        return try parseResponse(String(describing: raw))
        #else
        throw FoundationError.unavailable
        #endif
    }

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

    private func buildPrompt(text: String, tone: DecodeTone, context: DecodeContext) -> String {
        """
        You are ChadDrop, a fun and sharp text decoder for women figuring out what a guy really means.
        Use psychology, dating dynamics, and the dating marketplace to reveal the truth behind his words.
        Be blunt, funny, never mean. Use therapy techniques (CBT reframing, attachment theory, Gottman's principles).

        Analyze this text from a man and decode what he really means:
        "\(text)"

        Context: \(context.rawValue)
        Tone: \(tone.promptValue)

        Respond with ONLY valid JSON in this exact format:
        {
          "headline": "a funny one-liner headline",
          "translation": "what he actually means, blunt and funny",
          "psychology": "research-backed psychology explanation, cite studies",
          "receipts": ["signal1", "signal2"],
          "suggestedReplies": ["reply1", "reply2", "reply3"],
          "realityScore": 45,
          "energy": "short energy label with emoji",
          "flags": ["flag1", "flag2"]
        }
        """
    }

    private func parseResponse(_ raw: String) throws -> DecodeResult {
        var jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonStr.hasPrefix("```") {
            jsonStr = jsonStr.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw FoundationError.parseError
        }

        do {
            return try JSONDecoder().decode(DecodeResult.self, from: data)
        } catch {
            throw FoundationError.parseError
        }
    }

    enum FoundationError: LocalizedError {
        case unavailable
        case parseError

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Foundation model not available on this device"
            case .parseError: return "Could not parse Foundation model response"
            }
        }
    }
}