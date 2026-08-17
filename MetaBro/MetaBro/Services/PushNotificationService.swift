import Foundation

/// Authorization + device-token registration for push notifications. The
/// actual delivery of new-message/friend-request/notification pushes happens
/// server-side; the client's job is just to ask permission and hand over a token.
protocol PushNotificationService: Sendable {
    /// Prompts the system permission dialog (a no-op the second time it's granted/denied).
    @discardableResult
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    func registerDeviceToken(_ token: String) async throws
}

/// Always "grants" permission and discards tokens — keeps the demo/offline
/// build push-aware without needing a real APNs round trip.
actor MockPushNotificationService: PushNotificationService {
    private var authorized = false

    func requestAuthorization() async -> Bool {
        authorized = true
        return true
    }

    func isAuthorized() async -> Bool {
        authorized
    }

    func registerDeviceToken(_ token: String) async throws {
        BroLog.info("Registered mock device token: \(token)", category: "push")
    }
}
