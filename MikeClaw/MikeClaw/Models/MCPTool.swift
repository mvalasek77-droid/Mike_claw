import Foundation

// MARK: - MCP Server Configuration

struct MCPServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var transport: Transport
    var url: URL?
    var command: String?
    var args: [String]
    var env: [String: String]
    var isEnabled: Bool

    enum Transport: String, Codable, CaseIterable {
        case sse = "SSE"
        case streamableHTTP = "Streamable HTTP"
    }

    init(
        id: UUID = UUID(),
        name: String,
        transport: Transport = .streamableHTTP,
        url: URL? = nil,
        command: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.transport = transport
        self.url = url
        self.command = command
        self.args = args
        self.env = env
        self.isEnabled = isEnabled
    }
}

// MARK: - MCP Tool Definition

struct MCPTool: Identifiable, Codable, Hashable {
    let id: UUID
    let serverId: UUID
    let name: String
    let description: String
    let inputSchema: MCPToolSchema

    init(id: UUID = UUID(), serverId: UUID, name: String, description: String, inputSchema: MCPToolSchema) {
        self.id = id
        self.serverId = serverId
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

struct MCPToolSchema: Codable, Hashable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}

struct MCPPropertySchema: Codable, Hashable {
    let type: String
    let description: String?
    let enum_values: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description
        case enum_values = "enum"
    }
}

// MARK: - MCP Protocol Messages

struct MCPRequest: Codable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: MCPRequestParams?
}

struct MCPRequestParams: Codable {
    let name: String?
    let arguments: [String: AnyCodable]?
    let cursor: String?
}

struct MCPResponse: Codable {
    let jsonrpc: String
    let id: Int?
    let result: MCPResult?
    let error: MCPError?
}

struct MCPResult: Codable {
    let tools: [MCPToolRaw]?
    let content: [MCPContent]?
    let isError: Bool?
    let nextCursor: String?
}

struct MCPToolRaw: Codable {
    let name: String
    let description: String?
    let inputSchema: MCPToolSchema
}

struct MCPContent: Codable {
    let type: String
    let text: String?
}

struct MCPError: Codable {
    let code: Int
    let message: String
}

// MARK: - Claude Tool Format (from MCP tools)

struct ClaudeTool: Codable {
    let name: String
    let description: String
    let input_schema: ClaudeToolSchema
}

struct ClaudeToolSchema: Codable {
    let type: String
    let properties: [String: MCPPropertySchema]?
    let required: [String]?
}
