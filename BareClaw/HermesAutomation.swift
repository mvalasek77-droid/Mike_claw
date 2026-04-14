import Foundation
import UIKit

// MARK: - HermesAutomation
//
// On-device automation within Apple guidelines:
//  • Spending / habit tracker  — user logs manually; AI summarises
//  • App launcher              — opens installed apps via URL schemes
//  • Task memory               — "remember to reorder X" stored & surfaced
//  • Quick actions             — reorder Starbucks, open Maps, etc.
//
// Anything requiring cross-app data access uses the Shortcuts app
// (the user creates the Shortcut; we deep-link into it).

// MARK: - SpendingEntry

struct SpendingEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var amount: Double
    var category: SpendingCategory
    var merchant: String
    var note: String?
    var date: Date = Date()

    enum SpendingCategory: String, Codable, CaseIterable, Identifiable {
        case fastFood = "Fast Food"
        case coffee   = "Coffee"
        case groceries = "Groceries"
        case entertainment = "Entertainment"
        case transport = "Transport"
        case health   = "Health"
        case shopping = "Shopping"
        case other    = "Other"

        var id: String { rawValue }
        var emoji: String {
            switch self {
            case .fastFood:      return "🍔"
            case .coffee:        return "☕️"
            case .groceries:     return "🛒"
            case .entertainment: return "🎬"
            case .transport:     return "🚗"
            case .health:        return "💊"
            case .shopping:      return "🛍"
            case .other:         return "💳"
            }
        }
    }
}

// MARK: - SavedTask (things like "reorder Starbucks")

struct SavedTask: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String           // "Reorder my Starbucks drink"
    var action: TaskAction
    var createdAt: Date = Date()
    var lastTriggered: Date?

    enum TaskAction: Codable {
        case openURL(String)          // URL scheme / universal link
        case openShortcut(String)     // Shortcuts app deep-link
        case sendNotification(String) // just remind the user
        case customPrompt(String)     // ask the LLM to help
    }
}

// MARK: - HermesAutomation actor

actor HermesAutomation {
    static let shared = HermesAutomation()

    private var spendingLog: [SpendingEntry] = []
    private var savedTasks:  [SavedTask]     = []

    private let spendingURL: URL = fileURL("spending_log.json")
    private let tasksURL:    URL = fileURL("saved_tasks.json")

    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private init() {
        Task { await load() }
    }

    // MARK: - Spending tracker

    func logSpending(amount: Double, category: SpendingEntry.SpendingCategory,
                     merchant: String, note: String? = nil) async {
        let entry = SpendingEntry(amount: amount, category: category,
                                  merchant: merchant, note: note)
        spendingLog.append(entry)
        saveSpending()

        // Also write to Hermes memory so AI can reference it
        do {
            try await HermesMemory.shared.observe(
                category: "spending",
                content: ["amount": amount, "category": category.rawValue, "merchant": merchant],
                metadata: ["importance": 2]
            )
        } catch {}
    }

    /// Summary for the LLM to reference — totals by category for the current month.
    func monthlySummary() -> String {
        let cal   = Calendar.current
        let now   = Date()
        let month = cal.component(.month, from: now)
        let year  = cal.component(.year,  from: now)

        let thisMonth = spendingLog.filter {
            cal.component(.month, from: $0.date) == month &&
            cal.component(.year,  from: $0.date) == year
        }

        guard !thisMonth.isEmpty else { return "No spending logged this month." }

        let byCategory = Dictionary(grouping: thisMonth, by: \.category)
        let lines = byCategory.map { cat, entries -> String in
            let total = entries.reduce(0) { $0 + $1.amount }
            return "\(cat.emoji) \(cat.rawValue): $\(String(format: "%.2f", total))"
        }.sorted()

        let grandTotal = thisMonth.reduce(0) { $0 + $1.amount }
        return "This month:\n" + lines.joined(separator: "\n") +
               "\n\nTotal: $\(String(format: "%.2f", grandTotal))"
    }

    func recentEntries(limit: Int = 10) -> [SpendingEntry] {
        Array(spendingLog.suffix(limit).reversed())
    }

    // MARK: - Saved tasks

    func saveTask(_ task: SavedTask) async {
        savedTasks.removeAll { $0.title.lowercased() == task.title.lowercased() }
        savedTasks.append(task)
        saveTasks()
    }

    func allTasks() -> [SavedTask] { savedTasks }

    /// Execute a saved task — opens the appropriate app or runs the action.
    @MainActor
    func execute(task: SavedTask) async {
        var updated = task
        updated.lastTriggered = Date()
        await HermesAutomation.shared._updateTask(updated)

        switch task.action {
        case .openURL(let urlString):
            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                await UIApplication.shared.open(url)
            }
        case .openShortcut(let name):
            let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            if let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") {
                await UIApplication.shared.open(url)
            }
        case .sendNotification(let body):
            let content = UNMutableNotificationContent()
            content.title = "🐻 Reminder"
            content.body  = body
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: task.id.uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            _ = try? await UNUserNotificationCenter.current().add(req)
        case .customPrompt:
            break // handled in ChatViewModel
        }
    }

    func _updateTask(_ task: SavedTask) {
        if let idx = savedTasks.firstIndex(where: { $0.id == task.id }) {
            savedTasks[idx] = task
            saveTasks()
        }
    }

    // MARK: - Natural language task parser

    /// Detects automation intent from a user message.
    /// Returns a SavedTask if one can be created from the text.
    func detectTask(from text: String) -> SavedTask? {
        let lower = text.lowercased()

        // Starbucks reorder
        if lower.contains("starbucks") && (lower.contains("reorder") || lower.contains("order") || lower.contains("my drink")) {
            return SavedTask(
                title: "Reorder my Starbucks",
                action: .openURL("starbucks://")
            )
        }
        // Uber / Lyft
        if lower.contains("uber") || lower.contains("lyft") {
            let scheme = lower.contains("lyft") ? "lyft://" : "uber://"
            return SavedTask(title: "Open ride share", action: .openURL(scheme))
        }
        // DoorDash / Uber Eats
        if lower.contains("doordash") {
            return SavedTask(title: "Open DoorDash", action: .openURL("doordash://"))
        }
        if lower.contains("uber eats") {
            return SavedTask(title: "Open Uber Eats", action: .openURL("ubereats://"))
        }
        // Maps / navigation
        if lower.contains("navigate") || lower.contains("directions") {
            return SavedTask(title: "Open Maps", action: .openURL("maps://"))
        }
        // Spending tracker
        if lower.contains("track") && (lower.contains("spend") || lower.contains("spending") || lower.contains("money")) {
            return SavedTask(
                title: "Log spending",
                action: .customPrompt("Help me log a spending entry")
            )
        }
        // Generic "remind me"
        if lower.contains("remind me") {
            return SavedTask(
                title: String(text.prefix(60)),
                action: .sendNotification(text)
            )
        }
        return nil
    }

    // MARK: - App URL schemes catalogue

    static let appSchemes: [(name: String, emoji: String, scheme: String)] = [
        ("Starbucks",    "☕️", "starbucks://"),
        ("Uber",         "🚗", "uber://"),
        ("Lyft",         "🚗", "lyft://"),
        ("DoorDash",     "🍔", "doordash://"),
        ("Uber Eats",    "🍔", "ubereats://"),
        ("Maps",         "🗺", "maps://"),
        ("Spotify",      "🎵", "spotify://"),
        ("Netflix",      "🎬", "nflx://"),
        ("Instagram",    "📸", "instagram://"),
        ("Twitter/X",    "🐦", "twitter://"),
        ("YouTube",      "▶️", "youtube://"),
        ("Amazon",       "📦", "amazon://"),
        ("PayPal",       "💰", "paypal://"),
        ("Venmo",        "💸", "venmo://"),
        ("Snapchat",     "👻", "snapchat://"),
        ("Gmail",        "📧", "googlegmail://"),
    ]

    // MARK: - Persistence

    private func load() async {
        if let data = try? Data(contentsOf: spendingURL),
           let decoded = try? decoder.decode([SpendingEntry].self, from: data) {
            spendingLog = decoded
        }
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? decoder.decode([SavedTask].self, from: data) {
            savedTasks = decoded
        }
    }

    private func saveSpending() {
        if let data = try? encoder.encode(spendingLog) {
            try? data.write(to: spendingURL, options: .atomic)
        }
    }

    private func saveTasks() {
        if let data = try? encoder.encode(savedTasks) {
            try? data.write(to: tasksURL, options: .atomic)
        }
    }

    private static func fileURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}

// MARK: - UNUserNotificationCenter async shim

import UserNotifications
