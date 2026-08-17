import Foundation
import os

/// Severity for a logged diagnostic event, ordered low to high.
enum LogLevel: Int, Comparable, Sendable {
    case debug, info, warning, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var symbol: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .warning: "warn"
        case .error: "error"
        }
    }
}

/// One recorded diagnostic event, captured for both the system console and
/// the in-memory history a bug report can attach.
struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    var formatted: String {
        "\(Self.formatter.string(from: timestamp)) [\(level.symbol)] [\(category)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

/// In-memory ring buffer of recent log entries. An actor so it's safe to
/// write from any isolation context without a lock; bounded so a chatty
/// session can't grow it unboundedly.
actor LogStore {
    private var entries: [LogEntry] = []
    private let capacity: Int

    init(capacity: Int = 300) {
        self.capacity = capacity
    }

    func record(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func recent(_ limit: Int = 300) -> [LogEntry] {
        Array(entries.suffix(limit))
    }

    func exportText(limit: Int = 300) -> String {
        recent(limit).map(\.formatted).joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }
}

/// App-wide structured logging. Every entry mirrors to the unified system
/// log (visible in Console.app / `log stream`) and to an in-memory ring
/// buffer, so a bug report can attach the last few minutes of context with
/// no extra plumbing at the call site.
enum BroLog {
    static let store = LogStore()

    static func debug(_ message: String, category: String = "app") { emit(.debug, category, message) }
    static func info(_ message: String, category: String = "app") { emit(.info, category, message) }
    static func warning(_ message: String, category: String = "app") { emit(.warning, category, message) }
    static func error(_ message: String, category: String = "app") { emit(.error, category, message) }

    /// Logs a caught `Error` and returns it unchanged, so call sites can
    /// log-and-rethrow (or log-and-fall-through) in one expression.
    @discardableResult
    static func error(_ error: Error, category: String = "app") -> Error {
        emit(.error, category, String(describing: error))
        return error
    }

    private static func emit(_ level: LogLevel, _ category: String, _ message: String) {
        let logger = Logger(subsystem: "com.metabro.app", category: category)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        Task { await store.record(entry) }
    }
}
