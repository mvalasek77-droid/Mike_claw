import Foundation

/// The client for the matching Worker (Slice 4 of the spine — real bids,
/// matches, and messages between two signed-in users).
///
/// This service is the plumbing. In slice 4a it exposes typed calls for
/// every matching endpoint but **does not yet replace the on-device
/// simulation** — the app's SwiftUI screens still read from `AuctionStore`.
/// Slice 4b wires the screens to consume this service for signed-in users,
/// while keeping the sim for demo/local-only sessions.
///
/// Absent config (`BackendConfig.matchingURL` empty) or no session → the
/// service is `disabled` and every call returns `.notConfigured`.
///
/// Session tokens are read from the same Keychain slot `AuthService` uses,
/// so there's zero coupling between the two services.
@MainActor
final class MatchingService: ObservableObject {

    /// Latest fetched incoming bids (used by future UI). Nil = never fetched.
    @Published private(set) var incomingBids: [RemoteBid]?
    /// Latest fetched outgoing bids.
    @Published private(set) var outgoingBids: [RemoteBid]?
    /// Latest fetched matches.
    @Published private(set) var matches: [RemoteMatch]?
    @Published private(set) var inFlight = false
    @Published var lastError: String?

    private static let sessionTokenKey = "com.valasek.auctionbaby.auth.sessionToken.v1"
    private func sessionToken() -> String? { SecureStore.string(forKey: Self.sessionTokenKey) }

    /// True iff the matching Worker is wired AND we have a session token.
    var isEnabled: Bool {
        !BackendConfig.matchingURL.isEmpty && sessionToken() != nil
    }

    // MARK: - Bids

    /// Place a bid on another signed-in user (`lotId` = their serverUserId).
    /// Server rejects self-bids, non-positive amounts, and unknown lots.
    func placeBid(lotId: String, amount: Int, note: String? = nil,
                  gilded: Bool = false, insured: Bool = false,
                  isWhisper: Bool = false, promptRef: String? = nil) async -> ServiceResult<RemoteBid> {
        var body: [String: Any] = ["lotId": lotId, "amount": amount]
        if let note { body["note"] = note }
        if gilded { body["gilded"] = true }
        if insured { body["insured"] = true }
        if isWhisper { body["isWhisper"] = true }
        if let promptRef { body["promptRef"] = promptRef }
        struct Response: Decodable { let bid: RemoteBid }
        return await post("/bids", body: body, as: Response.self).map(\.bid)
    }

    @discardableResult
    func refreshIncoming() async -> ServiceResult<[RemoteBid]> {
        struct Response: Decodable { let bids: [RemoteBid] }
        let result = await get("/bids/incoming", as: Response.self).map(\.bids)
        if case .success(let list) = result { incomingBids = list }
        return result
    }

    @discardableResult
    func refreshOutgoing() async -> ServiceResult<[RemoteBid]> {
        struct Response: Decodable { let bids: [RemoteBid] }
        let result = await get("/bids/outgoing", as: Response.self).map(\.bids)
        if case .success(let list) = result { outgoingBids = list }
        return result
    }

    func accept(bidId: String) async -> ServiceResult<RemoteMatch> {
        struct Response: Decodable { let match: RemoteMatch }
        return await post("/bids/\(bidId)/accept", body: [:], as: Response.self).map(\.match)
    }

    func decline(bidId: String) async -> ServiceResult<RemoteBid> {
        struct Response: Decodable { let bid: RemoteBid }
        return await post("/bids/\(bidId)/decline", body: [:], as: Response.self).map(\.bid)
    }

    func withdraw(bidId: String) async -> ServiceResult<RemoteBid> {
        struct Response: Decodable { let bid: RemoteBid }
        return await post("/bids/\(bidId)/withdraw", body: [:], as: Response.self).map(\.bid)
    }

    // MARK: - Matches + messages

    @discardableResult
    func refreshMatches() async -> ServiceResult<[RemoteMatch]> {
        struct Response: Decodable { let matches: [RemoteMatch] }
        let result = await get("/matches", as: Response.self).map(\.matches)
        if case .success(let list) = result { matches = list }
        return result
    }

    /// One match + its messages (oldest first).
    func fetchMatch(_ matchId: String) async -> ServiceResult<MatchWithMessages> {
        return await get("/matches/\(matchId)", as: MatchWithMessages.self)
    }

    func sendMessage(matchId: String, text: String) async -> ServiceResult<RemoteMessage> {
        struct Response: Decodable { let message: RemoteMessage }
        return await post("/matches/\(matchId)/messages",
                          body: ["text": text], as: Response.self).map(\.message)
    }

    @discardableResult
    func markSeen(matchId: String) async -> ServiceResult<Int> {
        struct Response: Decodable { let updated: Int? }
        return await post("/matches/\(matchId)/mark-seen",
                          body: [:], as: Response.self).map { $0.updated ?? 0 }
    }

    @discardableResult
    func markDateDone(matchId: String) async -> ServiceResult<Bool> {
        struct Response: Decodable { let ok: Bool }
        return await post("/matches/\(matchId)/mark-date-done",
                          body: [:], as: Response.self).map(\.ok)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> ServiceResult<T> {
        await request(path: path, method: "GET", body: nil, as: type)
    }
    private func post<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async -> ServiceResult<T> {
        await request(path: path, method: "POST", body: body, as: type)
    }

    private func request<T: Decodable>(path: String, method: String,
                                       body: [String: Any]?, as type: T.Type) async -> ServiceResult<T> {
        guard isEnabled, let session = sessionToken() else { return .notConfigured }
        let base = BackendConfig.matchingURL.trimmingCharacters(in: .whitespaces)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)\(path)") else {
            return .failure("Matching Worker URL looks malformed.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        if let body, !body.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else if method == "POST" {
            // Empty POST — send an empty JSON body so servers that require
            // Content-Type on POST don't reject it.
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data("{}".utf8)
        }
        inFlight = true
        defer { inFlight = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                struct WorkerError: Decodable { let error: String? }
                let decoded = try? JSONDecoder().decode(WorkerError.self, from: data)
                let message = decoded?.error ?? "HTTP \(status)"
                lastError = message
                ErrorMonitor.shared.record(category: "Matching",
                                           message: "\(method) \(path) failed",
                                           detail: message)
                return .failure(message)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            lastError = nil
            return .success(decoded)
        } catch {
            ErrorMonitor.shared.record(category: "Matching",
                                       message: "\(method) \(path) transport",
                                       error: error)
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - Wire shapes (mirror the Worker's public*() functions)

/// The public bid shape returned by the matching Worker.
struct RemoteBid: Codable, Identifiable, Equatable {
    let id: String
    let bidderId: String
    let lotId: String
    let amount: Int
    let note: String?
    let status: String        // "pending" | "accepted" | "declined" | "withdrawn"
    let gilded: Bool
    let insured: Bool
    let isWhisper: Bool
    let promptRef: String?
    let createdAt: Double
    let resolvedAt: Double?
}

struct RemoteMatch: Codable, Identifiable, Equatable {
    let id: String
    let bidId: String
    let bidderId: String
    let lotId: String
    let amount: Int
    let phase: String         // "chatting" | "dateDone" | "closed"
    let createdAt: Double
    let expiresAt: Double?
    let reservedAmountCents: Int?
    let reservedAt: Double?
}

struct RemoteMessage: Codable, Identifiable, Equatable {
    let id: String
    let matchId: String
    let fromId: String
    let text: String
    let createdAt: Double
    let seenAt: Double?
}

struct MatchWithMessages: Codable, Equatable {
    let match: RemoteMatch
    let messages: [RemoteMessage]
}

// MARK: - Result type

enum ServiceResult<T> {
    case success(T)
    case failure(String)
    case notConfigured

    func map<U>(_ transform: (T) -> U) -> ServiceResult<U> {
        switch self {
        case .success(let v): return .success(transform(v))
        case .failure(let m): return .failure(m)
        case .notConfigured:  return .notConfigured
        }
    }
}
