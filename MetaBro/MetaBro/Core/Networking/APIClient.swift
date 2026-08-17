import Foundation

enum APIError: Error, Equatable {
    case offline
    case decoding
    case server(status: Int)
    case transport
    case encoding
}

/// Shared JSON coders so request/response formats are consistent app-wide.
enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

struct Endpoint {
    enum Method: String { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }

    var path: String
    var method: Method = .get
    var query: [URLQueryItem] = []
    var body: Data? = nil

    static func get(_ path: String, query: [URLQueryItem] = []) -> Endpoint {
        Endpoint(path: path, method: .get, query: query)
    }

    static func post(_ path: String, body: (any Encodable)? = nil) throws -> Endpoint {
        Endpoint(path: path, method: .post, body: try encode(body))
    }

    static func patch(_ path: String, body: (any Encodable)? = nil) throws -> Endpoint {
        Endpoint(path: path, method: .patch, body: try encode(body))
    }

    static func delete(_ path: String) -> Endpoint {
        Endpoint(path: path, method: .delete)
    }

    private static func encode(_ body: (any Encodable)?) throws -> Data? {
        guard let body else { return nil }
        do { return try JSON.encoder.encode(body) }
        catch { throw APIError.encoding }
    }
}

/// Minimal async networking surface. Services depend on the protocol so they can
/// be unit-tested against fakes without touching the network.
protocol APIClient: Sendable {
    /// Sends a request and decodes the response body.
    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T
    /// Sends a request that returns no meaningful body (mutations).
    func send(_ endpoint: Endpoint) async throws
}

/// Live client with exponential-backoff retry on transient transport failures.
final class LiveAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await data(for: endpoint)
        do { return try JSON.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding }
    }

    func send(_ endpoint: Endpoint) async throws {
        _ = try await data(for: endpoint)
    }

    /// Performs the request with retry, returning the raw response body.
    private func data(for endpoint: Endpoint) async throws -> Data {
        var attempt = 0
        let maxAttempts = 4
        while true {
            do {
                return try await perform(endpoint)
            } catch APIError.transport where attempt < maxAttempts - 1 {
                attempt += 1
                let backoff = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000) // 2s,4s,8s
                try await Task.sleep(nanoseconds: backoff)
            }
        }
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components?.url else { throw APIError.transport }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

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
        return data
    }
}
