import Foundation

// MARK: - MCP Client Service
// Implements Model Context Protocol over SSE or Streamable HTTP transports.
// Only supports HTTP-based transports (no local subprocess spawning — App Store safe).

actor MCPService {
    static let shared = MCPService()

    private var requestCounter = 0
    private var session = URLSession(configuration: .default)

    // MARK: - Tool Discovery

    func discoverTools(from server: MCPServerConfig) async throws -> [MCPTool] {
        guard server.isEnabled, let url = server.url else { return [] }

        let request = MCPRequest(id: nextId(), method: "tools/list", params: nil)
        let response: MCPResponse = try await send(request, to: url)

        guard let rawTools = response.result?.tools else { return [] }

        return rawTools.map { raw in
            MCPTool(
                serverId: server.id,
                name: "\(server.name)__\(raw.name)",
                description: raw.description ?? "",
                inputSchema: raw.inputSchema
            )
        }
    }

    // MARK: - Tool Execution

    func executeTool(
        named toolName: String,
        arguments: [String: AnyCodable],
        on server: MCPServerConfig
    ) async throws -> String {
        guard let url = server.url else {
            throw MCPError.serverNotConfigured(server.name)
        }

        // Strip server prefix from tool name
        let rawName = toolName.components(separatedBy: "__").dropFirst().joined(separator: "__")
        let params = MCPRequestParams(name: rawName, arguments: arguments, cursor: nil)
        let request = MCPRequest(id: nextId(), method: "tools/call", params: params)

        let response: MCPResponse = try await send(request, to: url)

        if let err = response.error {
            throw MCPError.executionFailed(err.message)
        }

        guard let content = response.result?.content else {
            return "(no result)"
        }

        let isError = response.result?.isError ?? false
        let text = content.compactMap(\.text).joined(separator: "\n")

        if isError {
            throw MCPError.executionFailed(text)
        }
        return text.isEmpty ? "(empty result)" : text
    }

    // MARK: - HTTP Transport

    private func send<T: Decodable>(_ request: MCPRequest, to url: URL) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        urlRequest.timeoutInterval = 30

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw MCPError.transportError("Non-200 response from MCP server")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func nextId() -> Int {
        requestCounter += 1
        return requestCounter
    }
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case serverNotConfigured(String)
    case transportError(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured(let name): return "MCP server '\(name)' is not configured."
        case .transportError(let msg): return "MCP transport error: \(msg)"
        case .executionFailed(let msg): return "MCP tool failed: \(msg)"
        }
    }
}
