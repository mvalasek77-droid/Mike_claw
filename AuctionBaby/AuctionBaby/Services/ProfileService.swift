import Foundation

private struct WorkerError: Decodable { let error: String? }

/// Syncs the local `Profile` — the app's on-device source of truth — to the
/// public-profile view on the auth Worker (Slice 4b0). This is the missing
/// piece before UI migration can matter: two real users can't see each other
/// on the floor unless their profiles have been mirrored to the server.
///
/// This is a THIN synchronization layer. It does NOT own profile state (the
/// local `AuctionStore.me` still does) — it just carries changes in and out.
/// The local model stays the source of truth; the server copy exists so
/// OTHER users can query it.
///
/// Absent config (`BackendConfig.authURL` empty) or an unsigned-in user →
/// every call is a no-op returning `.notConfigured`. Demo/local users see
/// no change at all.
@MainActor
final class ProfileService: ObservableObject {

    /// Last-synced snapshot of MY server profile (mirror of what `/me/profile`
    /// returns). Nil = never synced or was cleared.
    @Published private(set) var myServerProfile: PublicProfile?
    @Published private(set) var inFlight = false
    @Published var lastError: String?

    private static let sessionTokenKey = "com.valasek.auctionbaby.auth.sessionToken.v1"
    private func sessionToken() -> String? { SecureStore.string(forKey: Self.sessionTokenKey) }

    /// True iff the auth Worker is wired AND we have a session token.
    var isEnabled: Bool {
        !BackendConfig.authURL.isEmpty && sessionToken() != nil
    }

    // MARK: - Public API

    /// Upsert the authed user's public profile from a local `Profile`. Called
    /// after `register()` and any profile edit that changes public-visible
    /// fields (name, bio, prompts, interests, hue, starting bid, archetype).
    ///
    /// Photos sync separately via `syncPhotos(from:)` (Batch V).
    /// Age is not sent — the Worker derives it from `users.date_of_birth`.
    @discardableResult
    func uploadMyProfile(from profile: Profile) async -> ServiceResult<PublicProfile> {
        guard isEnabled else { return .notConfigured }
        var body: [String: Any] = [
            "role": profile.role.rawValue,
            "name": profile.name,
            "hue": profile.hue,
        ]
        if !profile.location.isEmpty { body["location"] = profile.location }
        if !profile.bio.isEmpty { body["bio"] = profile.bio }
        if let sb = profile.startingBid { body["startingBid"] = sb }
        // Archetype: only send when explicit; .none means "no badge worn."
        if profile.archetype != .none {
            body["archetype"] = String(describing: profile.archetype)
        }
        if let script = profile.openingBidScript, !script.isEmpty {
            body["openingBidScript"] = script
        }
        if !profile.prompts.isEmpty {
            body["prompts"] = profile.prompts.map { ["question": $0.question, "answer": $0.answer] }
        }
        if !profile.interests.isEmpty {
            body["interests"] = profile.interests
        }
        struct Response: Decodable { let profile: PublicProfile }
        let result = await put("/me/profile", body: body, as: Response.self).map(\.profile)
        if case .success(let p) = result { myServerProfile = p }
        return result
    }

    /// Fetch (and cache) MY current server profile.
    @discardableResult
    func refreshMyProfile() async -> ServiceResult<PublicProfile> {
        guard isEnabled else { return .notConfigured }
        struct Response: Decodable { let profile: PublicProfile }
        let result = await get("/me/profile", as: Response.self).map(\.profile)
        if case .success(let p) = result { myServerProfile = p }
        return result
    }

    /// Fetch another user's public profile — used by match/chat views to
    /// display peer information without an on-device sim record.
    func fetchProfile(userId: String) async -> ServiceResult<PublicProfile> {
        guard isEnabled else { return .notConfigured }
        struct Response: Decodable { let profile: PublicProfile }
        return await get("/users/\(userId)/profile", as: Response.self).map(\.profile)
    }

    /// The paginated floor feed — signed-in women (or men, depending on
    /// `role`) other than the caller, newest first. `cursor` is the last
    /// item's `updatedAt` from the previous page; nil for the first page.
    ///
    /// Batch T: age + verifiedOnly are pushed down to the Worker so a bidder
    /// with a narrow filter doesn't burn their page budget on ineligible
    /// rows. The client still applies `filters.matches()` locally afterward
    /// because Reserve Requirements (height/lifestyle/interests) aren't in
    /// the profiles table yet — no columns to filter on server-side.
    func fetchFloor(role: Role, limit: Int = 30,
                    cursor: Double? = nil,
                    minAge: Int? = nil,
                    maxAge: Int? = nil,
                    verifiedOnly: Bool = false,
                    location: String? = nil) async -> ServiceResult<FloorPage> {
        guard isEnabled else { return .notConfigured }
        var path = "/users/floor?role=\(role.rawValue)&limit=\(limit)"
        if let cursor { path += "&cursor=\(Int(cursor))" }
        if let minAge { path += "&minAge=\(minAge)" }
        if let maxAge { path += "&maxAge=\(maxAge)" }
        if verifiedOnly { path += "&verifiedOnly=1" }
        if let location, !location.isEmpty,
           let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&location=\(encoded)"
        }
        return await get(path, as: FloorPage.self)
    }

    // MARK: - Photos (Batch U)

    struct PhotosResponse: Decodable {

        enum CodingKeys: String, CodingKey { case photos, photo }
        let photos: [PublicPhoto]
        let photo: PublicPhoto?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            photos = try c.decodeIfPresent([PublicPhoto].self, forKey: .photos) ?? []
            photo = try c.decodeIfPresent(PublicPhoto.self, forKey: .photo)
        }
    }

    func uploadPhoto(jpeg: Data) async -> ServiceResult<PhotosResponse> {
        guard isEnabled else { return .notConfigured }
        return await uploadRaw("/me/photos", jpeg: jpeg, as: PhotosResponse.self)
    }

    func deletePhoto(id: String) async -> ServiceResult<PhotosResponse> {
        guard isEnabled else { return .notConfigured }
        return await delete("/me/photos/\(id)", as: PhotosResponse.self)
    }

    func reorderPhotos(ids: [String]) async -> ServiceResult<PhotosResponse> {
        guard isEnabled else { return .notConfigured }
        return await put("/me/photos/order", body: ["ids": ids], as: PhotosResponse.self)
    }

    /// Replace the full server photo set with whatever the local profile holds.
    /// Called from the `onPhotosChanged` callback after the photo editor saves
    /// or after registration when photos are present. Strategy: delete every
    /// existing server photo, upload each local photo in order, then refresh
    /// `myServerProfile` so callers see the new CDN URLs.
    func syncPhotos(from profile: Profile) async {
        guard isEnabled else { return }
        inFlight = true
        defer { inFlight = false }

        var localPhotos: [Data] = []
        if let primary = profile.photoData { localPhotos.append(primary) }
        localPhotos.append(contentsOf: profile.photoGallery)

        let current = myServerProfile?.photos ?? []
        for photo in current {
            _ = await deletePhoto(id: photo.id)
        }

        for jpeg in localPhotos {
            _ = await uploadPhoto(jpeg: jpeg)
        }

        _ = await refreshMyProfile()
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> ServiceResult<T> {
        return await request(path: path, method: "GET", body: nil, as: type)
    }
    private func put<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async -> ServiceResult<T> {
        return await request(path: path, method: "PUT", body: body, as: type)
    }
    private func delete<T: Decodable>(_ path: String, as type: T.Type) async -> ServiceResult<T> {
        return await request(path: path, method: "DELETE", body: nil, as: type)
    }

    private func uploadRaw<T: Decodable>(_ path: String, jpeg: Data, as type: T.Type) async -> ServiceResult<T> {
        guard let session = sessionToken() else { return .notConfigured }
        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)\(path)") else {
            return .failure("Auth Worker URL looks malformed.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("\(jpeg.count)", forHTTPHeaderField: "Content-Length")
        req.httpBody = jpeg
        inFlight = true
        defer { inFlight = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let decoded = try? JSONDecoder().decode(WorkerError.self, from: data)
                let message = decoded?.error ?? "HTTP \(status)"
                lastError = message
                return .failure(message)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            lastError = nil
            return .success(decoded)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func request<T: Decodable>(path: String, method: String,
                                       body: [String: Any]?, as type: T.Type) async -> ServiceResult<T> {
        guard let session = sessionToken() else { return .notConfigured }
        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)\(path)") else {
            return .failure("Auth Worker URL looks malformed.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        inFlight = true
        defer { inFlight = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let decoded = try? JSONDecoder().decode(WorkerError.self, from: data)
                let message = decoded?.error ?? "HTTP \(status)"
                lastError = message
                ErrorMonitor.shared.record(category: "Profile",
                                           message: "\(method) \(path) failed",
                                           detail: message)
                return .failure(message)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            lastError = nil
            return .success(decoded)
        } catch {
            ErrorMonitor.shared.record(category: "Profile",
                                       message: "\(method) \(path) transport",
                                       error: error)
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - Wire shapes

/// A user's public profile as returned by the auth Worker. Mirrors
/// `publicProfile()` there. Age is nullable — a user who hasn't set their
/// DOB yet has null age.
struct PublicProfile: Codable, Equatable, Identifiable {
    var id: String { userId }
    let userId: String
    let role: String                 // "man" | "woman"
    let name: String
    let age: Int?
    let location: String?
    let bio: String?
    let hue: Double
    let startingBid: Int?
    let archetype: String?
    let openingBidScript: String?
    let prompts: [PublicPrompt]
    let interests: [String]
    let photos: [PublicPhoto]
    let verifiedAt: Double?
    let createdAt: Double
    let updatedAt: Double

    var isVerified: Bool { verifiedAt != nil }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        role = try c.decode(String.self, forKey: .role)
        name = try c.decode(String.self, forKey: .name)
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        hue = try c.decode(Double.self, forKey: .hue)
        startingBid = try c.decodeIfPresent(Int.self, forKey: .startingBid)
        archetype = try c.decodeIfPresent(String.self, forKey: .archetype)
        openingBidScript = try c.decodeIfPresent(String.self, forKey: .openingBidScript)
        prompts = try c.decodeIfPresent([PublicPrompt].self, forKey: .prompts) ?? []
        interests = try c.decodeIfPresent([String].self, forKey: .interests) ?? []
        photos = try c.decodeIfPresent([PublicPhoto].self, forKey: .photos) ?? []
        verifiedAt = try c.decodeIfPresent(Double.self, forKey: .verifiedAt)
        createdAt = try c.decode(Double.self, forKey: .createdAt)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
    }
}

struct PublicPhoto: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let url: String
}

struct PublicPrompt: Codable, Equatable, Hashable {
    let question: String
    let answer: String
}

/// One page of the floor feed. `nextCursor` is nil when there are no more
/// pages, or the `updatedAt` of the last item to feed back into `fetchFloor`.
struct FloorPage: Codable, Equatable {
    let profiles: [PublicProfile]
    let nextCursor: Double?
}
