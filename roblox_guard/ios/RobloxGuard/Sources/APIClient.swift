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
}
