import Foundation
import UserNotifications
import Combine

/// Local-notification driver + in-app notification inbox.
/// A real product would swap the local scheduling for APNs pushes
/// from the server that runs Monday settlement.
final class NotificationsService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsService()

    @Published private(set) var inbox: [InboxItem] = []
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var unreadCount: Int { inbox.filter { !$0.isRead }.count }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
    }

    // MARK: - Permission

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else {
                DispatchQueue.main.async {
                    self?.authorizationStatus = settings.authorizationStatus
                }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            ) { _, _ in
                DispatchQueue.main.async { self?.refreshAuthorizationStatus() }
            }
        }
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: - Public API

    func notifySettlement(movie: Movie, position: Position, actual: Double, net: Double) {
        let win = net > 0
        let title = win ? "🎯 \(movie.title) — you called it" : "\(movie.title) settled"
        let body = "Opened at $\(String(format: "%.1f", actual))M. Your \(position.side.display) at $\(Int(position.strikeMillions))M netted \(String(format: "%+.0f", net)) RC."
        deliver(id: "settle_\(position.id.uuidString)", title: title, body: body,
                kind: .settlement(movieId: movie.id, positive: win))
    }

    func notifyFollowers(gained: Int) {
        guard gained > 0 else { return }
        let title = "\(gained) new follower\(gained == 1 ? "" : "s")"
        let body = "Your last winning call caught eyes on the feed."
        deliver(id: "followers_\(UUID().uuidString)", title: title, body: body, kind: .follower)
    }

    func notifyBadge(_ badge: Badge) {
        deliver(id: "badge_\(badge.id)",
                title: "\(badge.emoji) Badge unlocked: \(badge.name)",
                body: badge.blurb,
                kind: .badge(badgeId: badge.id))
    }

    func notifyTier(_ tier: Tier) {
        deliver(id: "tier_\(tier.rawValue)",
                title: "You're now a \(tier.name).",
                body: tier.perks.first ?? "New perks unlocked.",
                kind: .tier(tier: tier))
    }

    func notifyComment(fromHandle handle: String, movieTitle: String) {
        deliver(id: "cmt_\(UUID().uuidString)",
                title: "@\(handle) replied to your call",
                body: "On \(movieTitle).",
                kind: .comment(handle: handle))
    }

    /// Reminder scheduled at trade placement, 24h before release.
    func scheduleOpeningReminder(movie: Movie, position: Position) {
        let fireDate = movie.releaseDate.addingTimeInterval(-24 * 3600)
        guard fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "🎬 \(movie.title) opens tomorrow"
        content.body = "Your \(position.side.display) at $\(Int(position.strikeMillions))M is live. Consensus: $\(Int(movie.consensusOpeningMillions))M."
        content.sound = .default
        content.userInfo = ["movieId": movie.id]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(
            identifier: "open_\(position.id.uuidString)",
            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)

        // Also drop an inbox item now so users see the reminder is armed.
        appendInbox(.init(
            id: "reminder_\(position.id.uuidString)",
            title: "Reminder set",
            body: "We'll ping you 24h before \(movie.title) opens.",
            kind: .reminder(movieId: movie.id),
            createdAt: Date(),
            isRead: false
        ))
    }

    // MARK: - Delivery

    private func deliver(id: String, title: String, body: String, kind: InboxItem.Kind) {
        appendInbox(.init(id: id, title: title, body: body, kind: kind, createdAt: Date(), isRead: false))

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "\(id)_\(UUID().uuidString.prefix(6))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private func appendInbox(_ item: InboxItem) {
        inbox.insert(item, at: 0)
        if inbox.count > 100 { inbox = Array(inbox.prefix(100)) }
    }

    func markAllRead() {
        inbox = inbox.map { var i = $0; i.isRead = true; return i }
    }

    func markRead(id: String) {
        guard let idx = inbox.firstIndex(where: { $0.id == id }) else { return }
        inbox[idx].isRead = true
    }

    // Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct InboxItem: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let kind: Kind
    let createdAt: Date
    var isRead: Bool

    enum Kind: Hashable {
        case settlement(movieId: String, positive: Bool)
        case follower
        case badge(badgeId: String)
        case tier(tier: Tier)
        case comment(handle: String)
        case reminder(movieId: String)

        var emoji: String {
            switch self {
            case .settlement(_, let pos): return pos ? "🎯" : "📉"
            case .follower:               return "👥"
            case .badge:                  return "🏅"
            case .tier:                   return "⭐️"
            case .comment:                return "💬"
            case .reminder:               return "🎬"
            }
        }
    }
}
