import Foundation
import Combine

@MainActor
final class ErrorMonitor: ObservableObject {
    static let shared = ErrorMonitor()

    struct LogEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let category: String
        let message: String
        let detail: String?
    }

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 200
    private let storageKey = "auctionbaby.errormonitor.entries.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([LogEntry].self, from: data) {
            entries = decoded
        }
    }

    func record(category: String, message: String, detail: String? = nil) {
        let entry = LogEntry(id: UUID(), timestamp: Date(), category: category,
                             message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        persist()
        #if DEBUG
        print("[ErrorMonitor] \(category): \(message)" + (detail.map { " — \($0)" } ?? ""))
        #endif
    }

    func record(category: String, message: String, error: Error) {
        record(category: category, message: message, detail: String(describing: error))
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    var lastStoreKitError: String? {
        entries.filter { $0.category == "StoreKit" }.last?.detail
            ?? entries.filter { $0.category == "StoreKit" }.last?.message
    }

    var storeKitSummary: String {
        let skEntries = entries.filter { $0.category == "StoreKit" }
        if skEntries.isEmpty { return "No StoreKit errors recorded." }
        let last = skEntries.last!
        return "\(skEntries.count) event(s) · most recent: \(last.message)" + (last.detail.map { " (\($0))" } ?? "")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
