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

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    private let selectedInterestSyncSignatureKey = "hermes.interests.selectedSyncSignature"
    private let scheduledInterestSignatureKey = "hermes.interests.notificationScheduleSignature"
    private let scheduledInterestDateKey = "hermes.interests.notificationScheduleDate"
    private let notificationRescheduleInterval: TimeInterval = 6 * 60 * 60

    private init() {}

    // MARK: - Learning sync

    /// Persists the currently selected interests into memory/learning exactly
    /// when the selection changes. This keeps onboarding, settings, and startup
    /// aligned without adding duplicate intimacy every launch.
    func syncSelectedInterests(for persona: UserPersona, source: String) async {
        let signature = selectedInterestSignature(for: persona)
        let key = "\(selectedInterestSyncSignatureKey).\(persona.selectedCompanionID)"
        guard UserDefaults.standard.string(forKey: key) != signature else { return }
        DiagnosticsLog.info(
            "interests",
            "Selected interests sync started.",
            details: [
                "source": source,
                "companion": persona.selectedCompanionID,
                "interestCount": "\(persona.interests.count)"
            ]
        )

        for interest in persona.interests {
            await recordInterestSelection(interest, persona: persona, source: source)
        }

        UserDefaults.standard.set(signature, forKey: key)
        DiagnosticsLog.info("interests", "Selected interests sync finished.", details: ["source": source])
    }

    private func recordInterestSelection(_ interest: Interest, persona: UserPersona, source: String) async {
        _ = try? await HermesMemory.shared.observe(
            category: "interest_preference",
            content: [
                "id": interest.id,
                "label": interest.label,
                "category": interest.category.rawValue,
                "notificationsEnabled": interest.notificationsEnabled,
                "selected": true
            ],
            metadata: [
                "importance": 4,
                "source": source,
                "companionID": persona.selectedCompanionID
            ]
        )

        await HerLearningEngine.shared.processUserMessage(
            "I care about \(interest.label).",
            responseText: "I'll remember that \(interest.label) matters to you.",
            interests: persona.interests
        )
    }

    private func selectedInterestSignature(for persona: UserPersona) -> String {
        persona.interests
            .sorted { $0.id < $1.id }
            .map { "\($0.id):\($0.notificationsEnabled ? "1" : "0")" }
            .joined(separator: "|")
    }

    // MARK: - Notification permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            DiagnosticsLog.info("notification", "Notification permission checked.", details: ["granted": "\(granted)"])
            return granted
        } catch {
            DiagnosticsLog.error("notification", "Notification permission request failed.", error: error)
            return false
        }
    }

    // MARK: - Schedule interest notifications

    /// Call after onboarding or whenever interests change.
    func scheduleInterestNotifications(for persona: UserPersona) async {
        let signature = selectedInterestSignature(for: persona)
        let key = "\(scheduledInterestSignatureKey).\(persona.selectedCompanionID)"
        let dateKey = "\(scheduledInterestDateKey).\(persona.selectedCompanionID)"
        let now = Date().timeIntervalSince1970
        let lastScheduled = UserDefaults.standard.double(forKey: dateKey)
        if UserDefaults.standard.string(forKey: key) == signature,
           now - lastScheduled < notificationRescheduleInterval {
            DiagnosticsLog.info(
                "notification",
                "Interest notification schedule skipped because interests are unchanged.",
                details: ["companion": persona.selectedCompanionID]
            )
            return
        }

        await cancelAllInterestNotifications()

        let enabledInterests = persona.interests.filter { $0.notificationsEnabled }
        guard !enabledInterests.isEmpty else {
            DiagnosticsLog.info("notification", "No enabled interests to schedule.")
            UserDefaults.standard.set(signature, forKey: key)
            UserDefaults.standard.set(now, forKey: dateKey)
            return
        }
        guard await requestPermission() else {
            DiagnosticsLog.warning("notification", "Interest notifications not scheduled because permission is unavailable.")
            return
        }
        DiagnosticsLog.info(
            "notification",
            "Scheduling interest notifications.",
            details: ["count": "\(enabledInterests.count)", "companion": persona.selectedCompanionID]
        )

        for interest in enabledInterests {
            await scheduleNotification(for: interest, persona: persona)
        }
        UserDefaults.standard.set(signature, forKey: key)
        UserDefaults.standard.set(now, forKey: dateKey)
    }

    private func cancelAllInterestNotifications() async {
        let center = UNUserNotificationCenter.current()

        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("interest_") }
        if !pendingIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        }

        let deliveredIDs = await center.deliveredNotifications()
            .map { $0.request.identifier }
            .filter { $0.hasPrefix("interest_") }
        if !deliveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
        if !pendingIDs.isEmpty || !deliveredIDs.isEmpty {
            DiagnosticsLog.info(
                "notification",
                "Cancelled previous interest notifications.",
                details: ["pending": "\(pendingIDs.count)", "delivered": "\(deliveredIDs.count)"]
            )
        }
    }

    private func scheduleNotification(for interest: Interest, persona: UserPersona) async {
        let content = UNMutableNotificationContent()
        let displayName = persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName
        content.title = "\(displayName) 🐻"
        content.sound = .default

        // Build body based on category — try to fetch real content, fall back to prompt
        content.body = await notificationBody(for: interest, persona: persona)
        content.userInfo = [
            "handoffCategory": interest.category.rawValue,
            "interestID": interest.id,
            "interestLabel": interest.label,
            "companionID": persona.selectedCompanionID,
            "handoffMessage": notificationTapMessage(for: interest, persona: persona),
            "shouldSpeak": true
        ]

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
        do {
            try await UNUserNotificationCenter.current().add(request)
            DiagnosticsLog.info(
                "notification",
                "Interest notification scheduled.",
                details: [
                    "interestID": interest.id,
                    "category": interest.category.rawValue,
                    "hour": "\(notificationHour(for: interest.category))"
                ]
            )
        } catch {
            DiagnosticsLog.error(
                "notification",
                "Interest notification scheduling failed.",
                error: error,
                details: ["interestID": interest.id, "category": interest.category.rawValue]
            )
        }
    }

    private func notificationTapMessage(for interest: Interest, persona: UserPersona) -> String {
        let companion = persona.assistantName.isEmpty ? persona.selectedCompanion.name : persona.assistantName
        let detail = interest.detail ?? interest.label

        switch interest.category {
        case .food:
            return "\(companion) noticed you tapped the food idea. Tell me what sounds good - cozy, quick, healthy, indulgent, or nearby - and I'll help choose instead of just throwing a notification at you."
        case .music:
            return "\(companion) noticed you tapped the music nudge. I can pick songs for today's mood, explain why I chose them, or use your hearts in Vibes to learn what actually fits you."
        case .travel:
            return "\(companion) noticed you tapped the travel/place idea. Tell me where you're thinking of going and I'll help with the next step."
        case .fitness:
            return "\(companion) noticed you tapped the movement check-in. Want something gentle, fast, or actually challenging?"
        case .sports:
            return "\(companion) noticed you tapped \(detail). Want the latest, or do you want to talk about the game?"
        case .movies:
            return "\(companion) noticed you tapped the movie idea. Want a recommendation, a trailer-style pitch, or something based on your mood?"
        default:
            return "\(companion) noticed you tapped \(detail). I'm here - tell me what you want to do with it."
        }
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
        guard let (data, _) = try? await session.data(from: url) else {
            DiagnosticsLog.warning("interests", "Movie headline fetch failed.")
            return nil
        }
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
              let events = json["events"] as? [[String: Any]] else {
            DiagnosticsLog.warning("interests", "Sports headline fetch failed.", details: ["team": team ?? "none"])
            return nil
        }

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
        content.userInfo = [
            "handoffCategory": "immediate",
            "handoffMessage": body.isEmpty ? "You tapped my notification. I'm here - what should we do with it?" : body,
            "shouldSpeak": true
        ]

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
