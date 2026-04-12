import Foundation
import UserNotifications

// MARK: - CronJob model

struct CronJob: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String           // "Remind me to drink water"
    var body: String            // full notification text
    var schedule: JobSchedule
    var isEnabled: Bool = true
    var lastFired: Date?
    var createdAt: Date = Date()
    var category: JobCategory = .reminder

    enum JobCategory: String, Codable, CaseIterable, Identifiable {
        case reminder, habit, checkin, task
        var id: String { rawValue }
        var emoji: String {
            switch self {
            case .reminder: return "🔔"
            case .habit:    return "🔄"
            case .checkin:  return "✅"
            case .task:     return "📋"
            }
        }
    }
}

// MARK: - Schedule types

enum JobSchedule: Codable, Equatable {
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)   // 1=Sun … 7=Sat
    case interval(minutes: Int)                         // every N minutes (min 15 for background)
    case once(date: Date)

    var humanReadable: String {
        switch self {
        case .daily(let h, let m):
            return "Every day at \(formatted(h, m))"
        case .weekly(let wd, let h, let m):
            let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            let day = days[max(0, min(wd - 1, 6))]
            return "Every \(day) at \(formatted(h, m))"
        case .interval(let mins):
            return mins >= 60 ? "Every \(mins / 60)h" : "Every \(mins) min"
        case .once(let date):
            let f = DateFormatter()
            f.dateStyle = .short; f.timeStyle = .short
            return "Once — \(f.string(from: date))"
        }
    }

    private func formatted(_ h: Int, _ m: Int) -> String {
        let ampm = h >= 12 ? "PM" : "AM"
        let h12  = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", h12, m, ampm)
    }
}

// MARK: - HermesCronScheduler

/// Manages user-defined scheduled jobs using UNUserNotificationCenter.
/// No background daemon required — iOS delivers the notifications at the
/// scheduled time even if the app is closed.  When the user taps a
/// notification, the app opens and the job's payload is available.
actor HermesCronScheduler {
    static let shared = HermesCronScheduler()

    private var jobs: [CronJob] = []
    private let saveURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hermes/cron_jobs.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private init() {
        Task { await load() }
    }

    // MARK: - CRUD

    /// Add a new job and schedule its notification.
    func add(_ job: CronJob) async {
        jobs.append(job)
        save()
        if job.isEnabled { await schedule(job) }
    }

    /// Update an existing job.
    func update(_ job: CronJob) async {
        guard let idx = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        cancel(jobs[idx])
        jobs[idx] = job
        save()
        if job.isEnabled { await schedule(job) }
    }

    /// Delete a job and cancel its notification.
    func delete(id: UUID) async {
        if let job = jobs.first(where: { $0.id == id }) { cancel(job) }
        jobs.removeAll { $0.id == id }
        save()
    }

    func allJobs() -> [CronJob] { jobs }

    // MARK: - Scheduling

    private func schedule(_ job: CronJob) async {
        let content = UNMutableNotificationContent()
        content.title = "🐻  \(job.category.emoji)  \(job.title)"
        content.body = job.body
        content.sound = .default
        content.userInfo = ["jobId": job.id.uuidString]

        let trigger: UNNotificationTrigger

        switch job.schedule {
        case .daily(let h, let m):
            var c = DateComponents(); c.hour = h; c.minute = m
            trigger = UNCalendarNotificationTrigger(dateMatching: c, repeats: true)

        case .weekly(let wd, let h, let m):
            var c = DateComponents(); c.weekday = wd; c.hour = h; c.minute = m
            trigger = UNCalendarNotificationTrigger(dateMatching: c, repeats: true)

        case .interval(let mins):
            let secs = TimeInterval(max(15, mins) * 60)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: true)

        case .once(let date):
            let interval = max(1, date.timeIntervalSinceNow)
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: notifId(job),
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            #if DEBUG
            print("[CronScheduler] Failed to schedule notification for '\(job.title)': \(error)")
            #endif
        }
    }

    private func cancel(_ job: CronJob) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifId(job)])
    }

    private func notifId(_ job: CronJob) -> String { "cron_\(job.id.uuidString)" }

    // MARK: - Persistence

    private func load() async {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? decoder.decode([CronJob].self, from: data) else { return }
        jobs = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? encoder.encode(jobs) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    // MARK: - Natural language parser
    // Converts phrases like "every day at 8am", "every Monday at 9am",
    // "every 30 minutes" into a JobSchedule.

    static func parseSchedule(from text: String) -> JobSchedule? {
        let lower = text.lowercased()

        // "every N minutes"
        if let mins = extractNumber(after: "every", before: "minute", in: lower) {
            return .interval(minutes: mins)
        }
        // "every hour" / "every N hours"
        if lower.contains("every hour") { return .interval(minutes: 60) }
        if let hrs = extractNumber(after: "every", before: "hour", in: lower) {
            return .interval(minutes: hrs * 60)
        }

        // Parse time like "8am", "9:30pm", "14:00"
        let (hour, minute) = extractTime(from: lower) ?? (9, 0)

        // "every day" / "daily"
        if lower.contains("every day") || lower.contains("daily") {
            return .daily(hour: hour, minute: minute)
        }

        // "every monday" etc.
        let weekdays = ["sunday":1,"monday":2,"tuesday":3,"wednesday":4,
                        "thursday":5,"friday":6,"saturday":7]
        for (name, num) in weekdays where lower.contains(name) {
            return .weekly(weekday: num, hour: hour, minute: minute)
        }

        // "every morning" → 8am, "every evening" → 7pm, "every night" → 9pm
        if lower.contains("every morning") { return .daily(hour: 8,  minute: 0) }
        if lower.contains("every evening") { return .daily(hour: 19, minute: 0) }
        if lower.contains("every night")   { return .daily(hour: 21, minute: 0) }
        if lower.contains("every lunch")   { return .daily(hour: 12, minute: 0) }

        // Fallback: daily at extracted time
        if lower.contains("every") {
            return .daily(hour: hour, minute: minute)
        }

        return nil
    }

    private static func extractNumber(after prefix: String, before suffix: String, in text: String) -> Int? {
        let pattern = "\(prefix)\\s+(\\d+)\\s+\(suffix)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private static func extractTime(from text: String) -> (Int, Int)? {
        // "8am", "9:30pm", "14:00", "3 pm"
        let patterns = [
            "(\\d{1,2}):(\\d{2})\\s*(am|pm)?",
            "(\\d{1,2})\\s*(am|pm)"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            else { continue }

            let hourStr  = match.range(at: 1).location != NSNotFound ? substring(match.range(at: 1), in: text) : nil
            let minStr   = match.range(at: 2).location != NSNotFound && pattern.contains(":(") ? substring(match.range(at: 2), in: text) : "0"
            let meridiem = (match.numberOfRanges > 3) ? substring(match.range(at: match.numberOfRanges - 1), in: text) : nil

            guard var hour = Int(hourStr ?? "9") else { continue }
            let minute = Int(minStr ?? "0") ?? 0

            if let m = meridiem {
                if m.lowercased() == "pm" && hour != 12 { hour += 12 }
                if m.lowercased() == "am" && hour == 12 { hour = 0 }
            }
            return (hour, minute)
        }
        return nil
    }

    private static func substring(_ nsRange: NSRange, in text: String) -> String? {
        guard let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }
}
