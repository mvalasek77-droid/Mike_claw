import Foundation

/// Thin client for the RobloxGuard backend. The app never talks to Roblox
/// directly and never handles the child's Roblox credentials — there is no
/// password field anywhere in this app by design.
struct APIClient {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func request<T: Decodable>(_ method: String, _ path: String,
                                       body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
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
    func reportURL(childId: Int, format: String = "html") -> URL {
        baseURL.appendingPathComponent("children/\(childId)/report")
            .appending(queryItems: [URLQueryItem(name: "format", value: format)])
    }

    func evidenceFileURL(evidenceId: Int) -> URL {
        baseURL.appendingPathComponent("evidence/\(evidenceId)/file")
    }

    func uploadEvidence(childId: Int, imageData: Data, filename: String,
                        note: String) async throws {
        let boundary = "rg-\(UUID().uuidString)"
        var req = URLRequest(url: baseURL.appendingPathComponent("children/\(childId)/evidence/upload"))
        req.httpMethod = "POST"
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
