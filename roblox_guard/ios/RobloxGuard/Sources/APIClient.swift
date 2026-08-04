import Foundation
import Security
import UIKit

/// Thin client for the RobloxGuard backend. The app never talks to Roblox
/// directly and never handles the child's Roblox credentials — there is no
/// password field anywhere in this app by design.
struct APIClient {
    var baseURL: URL
    /// Bearer token matching the backend's RG_API_TOKEN. In production this
    /// is provisioned at build time; empty only for local development.
    var apiToken: String
    var clientID: String

    init(baseURL: URL? = nil, apiToken: String? = nil,
         clientID: String = ClientIdentity.current) {
        let configuredURL: URL? = (Bundle.main.object(
            forInfoDictionaryKey: "RGAPIBaseURL"
        ) as? String)
            .flatMap(URL.init(string:))
            .flatMap { (url: URL) -> URL? in
                guard url.scheme == "https" || url.scheme == "http",
                      url.host != nil else { return nil }
                return url
            }
        let configuredToken = Bundle.main.object(
            forInfoDictionaryKey: "RGAPIToken"
        ) as? String

        #if DEBUG
        self.baseURL = baseURL ?? configuredURL ?? URL(string: "http://localhost:8000")!
        #else
        self.baseURL = baseURL ?? configuredURL
            ?? URL(string: "https://configuration.invalid")!
        #endif
        self.apiToken = apiToken ?? configuredToken ?? ""
        self.clientID = clientID
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue(clientID, forHTTPHeaderField: "X-RobloxGuard-Client-ID")
        if !apiToken.isEmpty {
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        }
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func request<T: Decodable>(_ method: String, _ path: String,
                                       body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 30
        authorize(&req)
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Unexpected response")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let detail = try? JSONDecoder().decode([String: String].self, from: data),
               let message = detail["detail"] {
                throw APIError(message: message)
            }
            throw APIError(message: "Server error (\(http.statusCode))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func listChildren() async throws -> [Child] {
        try await request("GET", "children")
    }

    func linkChild(username: String, parentName: String) async throws -> Child {
        try await request("POST", "children", body: [
            "roblox_username": username,
            // Set only after the parent confirms the consent screen.
            "parent_attestation": true,
            "parent_name": parentName,
        ])
    }

    func unlinkChild(id: Int) async throws {
        struct Empty: Decodable {}
        var req = URLRequest(url: baseURL.appendingPathComponent("children/\(id)"))
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30
        authorize(&req)
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 else {
            throw APIError(message: "Could not unlink account")
        }
    }

    func refresh(childId: Int) async throws {
        struct RefreshResponse: Decodable { let new_alerts: [NewAlert] }
        struct NewAlert: Decodable { let id: Int }
        let _: RefreshResponse = try await request("POST", "children/\(childId)/refresh")
    }

    func alerts(childId: Int) async throws -> [SafetyAlert] {
        struct AlertsResponse: Decodable { let alerts: [SafetyAlert] }
        let response: AlertsResponse = try await request("GET", "children/\(childId)/alerts")
        return response.alerts
    }

    func acknowledge(alertId: Int) async throws {
        struct AckResponse: Decodable { let acknowledged: Bool }
        let _: AckResponse = try await request("POST", "alerts/\(alertId)/acknowledge")
    }

    func resources() async throws -> [SafetyResource] {
        struct ResourcesResponse: Decodable { let resources: [SafetyResource] }
        let response: ResourcesResponse = try await request("GET", "resources")
        return response.resources
    }

    func education() async throws -> EducationContent {
        try await request("GET", "education")
    }

    func protectionStatus() async throws -> ProtectionStatus {
        struct Health: Decodable {
            let threat_feed: ProtectionStatus.FeedStatus
        }
        struct IntelStatus: Decodable {
            let runs: [ProtectionStatus.IntelRun]
            let analyzer: String
            let auto_apply: Bool
            let sources_configured: Int
        }
        let health: Health = try await request("GET", "health")
        let intel: IntelStatus = try await request("GET", "intel/runs")
        return ProtectionStatus(
            feed: health.threat_feed,
            lastIntelRun: intel.runs.first,
            analyzer: intel.analyzer,
            autoApply: intel.auto_apply,
            sourcesConfigured: intel.sources_configured
        )
    }

    /// Parent verdict on an alert. Drives adaptive tuning: three "dismissed"
    /// verdicts mute that signal type for that child (elevated alerts are
    /// never muted); one "confirmed" switches to heightened monitoring.
    func sendFeedback(alertId: Int, verdict: String) async throws {
        struct FeedbackResponse: Decodable { let feedback: String }
        let _: FeedbackResponse = try await request(
            "POST", "alerts/\(alertId)/feedback", body: ["verdict": verdict])
    }

    func evidence(childId: Int) async throws -> [EvidenceItem] {
        struct EvidenceResponse: Decodable { let evidence: [EvidenceItem] }
        let response: EvidenceResponse = try await request("GET", "children/\(childId)/evidence")
        return response.evidence
    }

    /// URL the incident report is served from — openable in Safari, printable,
    /// and shareable with investigators.
    func reportURL(childId: Int, accessToken: String,
                   format: String = "html") -> URL {
        baseURL.appendingPathComponent("children/\(childId)/report")
            .appending(queryItems: [
                URLQueryItem(name: "format", value: format),
                URLQueryItem(name: "share_token", value: accessToken),
            ])
    }

    func evidenceFileURL(evidenceId: Int, accessToken: String) -> URL {
        baseURL.appendingPathComponent("evidence/\(evidenceId)/file")
            .appending(queryItems: [
                URLQueryItem(name: "share_token", value: accessToken),
            ])
    }

    /// Submits a "Report a Bug" entry (Settings). Always persisted server-side
    /// to the durable bug log even if email relay isn't configured yet.
    @discardableResult
    func submitBugReport(summary: String, details: String, contactEmail: String) async throws -> Bool {
        struct BugReportResponse: Decodable { let id: Int; let emailed: Bool; let support_email: String }
        let response: BugReportResponse = try await request("POST", "support/bug-report", body: [
            "summary": summary,
            "details": details,
            "contact_email": contactEmail,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "platform": "iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)",
        ])
        return response.emailed
    }

    /// Hands the APNs device token to the backend (see PushManager.swift) so
    /// monitor.py's per-alert push hook knows where to deliver.
    func registerDevice(token: String) async throws {
        struct RegisterResponse: Decodable { let registered: Bool }
        let _: RegisterResponse = try await request("POST", "devices/register", body: [
            "token": token,
            "platform": "ios",
        ])
    }

    /// Fires one on-demand push to every registered device — for testing,
    /// so you don't have to wait for a real Roblox signal to fire.
    func sendTestNotification() async throws -> (sent: Int, failed: Int) {
        struct TestResponse: Decodable { let sent: Int; let failed: Int }
        let response: TestResponse = try await request("POST", "notifications/test")
        return (response.sent, response.failed)
    }

    func uploadEvidence(childId: Int, imageData: Data, filename: String,
                        note: String) async throws {
        let boundary = "rg-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appendingPathComponent("children/\(childId)/evidence/upload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        authorize(&req)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ string: String) { body.append(Data(string.utf8)) }
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\n\(note)\r\n")
        field("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        field("Content-Type: image/png\r\n\r\n")
        body.append(imageData)
        field("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let detail = try? JSONDecoder().decode([String: String].self, from: data),
               let message = detail["detail"] {
                throw APIError(message: message)
            }
            throw APIError(message: "Upload failed")
        }
    }
}

/// Stable, random per-installation identifier used to isolate each family's
/// records. It is stored in the Keychain so app updates do not silently
/// orphan linked accounts. It is not an advertising identifier.
private enum ClientIdentity {
    private static let service = "com.mikeclaw.robloxguard.installation"
    private static let account = "client-id"

    static var current: String {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var lookup = baseQuery
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let stored = String(data: data, encoding: .utf8),
           UUID(uuidString: stored) != nil {
            return stored
        }

        let generated = UUID().uuidString.lowercased()
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(generated.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        SecItemAdd(insert as CFDictionary, nil)
        return generated
    }
}
