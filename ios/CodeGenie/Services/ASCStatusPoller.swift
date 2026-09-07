import Foundation
import CryptoKit

/// Asks Apple what happened to the build, from the phone.
///
/// The backend has an equivalent poller, but it cannot be used here:
/// it needs the App Store Connect key to sign its requests, and that
/// key deliberately never leaves the user's devices. Since shipping
/// runs on the paired Mac, the backend is not involved in the upload
/// at all and would have nothing to report.
///
/// So the phone asks directly. It already holds the key, and signing
/// an ES256 token is a few lines of CryptoKit. Without this, step 4 of
/// the guide — "wait for Apple to process it" — was a spinner that
/// never changed, on a wait that genuinely takes up to a few hours.
@MainActor
final class ASCStatusPoller: ObservableObject {

    /// What Apple says about the most recent build.
    struct Status: Equatable {
        /// Apple's own `processingState`, e.g. PROCESSING, VALID.
        let state: String
        let version: String?
        let buildNumber: String?
        /// Already written for a person to read.
        let summary: String
        /// True once there is nothing left to wait for.
        let isFinished: Bool
    }

    enum PollError: LocalizedError {
        case noCredentials
        case badKey(String)
        case appNotFound(String)
        case http(Int, String)
        case transport(String)

        // Explicit returns rather than a switch expression: the
        // property's type is `String?` while every arm produces a
        // `String`, and spelling out the returns keeps that coercion
        // unambiguous.
        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "Add your App Store Connect key in Settings first — checking the status needs it."
            case .badKey(let why):
                return "Your App Store Connect key couldn't be read: \(why)"
            case .appNotFound(let bundleID):
                return "No app in App Store Connect uses the ID \(bundleID). Check that the app record you created matches it exactly."
            case .http(let code, let body):
                if code == 401 {
                    return "Apple rejected your key. Check the Key ID and Issuer ID in Settings. \(body)"
                }
                return "Apple returned \(code). \(body)"
            case .transport(let why):
                return "Couldn't reach Apple: \(why)"
            }
        }
    }

    @Published private(set) var status: Status?
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?

    private let session: URLSession
    /// Keyed by bundle ID, not a bare "have we looked yet" flag —
    /// otherwise checking a second app on the same instance would
    /// silently report the first app's build.
    private var appIDCache: [String: String] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// One check. The caller decides when to repeat — Apple's own
    /// guidance is minutes, not seconds, and a tight loop here would
    /// burn the user's battery for no extra information.
    func check(bundleID: String, credentials: Credentials? = nil) async {
        let creds = credentials ?? .shared
        isChecking = true
        defer { isChecking = false }
        do {
            status = try await fetch(bundleID: bundleID, creds: creds)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: - Apple

    private func fetch(bundleID: String, creds: Credentials) async throws -> Status {
        guard !creds.ascKeyID.isEmpty,
              !creds.ascIssuerID.isEmpty,
              !creds.ascP8PEM.isEmpty
        else { throw PollError.noCredentials }

        let token = try mintJWT(
            keyID: creds.ascKeyID, issuerID: creds.ascIssuerID, pem: creds.ascP8PEM
        )

        // `/v1/builds` has no bundle-ID filter — Apple keys builds off
        // the numeric app id, so that has to be resolved first.
        let appID: String
        if let known = appIDCache[bundleID] {
            appID = known
        } else {
            appID = try await resolveAppID(bundleID: bundleID, token: token)
            appIDCache[bundleID] = appID
        }

        let builds = try await get(
            "https://api.appstoreconnect.apple.com/v1/builds"
                + "?filter%5Bapp%5D=\(escape(appID))&limit=1&sort=-uploadedDate",
            token: token
        )
        guard let first = (builds["data"] as? [[String: Any]])?.first else {
            return Status(
                state: "WAITING",
                version: nil,
                buildNumber: nil,
                summary: "Apple hasn't picked up your build yet. This is normal for the first few minutes after an upload.",
                isFinished: false
            )
        }
        let attributes = first["attributes"] as? [String: Any] ?? [:]
        let state = (attributes["processingState"] as? String) ?? "UNKNOWN"
        return Status(
            state: state,
            version: attributes["version"] as? String,
            buildNumber: attributes["buildNumber"] as? String,
            summary: Self.explain(state),
            isFinished: Self.finishedStates.contains(state)
        )
    }

    private func resolveAppID(bundleID: String, token: String) async throws -> String {
        let body = try await get(
            "https://api.appstoreconnect.apple.com/v1/apps"
                + "?filter%5BbundleId%5D=\(escape(bundleID))&limit=1",
            token: token
        )
        guard let id = (body["data"] as? [[String: Any]])?.first?["id"] as? String else {
            throw PollError.appNotFound(bundleID)
        }
        return id
    }

    private func get(_ url: String, token: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw PollError.transport("bad URL") }
        var request = URLRequest(url: u)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw PollError.transport(error.localizedDescription)
        }
        let (data, response) = result
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw PollError.http(code, Self.appleErrorDetail(data))
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Apple returns a structured error body; its `detail` is usually
    /// the only part worth showing anyone.
    private static func appleErrorDetail(_ data: Data) -> String {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let errors = body["errors"] as? [[String: Any]],
              let first = errors.first
        else { return "" }
        return (first["detail"] as? String) ?? (first["title"] as? String) ?? ""
    }

    private func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    // MARK: - Token

    /// Apple wants an ES256-signed JWT with a short TTL. CryptoKit's
    /// P-256 signing produces the raw r‖s form JWS expects, so no
    /// DER unwrapping is needed.
    private func mintJWT(keyID: String, issuerID: String, pem: String) throws -> String {
        let key: P256.Signing.PrivateKey
        do {
            key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        } catch {
            throw PollError.badKey(error.localizedDescription)
        }

        let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now,
            // Apple rejects anything longer than 20 minutes.
            "exp": now + 60 * 19,
            "aud": "appstoreconnect-v1",
        ]
        let headerPart = try base64URL(json: header)
        let payloadPart = try base64URL(json: payload)
        let signingInput = headerPart + "." + payloadPart
        // CryptoKit's `rawRepresentation` is the r‖s form JWS wants, so
        // there is no DER signature to unwrap.
        let signature = try key.signature(for: Data(signingInput.utf8))
        return signingInput + "." + base64URL(signature.rawRepresentation)
    }

    private func base64URL(json: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return base64URL(data)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Plain English

    /// Terminal as far as waiting goes. `VALID` is the good one; the
    /// rest mean stop refreshing and go read your email.
    private static let finishedStates: Set<String> = [
        "VALID", "INVALID", "FAILED", "EXPIRED",
    ]

    static func explain(_ state: String) -> String {
        switch state.uppercased() {
        case "PROCESSING":
            "Apple is checking your build. Usually 5 to 30 minutes, occasionally a few hours. You don't need to keep this open."
        case "VALID":
            "Done. Your build is ready to install through TestFlight."
        case "INVALID", "FAILED":
            "Apple rejected this build. They email the reason to your account holder address — it's almost always a missing icon, a bad Info.plist entry, or an entitlement you don't have."
        case "EXPIRED":
            "This build has expired. TestFlight builds last 90 days; upload a fresh one."
        case "WAITING":
            "Apple hasn't picked up your build yet."
        default:
            "Apple reports: \(state)."
        }
    }
}
