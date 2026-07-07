import Foundation

struct DecodeService {
    private let engine = DecodeEngine()
    private let proxy = AIProxyClient()

    /// Confidence threshold: if the local engine's score is in this range, try Apple Foundation for a better read.
    private let uncertainRange = 35...65

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async -> DecodeOutcome {
        // Tier 1: AI Proxy (if configured) — best quality, requires backend
        if proxy.isConfigured {
            do {
                let result = try await proxy.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result.normalized, usedFallback: false)
            } catch {
                // Proxy failed, continue to next tier
            }
        }

        // Tier 2: Local engine
        let localResult = engine.decode(text: text, tone: tone, context: context)

        // If the engine is confident (score outside uncertain range), use its result directly
        if !uncertainRange.contains(localResult.realityScore) {
            return DecodeOutcome(result: localResult, usedFallback: true)
        }

        // Tier 3: Apple Foundation model — for ambiguous texts the engine can't confidently decode
        if #available(iOS 26.0, *) {
            let foundationClient = AppleFoundationClient()
            if foundationClient.isAvailable {
                do {
                    let foundationResult = try await foundationClient.decode(text: text, tone: tone, context: context)
                    return DecodeOutcome(result: foundationResult.normalized, usedFallback: false)
                } catch {
                    // Foundation failed, use local engine result
                }
            }
        }

        return DecodeOutcome(result: localResult, usedFallback: true)
    }
}

struct AIProxyClient {
    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AI_PROXY_URL") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    var isConfigured: Bool {
        endpoint != nil
    }

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async throws -> DecodeResult {
        guard let endpoint else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ProxyRequest(
            text: text,
            tone: tone.promptValue,
            context: context.rawValue
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DecodeResult.self, from: data)
    }

    private struct ProxyRequest: Encodable {
        let text: String
        let tone: String
        let context: String
    }
}