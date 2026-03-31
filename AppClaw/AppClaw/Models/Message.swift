import Foundation

// MARK: - Chat Message

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var toolUses: [ToolUse]
    var isStreaming: Bool

    enum Role: String, Codable {
        case user, assistant, system, tool
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        toolUses: [ToolUse] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolUses = toolUses
        self.isStreaming = isStreaming
    }
}

// MARK: - Tool Use

struct ToolUse: Identifiable, Codable, Equatable {
    let id: UUID
    let toolName: String
    let input: [String: AnyCodable]
    var result: String?
    var status: Status

    enum Status: String, Codable {
        case running, success, failure
    }

    init(id: UUID = UUID(), toolName: String, input: [String: AnyCodable], result: String? = nil, status: Status = .running) {
        self.id = id
        self.toolName = toolName
        self.input = input
        self.result = result
        self.status = status
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var systemPrompt: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [Message] = [],
        systemPrompt: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - AnyCodable (type-erased Codable)

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:   try container.encode(bool)
        case let int as Int:     try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple string comparison for equality checks
        return "\(lhs.value)" == "\(rhs.value)"
    }
}
