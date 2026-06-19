import Foundation

enum APIError: Error, Equatable {
    case offline
    case decoding
    case server(status: Int)
    case transport
}

struct Endpoint {
    var path: String
    var method: String = "GET"
    var query: [URLQueryItem] = []
}

/// Minimal async networking surface. ViewModels depend on the protocol so they
/// can be unit-tested against mocks without touching the network.
protocol APIClient: Sendable {
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T
}

/// Live client with exponential-backoff retry on transient transport failures.
final class LiveAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        var attempt = 0
        let maxAttempts = 4
        while true {
            do {
                return try await perform(endpoint, as: type)
            } catch APIError.transport where attempt < maxAttempts - 1 {
                attempt += 1
                let backoff = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000) // 2s,4s,8s
                try await Task.sleep(nanoseconds: backoff)
            }
        }
    }

    private func perform<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components?.url else { throw APIError.transport }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw APIError.offline
        } catch {
            throw APIError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}
