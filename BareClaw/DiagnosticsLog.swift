import Foundation
import OSLog

enum DiagnosticsLog {
    enum Level: String, Codable {
        case info
        case warning
        case error
    }

    private struct Entry: Codable {
        let timestamp: Date
        let level: Level
        let category: String
        let message: String
        let details: [String: String]
        let appVersion: String
        let build: String
        let osVersion: String
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BareClaw",
        category: "Diagnostics"
    )
    private static let queue = DispatchQueue(label: "com.bareclaw.diagnostics.log", qos: .utility)
    private static let maxFileBytes = 900_000
    private static let retainedBytesAfterRotation = 360_000

    static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (documents ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("BareClawDiagnostics.jsonl")
    }

    static func info(_ category: String, _ message: String, details: [String: String] = [:]) {
        record(level: .info, category: category, message: message, details: details)
    }

    static func warning(_ category: String, _ message: String, details: [String: String] = [:]) {
        record(level: .warning, category: category, message: message, details: details)
    }

    static func error(_ category: String, _ message: String, error: Error? = nil, details: [String: String] = [:]) {
        var merged = details
        if let error {
            merged["error"] = error.localizedDescription
            merged["errorType"] = String(describing: type(of: error))
        }
        record(level: .error, category: category, message: message, details: merged)
    }

    static func recentText(lineLimit: Int = 350) -> String {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "No diagnostics recorded yet."
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.suffix(max(1, lineLimit)).joined(separator: "\n")
        }
    }

    static func snapshotData(lineLimit: Int = 700) -> Data? {
        recentText(lineLimit: lineLimit).data(using: .utf8)
    }

    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
            writeUnlocked(
                Entry(
                    timestamp: Date(),
                    level: .info,
                    category: "diagnostics",
                    message: "Diagnostics log cleared.",
                    details: [:],
                    appVersion: appVersion,
                    build: buildNumber,
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                )
            )
        }
    }

    private static func record(level: Level,
                               category: String,
                               message: String,
                               details: [String: String]) {
        switch level {
        case .info:
            logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning:
            logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error:
            logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }

        let entry = Entry(
            timestamp: Date(),
            level: level,
            category: clipped(category, limit: 80),
            message: clipped(message, limit: 420),
            details: sanitized(details),
            appVersion: appVersion,
            build: buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )

        queue.async {
            rotateIfNeeded()
            writeUnlocked(entry)
        }
    }

    private static func writeUnlocked(_ entry: Entry) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry)
            data.append(0x0A)

            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            logger.error("Failed to write diagnostics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func rotateIfNeeded() {
        let url = fileURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue > maxFileBytes,
              let data = try? Data(contentsOf: url) else {
            return
        }

        let retained = data.suffix(retainedBytesAfterRotation)
        var rotated = Data()
        rotated.append(Data("{\"level\":\"info\",\"category\":\"diagnostics\",\"message\":\"Diagnostics log rotated.\"}\n".utf8))
        rotated.append(retained)
        try? rotated.write(to: url, options: .atomic)
    }

    private static func sanitized(_ details: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in details {
            let lowerKey = key.lowercased()
            let redactedKeyParts = ["key", "token", "secret", "password", "authorization"]
            let safeKey = clipped(key, limit: 80)
            if redactedKeyParts.contains(where: { lowerKey.contains($0) }) {
                output[safeKey] = "[redacted]"
            } else {
                output[safeKey] = sanitizedValue(value)
            }
        }
        return output
    }

    private static func sanitizedValue(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("sk-ant") || lower.contains("sk_") || lower.contains("xi-api-key") {
            return "[redacted]"
        }
        return clipped(value, limit: 700)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "..."
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
}
