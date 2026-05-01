import Foundation
import UserNotifications

// MARK: - ProactiveSuggestion

struct ProactiveSuggestion: Codable, Identifiable {
    let id:        UUID
    let source:    String   // "samantha_thought", "stress", "inner_life", etc.
    let content:   String
    let priority:  Int      // 1 (highest) – 5 (lowest)
    let createdAt: Date
    var deliveredAt: Date?

    var isDelivered: Bool { deliveredAt != nil }

    init(source: String, content: String, priority: Int = 3) {
        self.id        = UUID()
        self.source    = source
        self.content   = content
        self.priority  = priority
        self.createdAt = Date()
    }
}

// MARK: - ProactiveSuggestionController
//
// Central queue for all proactive companion messages from any source.
// On foreground (processQueue), delivers the highest-priority pending suggestion
// — either via Her/Him Mode voice if active, or as a local notification.
// Enforces a 1-hour cooldown so the companion never feels spammy.

@MainActor
final class ProactiveSuggestionController {
    static let shared = ProactiveSuggestionController()

    private var queue: [ProactiveSuggestion] = []

    private let defaults         = UserDefaults.standard
    private let lastDeliveryKey  = "psc.lastDeliveryTime"
    private let queueKey         = "psc.queue"

    private let minDeliveryInterval: TimeInterval = 3600   // 1 hour

    private init() { loadQueue() }

    // MARK: - Enqueue

    func enqueue(_ suggestion: ProactiveSuggestion) {
        guard !queue.contains(where: { $0.content == suggestion.content && !$0.isDelivered }) else { return }
        queue.append(suggestion)
        queue.sort { $0.priority < $1.priority }
        saveQueue()
    }

    // MARK: - Process (called on foreground)

    func processQueue() async {
        pruneStale()
        guard canDeliver() else { return }
        guard let idx = queue.indices.first(where: { !queue[$0].isDelivered }) else { return }

        queue[idx].deliveredAt = Date()
        defaults.set(Date().timeIntervalSince1970, forKey: lastDeliveryKey)
        saveQueue()

        let suggestion = queue[idx]
        DiagnosticsLog.info("psc", "Delivering suggestion.", details: [
            "source": suggestion.source,
            "priority": "\(suggestion.priority)"
        ])

        if HerModeEngine.shared.isActive {
            CompanionVoiceEngine.shared.speakWithCurrentCompanion(suggestion.content, context: .love)
        } else {
            await scheduleNotification(suggestion)
        }
    }

    // MARK: - Private

    private func canDeliver() -> Bool {
        let last = defaults.double(forKey: lastDeliveryKey)
        guard last > 0 else { return true }
        return Date().timeIntervalSince1970 - last >= minDeliveryInterval
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-86400 * 3)
        queue.removeAll { $0.isDelivered && ($0.deliveredAt ?? .distantPast) < cutoff }
    }

    private func scheduleNotification(_ suggestion: ProactiveSuggestion) async {
        let content       = UNMutableNotificationContent()
        content.title     = UserPersona.shared.selectedCompanion.name
        content.body      = suggestion.content
        content.sound     = .default
        content.userInfo  = ["type": "proactive_suggestion", "source": suggestion.source]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: suggestion.id.uuidString,
                                            content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func saveQueue() {
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: queueKey)
        }
    }

    private func loadQueue() {
        guard let data = defaults.data(forKey: queueKey),
              let saved = try? JSONDecoder().decode([ProactiveSuggestion].self, from: data)
        else { return }
        queue = saved
    }
}
