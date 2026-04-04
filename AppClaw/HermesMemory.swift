import Foundation

// MARK: - Data model

/// A single memory entry stored on-device.
struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: String
    let content: AnyCodable   // arbitrary JSON-compatible value
    let metadata: [String: AnyCodable]
    var importance: Int       // 1–5; higher = kept longer during dream consolidation

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: String,
        content: Any,
        metadata: [String: Any] = [:],
        importance: Int = 1
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.content = AnyCodable(content)
        self.metadata = metadata.mapValues { AnyCodable($0) }
        self.importance = max(1, min(5, importance))
    }
}

/// Type-erased Codable wrapper so we can store arbitrary JSON values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)             { value = v; return }
        if let v = try? c.decode(Int.self)              { value = v; return }
        if let v = try? c.decode(Double.self)           { value = v; return }
        if let v = try? c.decode(String.self)           { value = v; return }
        if let v = try? c.decode([AnyCodable].self)     { value = v.map(\.value); return }
        if let v = try? c.decode([String: AnyCodable].self) {
            value = v.mapValues(\.value); return
        }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:              try c.encode(v)
        case let v as Int:               try c.encode(v)
        case let v as Double:            try c.encode(v)
        case let v as String:            try c.encode(v)
        case let v as [Any]:             try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:     try c.encode(v.mapValues { AnyCodable($0) })
        default:                         try c.encodeNil()
        }
    }
}

// MARK: - Memory store actor

/// Fully on-device, persistent memory store.
/// No network. Reads/writes to the app's sandboxed Documents directory.
actor HermesMemory {
    static let shared = HermesMemory()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var entries: [MemoryEntry] = []
    private var loaded = false

    /// Directory for all Hermes files inside the app sandbox.
    private let memoryDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes", isDirectory: true)
    }()

    private var shortTermFile: URL { memoryDir.appendingPathComponent("short_term.json") }

    private init() {}

    // MARK: - Write

    /// Record a new observation.
    func observe(category: String, content: Any, metadata: [String: Any] = [:]) async throws {
        try ensureDir()
        await loadIfNeeded()

        let importance = (metadata["importance"] as? Int) ?? 1
        let entry = MemoryEntry(
            category: category,
            content: content,
            metadata: metadata,
            importance: importance
        )
        entries.append(entry)
        try await persist()
    }

    // MARK: - Read

    /// Simple keyword search across serialized content.
    func search(query: String, limit: Int = 20) async -> [MemoryEntry] {
        await loadIfNeeded()
        let q = query.lowercased()
        return entries
            .filter { "\($0.content.value)".lowercased().contains(q)
                   || $0.category.lowercased().contains(q) }
            .suffix(limit)
            .reversed()
            .map { $0 }
    }

    /// Most recent N entries, newest first.
    func recentEntries(limit: Int = 50) async -> [MemoryEntry] {
        await loadIfNeeded()
        return Array(entries.suffix(limit).reversed())
    }

    /// All entries in a given category.
    func entries(for category: String) async -> [MemoryEntry] {
        await loadIfNeeded()
        return entries.filter { $0.category == category }
    }

    // MARK: - Maintenance

    /// Remove low-importance, old entries (called by DreamEngine at night).
    /// Keeps everything with importance >= threshold, or newer than `keepWindow`.
    func consolidate(importanceThreshold: Int = 2, keepWindow: TimeInterval = 7 * 86400) async throws {
        await loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-keepWindow)
        entries = entries.filter { $0.importance >= importanceThreshold || $0.timestamp > cutoff }
        try await persist()
    }

    /// Replace or promote an entry (used by DreamEngine to bump importance).
    func update(_ entry: MemoryEntry) async throws {
        await loadIfNeeded()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
            try await persist()
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: shortTermFile),
              let decoded = try? decoder.decode([MemoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() async throws {
        let data = try encoder.encode(entries)
        try data.write(to: shortTermFile, options: .atomic)
    }

    private func ensureDir() throws {
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
    }
}
