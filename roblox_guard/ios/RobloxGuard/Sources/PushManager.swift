import UIKit
import UserNotifications

extension Notification.Name {
    static let rgDeviceTokenReceived = Notification.Name("rgDeviceTokenReceived")
    static let rgDeviceTokenRegistrationFailed = Notification.Name("rgDeviceTokenRegistrationFailed")
}

/// UIKit only calls didRegisterForRemoteNotificationsWithDeviceToken on an
/// app delegate — there's no SwiftUI-native equivalent — so this exists
/// purely to forward that one callback into PushManager via NotificationCenter.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .rgDeviceTokenReceived, object: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .rgDeviceTokenRegistrationFailed, object: error)
    }
}

/// Push notifications for watch/elevated alerts — the whole point is hearing
/// about a threat without having the app open. Getting a device token
/// registered with APNs and the backend is a three-step relay: request OS
/// permission -> UIKit hands us a device token via AppDelegate -> we send
/// that token to POST /devices/register so the backend's monitor loop
/// (monitor.py's _push_alert) knows where to deliver.
@MainActor
final class PushManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isRegistered = false
    @Published var errorMessage: String?

    private var api: APIClient?
    private var observers: [NSObjectProtocol] = []

    func configure(api: APIClient) {
        self.api = api
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: .rgDeviceTokenReceived, object: nil, queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { await self?.register(token: token) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .rgDeviceTokenRegistrationFailed, object: nil, queue: .main
        ) { [weak self] note in
            let message = (note.object as? Error)?.localizedDescription
            Task { @MainActor [weak self] in
                self?.errorMessage = message
            }
        })
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            authorizationStatus = granted ? .authorized : .denied
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            errorMessage = error.localizedDescription
            authorizationStatus = .denied
        }
    }

    private func register(token: String) async {
        guard let api else { return }
        do {
            try await api.registerDevice(token: token)
            isRegistered = true
            errorMessage = nil
        } catch {
            isRegistered = false
            errorMessage = error.localizedDescription
        }
    }
}
