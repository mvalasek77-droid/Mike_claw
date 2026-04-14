import Foundation

// MARK: - Memory tier

/// Short-term holds raw, recent observations.
/// Long-term holds entries that have been promoted by the DreamEngine.
enum MemoryTier: String, Codable {
    case shortTerm
    case longTerm
}

// MARK: - MemoryEntry

struct MemoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let category: String
    let content: AnyCodable
    let metadata: [String: AnyCodable]
    var importance: Int      // 1–5; decays over time, boosted by DreamEngine
    var tier: MemoryTier
    var accessCount: Int     // incremented on retrieval; informs eviction

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: String,
        content: Any,
        metadata: [String: Any] = [:],
        importance: Int = 1,
        tier: MemoryTier = .shortTerm
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.content = AnyCodable(content)
        self.metadata = metadata.mapValues { AnyCodable($0) }
        self.importance = max(1, min(5, importance))
        self.tier = tier
        self.accessCount = 0
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for arbitrary JSON-compatible values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // Bool must come before Int: in JSON, true/false are distinct from 1/0
        if let v = try? c.decode(Bool.self)                  { value = v; return }
        if let v = try? c.decode(Int.self)                   { value = v; return }
        if let v = try? c.decode(Double.self)                { value = v; return }
        if let v = try? c.decode(String.self)                { value = v; return }
        if let v = try? c.decode([AnyCodable].self)          { value = v.map { $0.value }; return }
        if let v = try? c.decode([String: AnyCodable].self)  { value = v.mapValues { $0.value }; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool:          try c.encode(v)
        case let v as Int:           try c.encode(v)
        case let v as Double:        try c.encode(v)
        case let v as String:        try c.encode(v)
        case let v as [Any]:         try c.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try c.encode(v.mapValues { AnyCodable($0) })
        default:                     try c.encodeNil()
        }
    }
}

// MARK: - MemoryIndex (Layered Memory Architecture)
//
// A lightweight keyword → entry-ID map persisted separately from the full
// entry store.  The HermesAgentHarness queries this index first; it only
// deserialises full entries for the small result set, preventing context
// entropy from reloading entire conversation histories.

struct MemoryIndex: Codable {
    /// keyword → set of entry IDs that contain it
    var keywordMap: [String: [UUID]] = [:]
    var updatedAt: Date = Date()

    /// Add an entry's keywords to the index.
    mutating func index(entry: MemoryEntry) {
        let words = tokenise("\(entry.content.value) \(entry.category)")
        for word in words {
            var ids = keywordMap[word, default: []]
            if !ids.contains(entry.id) { ids.append(entry.id) }
            keywordMap[word] = ids
        }
    }

    /// Remove an entry's ID from all keyword buckets.
    mutating func remove(id: UUID) {
        for key in keywordMap.keys {
            keywordMap[key]?.removeAll { $0 == id }
        }
    }

    /// Look up entry IDs matching ALL of the given keywords (AND logic).
    func lookup(keywords: [String]) -> Set<UUID> {
        guard !keywords.isEmpty else { return [] }
        let sets = keywords.map { kw -> Set<UUID> in
            Set(keywordMap[kw.lowercased()] ?? [])
        }
        return sets.dropFirst().reduce(sets[0]) { $0.intersection($1) }
    }

    /// Look up entry IDs matching ANY keyword (OR logic).
    func lookupAny(keywords: [String]) -> Set<UUID> {
        Set(keywords.flatMap { keywordMap[$0.lowercased()] ?? [] })
    }

    private func tokenise(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 }
    }
}

// MARK: - HermesMemory

/// Fully on-device, sandboxed memory store.
///
/// v3 additions:
/// - MemoryIndex: lightweight keyword map persisted separately for O(1) search
///   without deserialising full entry payloads (layered memory architecture)
actor HermesMemory {
    static let shared = HermesMemory()

    // MARK: - Constants

    private let shortTermCap = 2_000
    private let decayIntervalDays: Double = 3
    private let persistDebounceSeconds: Double = 2.0

    // MARK: - Storage

    private var entries: [MemoryEntry] = []
    /// Category → entry IDs (maintained in sync with `entries`)
    private var categoryIndex: [String: [UUID]] = [:]
    /// Lightweight keyword index (separate file, fast to load)
    private var memoryIndex: MemoryIndex = MemoryIndex()
    private var loaded = false

    /// Pending debounced persist task
    private var pendingPersistTask: Task<Void, Never>?

    // MARK: - Paths

    private let memoryDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes", isDirectory: true)
    }()

    private var shortTermFile: URL { memoryDir.appendingPathComponent("short_term.json") }
    private var longTermFile:  URL { memoryDir.appendingPathComponent("long_term.json") }
    private var indexFile:     URL { memoryDir.appendingPathComponent("memory_index.json") }

    // MARK: - Encoder / Decoder

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

    private init() {}

    // MARK: - Write

    /// Record a new observation. Returns the created entry's ID.
    @discardableResult
    func observe(category: String, content: Any, metadata: [String: Any] = [:]) async throws -> UUID {
        try ensureDir()
        await loadIfNeeded()

        let importance = (metadata["importance"] as? Int) ?? 1
        let entry = MemoryEntry(category: category, content: content,
                                metadata: metadata, importance: importance)
        append(entry)
        applyDecay()
        evictIfNeeded()
        schedulePersist()
        return entry.id
    }

    /// Batch-update multiple entries in one persist round-trip.
    func updateBatch(_ updated: [MemoryEntry]) async throws {
        await loadIfNeeded()
        for entry in updated {
            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[idx] = entry
            }
        }
        try await persistNow()
    }

    /// Update a single entry.
    func update(_ entry: MemoryEntry) async throws {
        try await updateBatch([entry])
    }

    // MARK: - Read

    /// All entries, newest first.
    func allEntries() async -> [MemoryEntry] {
        await loadIfNeeded()
        return entries.reversed()
    }

    /// Most recent N entries, newest first.
    func recentEntries(limit: Int = 50) async -> [MemoryEntry] {
        await loadIfNeeded()
        return Array(entries.suffix(limit).reversed())
    }

    /// Entries in a given category, newest first — O(index) lookup.
    func entries(for category: String) async -> [MemoryEntry] {
        await loadIfNeeded()
        let ids = Set(categoryIndex[category] ?? [])
        return entries
            .filter { ids.contains($0.id) }
            .reversed()
    }

    /// Entries matching multiple categories.
    func entries(forAny categories: [String]) async -> [MemoryEntry] {
        await loadIfNeeded()
        let ids = categories.flatMap { categoryIndex[$0] ?? [] }
        let idSet = Set(ids)
        return entries.filter { idSet.contains($0.id) }.reversed()
    }

    /// Keyword search across serialised content and category name.
    func search(query: String, limit: Int = 20) async -> [MemoryEntry] {
        await loadIfNeeded()
        let q = query.lowercased()
        let matches = entries
            .filter { "\($0.content.value)".lowercased().contains(q)
                   || $0.category.lowercased().contains(q) }
        // Bump access count for found entries
        let ids = Set(matches.map(\.id))
        for i in entries.indices where ids.contains(entries[i].id) {
            entries[i].accessCount += 1
        }
        return Array(matches.suffix(limit).reversed())
    }

    // MARK: - Maintenance

    /// Prune low-importance, old short-term entries (called by DreamEngine).
    func consolidate(importanceThreshold: Int = 2, keepWindow: TimeInterval = 7 * 86400) async throws {
        await loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-keepWindow)
        let before = entries.count
        entries = entries.filter {
            $0.tier == .longTerm
                || $0.importance >= importanceThreshold
                || $0.timestamp > cutoff
        }
        rebuildCategoryIndex()
        if entries.count != before { try await persistNow() }
    }

    /// Promote entries to long-term tier.
    func promoteToLongTerm(_ ids: [UUID]) async throws {
        await loadIfNeeded()
        var changed = false
        for i in entries.indices where ids.contains(entries[i].id) {
            if entries[i].tier != .longTerm {
                entries[i].tier = .longTerm
                changed = true
            }
        }
        if changed { try await persistNow() }
    }

    // MARK: - Private helpers

    private func append(_ entry: MemoryEntry) {
        entries.append(entry)
        categoryIndex[entry.category, default: []].append(entry.id)
        memoryIndex.index(entry: entry)
    }

    private func rebuildCategoryIndex() {
        categoryIndex = [:]
        memoryIndex = MemoryIndex()
        for entry in entries {
            categoryIndex[entry.category, default: []].append(entry.id)
            memoryIndex.index(entry: entry)
        }
    }

    // MARK: - Index-based search (layered architecture: no full deserialisation)

    /// Fast keyword search via MemoryIndex — resolves only matching entry IDs.
    func indexSearch(keywords: [String], limit: Int = 20) async -> [MemoryEntry] {
        await loadIfNeeded()
        let ids = memoryIndex.lookupAny(keywords: keywords.map { $0.lowercased() })
        let idMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return Array(ids
            .compactMap { idMap[$0] }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit))
    }

    /// Importance decay: short-term entries lose 1 point per `decayIntervalDays` days of age.
    private func applyDecay() {
        let now = Date()
        for i in entries.indices where entries[i].tier == .shortTerm {
            let ageDays = now.timeIntervalSince(entries[i].timestamp) / 86400
            let decaySteps = Int(ageDays / decayIntervalDays)
            let decayed = max(1, entries[i].importance - decaySteps)
            if decayed != entries[i].importance {
                entries[i].importance = decayed
            }
        }
    }

    /// Evict short-term entries beyond cap: lowest importance first, then oldest.
    private func evictIfNeeded() {
        // Bug fix #6: count only shortTerm entries against the cap — longTerm
        // entries are permanently retained and must not trigger eviction.
        let shortTerm = entries.filter { $0.tier == .shortTerm }
        guard shortTerm.count > shortTermCap else { return }

        let overflow = shortTerm.count - shortTermCap
        let toEvict = Set(
            shortTerm
                .sorted { lhs, rhs in
                    if lhs.importance != rhs.importance { return lhs.importance < rhs.importance }
                    return lhs.timestamp < rhs.timestamp
                }
                .prefix(overflow)
                .map(\.id)
        )
        entries.removeAll { toEvict.contains($0.id) }
        rebuildCategoryIndex()
    }

    /// Debounced: cancels any pending write and schedules a new one 2 s out.
    private func schedulePersist() {
        pendingPersistTask?.cancel()
        pendingPersistTask = Task { [weak self] in
            _ = try? await Task.sleep(nanoseconds: UInt64(2_000_000_000))
            guard !Task.isCancelled, let self else { return }
            _ = try? await self.persistNow()
        }
    }

    // MARK: - Persistence

    private func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        // Load both tiers and merge
        var all: [MemoryEntry] = []
        for file in [shortTermFile, longTermFile] {
            if let data = try? Data(contentsOf: file),
               let decoded = try? decoder.decode([MemoryEntry].self, from: data) {
                all.append(contentsOf: decoded)
            }
        }
        entries = all.sorted { $0.timestamp < $1.timestamp }

        // Load the lightweight index if present; rebuild if missing or stale
        if let idxData = try? Data(contentsOf: indexFile),
           let idx = try? decoder.decode(MemoryIndex.self, from: idxData) {
            memoryIndex = idx
            // Rebuild category index from entries (cheap)
            categoryIndex = [:]
            for entry in entries {
                categoryIndex[entry.category, default: []].append(entry.id)
            }
        } else {
            rebuildCategoryIndex()   // also rebuilds memoryIndex
        }
    }

    func persistNow() async throws {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil
        let short = entries.filter { $0.tier == .shortTerm }
        let long  = entries.filter { $0.tier == .longTerm }
        try encoder.encode(short).write(to: shortTermFile, options: .atomic)
        if !long.isEmpty {
            try encoder.encode(long).write(to: longTermFile, options: .atomic)
        }
        // Persist the lightweight index separately (much smaller than full entry files)
        let idxData = try encoder.encode(memoryIndex)
        try idxData.write(to: indexFile, options: .atomic)
    }

    private func ensureDir() throws {
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
    }
}
