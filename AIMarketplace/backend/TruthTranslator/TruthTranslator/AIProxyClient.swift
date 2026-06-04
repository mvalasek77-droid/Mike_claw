import Foundation

struct DecodeService {
    private let engine = DecodeEngine()
    private let proxy = AIProxyClient()

    func decode(text: String, tone: DecodeTone, context: DecodeContext) async -> DecodeOutcome {
        if proxy.isConfigured {
            do {
                let result = try await proxy.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result.normalized, usedFallback: false)
            } catch {
                let result = engine.decode(text: text, tone: tone, context: context)
                return DecodeOutcome(result: result, usedFallback: true)
            }
        }
        return DecodeOutcome(result: engine.decode(text: text, tone: tone, context: context), usedFallback: true)
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
