import Foundation
import UserNotifications
import SwiftUI

/// Local notifications + permission flow. iOS will deliver these even when
/// the app is backgrounded, which is what the prior "in-app inbox only"
/// design was missing — creators were leaving the app and never coming back
/// because sales arrived silently. This handles the in-app side; APNs / push
/// would also need a real server-side certificate and is wired separately.
@MainActor
final class LocalNotificationService {
    static let shared = LocalNotificationService()
    private init() {}

    enum Category: String {
        case sale          // a buyer purchased a creator title
        case payout        // Stripe transfer settled or failed
        case reviewDone    // AI Editor finished a verdict
        case scoutLanded   // Scout produced new content for the creator
        case reportResolved // operator resolved a report this device submitted
    }

    /// Asks once for delivery permission. iOS dedupes; safe to call repeatedly.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        guard current.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Fire-and-forget delivery. No-op silently if permission was denied.
    func fire(_ category: Category, title: String, body: String, deepLink: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        if let deepLink {
            content.userInfo = ["deepLink": deepLink.absoluteString]
        }
        // Immediate delivery (1s trigger so iOS schedules it).
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
