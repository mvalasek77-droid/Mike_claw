import Foundation
import Combine

/// Lightweight in-app error monitor that captures StoreKit errors and other
/// app errors into a ring-buffer log. Designed for TestFlight debugging —
/// the admin console exposes the log so testers can report *why* something
/// failed instead of just seeing "unavailable".
@MainActor
final class ErrorMonitor: ObservableObject {
    static let shared = ErrorMonitor()

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let category: String   // e.g. "StoreKit", "Network", "Purchase"
        let message: String
        let detail: String?    // full error description / localizedDescription
    }

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 200
    private let storageKey = "errormonitor.entries.v1"

    private init() {
        // Restore persisted entries from previous session
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = decoded
        }
    }

    // MARK: - Public recording API

    func record(category: String, message: String, detail: String? = nil) {
        let entry = LogEntry(
            id: UUID(),
            timestamp: Date(),
            category: category,
            message: message,
            detail: detail
        )
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        persist()
        #if DEBUG
        print("[ErrorMonitor] \(category): \(message)" + (detail.map { " — \($0)" } ?? ""))
        #endif
    }

    /// Convenience: record an Error under a category.
    func record(category: String, message: String, error: Error) {
        record(category: category, message: message, detail: String(describing: error))
    }

    /// Clear all entries (admin action).
    func clear() {
        entries.removeAll()
        persist()
    }

    // MARK: - StoreKit diagnostics (computed helpers for the UI)

    /// Returns the most recent StoreKit-related error message, if any.
    var lastStoreKitError: String? {
        entries.filter { $0.category == "StoreKit" }.last?.detail ?? entries.filter { $0.category == "StoreKit" }.last?.message
    }

    /// Summary of StoreKit product loading status for the diagnostic card.
    var storeKitSummary: String {
        let skEntries = entries.filter { $0.category == "StoreKit" }
        if skEntries.isEmpty { return "No StoreKit errors recorded." }
        let last = skEntries.last!
        let count = skEntries.count
        return "\(count) error(s) · most recent: \(last.message)" + (last.detail.map { " (\($0))" } ?? "")
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}