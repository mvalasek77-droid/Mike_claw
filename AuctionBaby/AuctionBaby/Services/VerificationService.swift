import Foundation

/// Orchestrates the real-user verification flow (Slice 3 of the spine).
///
/// The blue check is server-owned truth: this service kicks off a session
/// on the auth Worker (`POST /verify/start`), interprets the vendor-specific
/// `nextStep`, and — for `manual` (the default) — parks the user in a
/// "pending" state that will flip when the founder approves via the admin
/// endpoint, at which point the push from slice 2 lands and `AuthService.
/// refreshMe()` picks up the new `verifiedAt`.
///
/// Absent config (`BackendConfig.authURL` empty) or an unsigned-in user →
/// the service is `disabled` and every call is a no-op. The existing
/// simulated verification in `VerificationSheet` still runs for demo users.
@MainActor
final class VerificationService: ObservableObject {
    /// The last outcome from `/verify/start`, so the UI can react.
    @Published private(set) var lastResult: StartResult?
    @Published private(set) var inFlight = false
    @Published var lastError: String?

    /// True iff the auth Worker is wired AND the app has a session token.
    /// (The Worker demands auth for /verify/start; we short-circuit locally
    /// so demo/local users get a clean "not applicable" instead of a 401.)
    var isEnabled: Bool {
        !BackendConfig.authURL.isEmpty && sessionToken() != nil
    }

    private static let sessionTokenKey = "com.valasek.auctionbaby.auth.sessionToken.v1"
    private func sessionToken() -> String? { SecureStore.string(forKey: Self.sessionTokenKey) }

    // MARK: - Public API

    /// Kick off (or resume) verification for the signed-in user. Idempotent
    /// server-side — a user who already passed gets the passed state back.
    ///
    /// The caller (usually `VerificationSheet`) interprets the returned
    /// `nextStep` to decide what to show:
    ///   • `.done`  → the check is already live (or the stub vendor passed
    ///                instantly); render the success state and refresh /me.
    ///   • `.wait`  → manual mode: park on a "we'll notify you" screen.
    ///   • `.sdk`   → future vendors (Persona/Onfido): launch their SDK.
    @discardableResult
    func startVerification() async -> StartResult {
        guard isEnabled, let session = sessionToken() else {
            let r = StartResult.failure("Sign in to verify your identity.")
            lastResult = r
            return r
        }
        inFlight = true
        defer { inFlight = false }
        lastError = nil

        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)/verify/start") else {
            let r = StartResult.failure("Auth Worker URL looks malformed.")
            lastResult = r
            return r
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                struct E: Decodable { let error: String? }
                let msg = (try? JSONDecoder().decode(E.self, from: data).error) ?? "HTTP \(status)"
                ErrorMonitor.shared.record(category: "Verify",
                                           message: "POST /verify/start failed",
                                           detail: msg)
                let r = StartResult.failure(msg)
                lastResult = r
                return r
            }
            let decoded = try JSONDecoder().decode(StartResponse.self, from: data)
            let r = StartResult.success(decoded)
            lastResult = r
            return r
        } catch {
            ErrorMonitor.shared.record(category: "Verify",
                                       message: "POST /verify/start transport",
                                       error: error)
            let r = StartResult.failure(error.localizedDescription)
            lastResult = r
            return r
        }
    }

    /// Submit the result of the on-device Vision checks. Images and landmarks
    /// never enter this request; the server receives only bounded numeric
    /// quality/match scores and the liveness outcome.
    func submitVerificationResult(selfieScore: Double,
                                  livenessPassed: Bool,
                                  faceMatchScore: Double) async -> SubmitResult {
        guard isEnabled, let session = sessionToken() else {
            return .failure("Sign in to verify your identity.")
        }
        inFlight = true
        defer { inFlight = false }
        lastError = nil

        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)/verify/submit") else {
            return .failure("Auth Worker URL looks malformed.")
        }

        struct Body: Encodable {
            let selfieScore: Double
            let livenessPassed: Bool
            let faceMatchScore: Double
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(Body(
                selfieScore: min(max(selfieScore, 0), 1),
                livenessPassed: livenessPassed,
                faceMatchScore: min(max(faceMatchScore, 0), 1)
            ))
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(statusCode) else {
                struct E: Decodable { let error: String? }
                let message = (try? JSONDecoder().decode(E.self, from: data).error) ?? "HTTP \(statusCode)"
                lastError = message
                return .failure(message)
            }
            return .success(try JSONDecoder().decode(SubmitResponse.self, from: data))
        } catch {
            ErrorMonitor.shared.record(category: "Verify", message: "POST /verify/submit failed", error: error)
            lastError = error.localizedDescription
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Response shapes

    /// Mirrors the Worker's `handleVerifyStart` response.
    struct StartResponse: Decodable {
        let verificationId: String?
        let vendor: String
        let status: String
        let verifiedAt: Double?
        let nextStep: NextStep

        struct NextStep: Decodable {
            let kind: String            // "done" | "wait" | "sdk"
            let message: String?
            let vendor: String?
            let ref: String?
        }
    }

    enum StartResult {
        case success(StartResponse)
        case failure(String)
    }

    struct SubmitResponse: Decodable {
        let status: String
        let verifiedAt: Double?
        let message: String?
    }

    enum SubmitResult {
        case success(SubmitResponse)
        case failure(String)
    }
}
