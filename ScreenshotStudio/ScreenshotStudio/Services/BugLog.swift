import UIKit

/// A lightweight, persistent diagnostics log.
///
/// Screenshot Studio is on-device and privacy-first — there's no server to
/// phone home to — so when something fails we record it locally instead. This
/// gives developers a "did anything fail?" trail and powers the user-facing
/// **Report a bug** flow, which hands the recent log to the share sheet so the
/// user can send it wherever they like. Nothing is ever transmitted
/// automatically.
final class BugLog: ObservableObject {
    static let shared = BugLog()

    enum Level: String, Codable, Hashable {
        case info, warning, error
        var symbol: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }

    struct Entry: Identifiable, Codable, Hashable {
        var id = UUID()
        var date: Date = Date()
        var level: Level
        var category: String
        var message: String
    }

    /// Newest entries last. Mutated only on the main thread so SwiftUI views
    /// can observe it directly.
    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 400
    private var fileURL: URL { Workspace.root.appendingPathComponent("diagnostics.json") }

    private init() { load() }

    // MARK: Recording (safe to call from any thread)

    nonisolated static func info(_ category: String, _ message: String) {
        shared.record(.info, category, message)
    }
    nonisolated static func warning(_ category: String, _ message: String) {
        shared.record(.warning, category, message)
    }
    nonisolated static func error(_ category: String, _ message: String) {
        shared.record(.error, category, message)
    }

    func record(_ level: Level, _ category: String, _ message: String) {
        let entry = Entry(level: level, category: category, message: message)
        #if DEBUG
        print("🐞 [\(level.rawValue.uppercased())] \(category): \(message)")
        #endif
        if Thread.isMainThread {
            apply(entry)
        } else {
            DispatchQueue.main.async { [weak self] in self?.apply(entry) }
        }
    }

    private func apply(_ entry: Entry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    var hasFailures: Bool { entries.contains { $0.level != .info } }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Report text

    /// A device/app summary that's safe to share (no personal content).
    static func deviceSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return """
        App: Screenshot Studio \(version) (\(build))
        Device: \(device.model) · iOS \(device.systemVersion)
        """
    }

    /// The recent log, formatted for a bug report.
    func recentLogText(limit: Int = 120) -> String {
        guard !entries.isEmpty else { return "No diagnostic events recorded." }
        let formatter = ISO8601DateFormatter()
        return entries.suffix(limit).map { entry in
            "[\(formatter.string(from: entry.date))] \(entry.level.rawValue.uppercased()) · \(entry.category): \(entry.message)"
        }.joined(separator: "\n")
    }

    /// Assemble the full text of a user bug report.
    func makeReport(userDescription: String, includeLog: Bool) -> String {
        var parts: [String] = ["Screenshot Studio — Bug Report", "", BugLog.deviceSummary(), ""]
        let trimmed = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("What happened:")
        parts.append(trimmed.isEmpty ? "(no description provided)" : trimmed)
        if includeLog {
            parts.append("")
            parts.append("Recent diagnostics:")
            parts.append(recentLogText())
        }
        return parts.joined(separator: "\n")
    }
}
