import Foundation
import UserNotifications

// MARK: - HermesInterestEngine
//
// Manages interest-based notifications and content.
// Uses only on-device scheduling (UNUserNotificationCenter) — no external
// tracking, fully App Store compliant.
//
// For real-time event data (sports scores, movie releases) the engine uses
// free public RSS/JSON APIs with no auth required:
//   • Movies:  RSS from iTunes Movie Trailers
//   • Sports:  ESPN public scores endpoint
//   • News:    RSS feeds per topic

actor HermesInterestEngine {
    static let shared = HermesInterestEngine()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Notification permission

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Schedule interest notifications

    /// Call after onboarding or whenever interests change.
    func scheduleInterestNotifications(for persona: UserPersona) async {
        guard await requestPermission() else { return }

        // Remove all existing interest notifications before rescheduling
        let ids = persona.interests.map { "interest_\($0.id)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)

        for interest in persona.interests where interest.notificationsEnabled {
            await scheduleNotification(for: interest, persona: persona)
        }
    }

    private func scheduleNotification(for interest: Interest, persona: UserPersona) async {
        let content = UNMutableNotificationContent()
        content.title = "\(persona.assistantName) 🐻"
        content.sound = .default

        // Build body based on category — try to fetch real content, fall back to prompt
        content.body = await notificationBody(for: interest, persona: persona)

        // Schedule once daily at a sensible time per category
        var comps = DateComponents()
        comps.hour   = notificationHour(for: interest.category)
        comps.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: "interest_\(interest.id)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func notificationHour(for category: Interest.Category) -> Int {
        switch category {
        case .sports:   return 9    // morning scores
        case .movies:   return 18   // evening — after work
        case .food:     return 12   // lunch time
        case .fitness:  return 7    // morning workout nudge
        case .finance:  return 8    // pre-market
        case .music:    return 17   // after-school/work
        default:        return 10
        }
    }

    // MARK: - Notification body generation

    private func notificationBody(for interest: Interest, persona: UserPersona) async -> String {
        let name = persona.userName.isEmpty ? "" : " \(persona.userName),"
        let detail = interest.detail ?? interest.label

        switch interest.category {
        case .movies:
            if let headline = await fetchMovieHeadline() {
                return "🎬\(name) \(headline)"
            }
            return "🎬\(name) Any good movies on your radar? I found something you might like — ask me!"

        case .sports:
            if let score = await fetchSportsHeadline(team: interest.detail) {
                return "🏆\(name) \(score)"
            }
            return "🏆\(name) Checking in on \(detail) — want the latest? Just ask me!"

        case .music:
            return "🎵\(name) New releases dropped this week. Want me to tell you about them?"

        case .food:
            if detail.lowercased().contains("starbucks") {
                return "☕️\(name) Ready for your \(detail)? I can help you reorder — just tap!"
            }
            return "🍽\(name) Thinking about what to eat? I have some ideas for you."

        case .fitness:
            return "💪\(name) Time to move! Even 10 minutes counts. Want a quick routine?"

        case .finance:
            return "💰\(name) Quick money check-in — want to log any spending today?"

        case .tech:
            return "⚡️\(name) Something interesting happened in tech today. Want the rundown?"

        case .travel:
            return "✈️\(name) Dreaming of your next trip? Ask me for inspiration!"

        default:
            return "Hey\(name) just thinking of you. Tap to chat!"
        }
    }

    // MARK: - Light public API fetches (no auth, no tracking)

    private func fetchMovieHeadline() async -> String? {
        guard let url = URL(string: "https://trailers.apple.com/trailers/home/rss/newtrailers.rss") else { return nil }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        // Parse first <title> after the channel title from RSS
        let xml = String(data: data, encoding: .utf8) ?? ""
        let titles = xml.components(separatedBy: "<title>")
            .dropFirst(2)   // skip channel title and first item
            .prefix(1)
            .compactMap { $0.components(separatedBy: "</title>").first }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return titles.first.map { "New trailer: \($0)" }
    }

    private func fetchSportsHeadline(team: String?) async -> String? {
        // ESPN public scoreboard — no API key needed
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=\(today)") else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return nil }

        for event in events {
            let name = (event["name"] as? String) ?? ""
            if let team, name.lowercased().contains(team.lowercased()) {
                let status = ((event["status"] as? [String: Any])?["type"] as? [String: Any])?["description"] as? String ?? ""
                let competitors = (event["competitions"] as? [[String: Any]])?.first?["competitors"] as? [[String: Any]] ?? []
                let scores = competitors.compactMap { c -> String? in
                    guard let t = (c["team"] as? [String: Any])?["abbreviation"] as? String,
                          let s = c["score"] as? String else { return nil }
                    return "\(t) \(s)"
                }.joined(separator: " – ")
                return "\(name): \(scores) (\(status))"
            }
        }
        return nil
    }

    // MARK: - Send immediate interest notification (for chat-triggered updates)

    func sendImmediateNotification(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Detect new interests from conversation

    /// Parse a user message for newly mentioned interests and return any found.
    func detectInterests(in text: String) -> [Interest] {
        let lower = text.lowercased()
        var found: [Interest] = []

        let checks: [(keyword: String, interest: Interest)] = [
            ("movie", Interest(id: "movies", category: .movies, label: "Movies", emoji: "🎬")),
            ("film",  Interest(id: "movies", category: .movies, label: "Movies", emoji: "🎬")),
            ("netflix", Interest(id: "movies", category: .movies, label: "Movies", emoji: "🎬")),
            ("nba",   Interest(id: "sports_nba", category: .sports, label: "NBA", emoji: "🏀")),
            ("nfl",   Interest(id: "sports_nfl", category: .sports, label: "NFL", emoji: "🏈")),
            ("mlb",   Interest(id: "sports_mlb", category: .sports, label: "MLB", emoji: "⚾️")),
            ("soccer",Interest(id: "sports_soccer", category: .sports, label: "Soccer", emoji: "⚽️")),
            ("music", Interest(id: "music", category: .music, label: "Music", emoji: "🎵")),
            ("spotify",Interest(id: "music", category: .music, label: "Music", emoji: "🎵")),
            ("gym",   Interest(id: "fitness", category: .fitness, label: "Fitness", emoji: "💪")),
            ("workout",Interest(id: "fitness", category: .fitness, label: "Fitness", emoji: "💪")),
            ("starbucks", Interest(id: "food_starbucks", category: .food, label: "Starbucks", emoji: "☕️")),
            ("coffee", Interest(id: "food_coffee", category: .food, label: "Coffee", emoji: "☕️")),
            ("travel", Interest(id: "travel", category: .travel, label: "Travel", emoji: "✈️")),
            ("gaming", Interest(id: "gaming", category: .gaming, label: "Gaming", emoji: "🎮")),
            ("crypto", Interest(id: "finance_crypto", category: .finance, label: "Crypto", emoji: "₿")),
            ("stocks", Interest(id: "finance_stocks", category: .finance, label: "Stocks", emoji: "📈")),
        ]

        for check in checks where lower.contains(check.keyword) {
            found.append(check.interest)
        }

        return found
    }
}
