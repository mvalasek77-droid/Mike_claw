import UIKit
import UserNotifications

/// Minimal UIKit shim so we can hook the APNs registration callbacks — SwiftUI
/// doesn't expose `didRegisterForRemoteNotificationsWithDeviceToken` any other
/// way. Injected at app root via `@UIApplicationDelegateAdaptor` (see
/// `AuctionBabyApp.swift`).
///
/// Its only job is to forward the raw device token to `PushService.shared`,
/// which handles hex-encoding, buffering until a session is available, and
/// the actual POST to the auth Worker.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions:
                     [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Foreground alerts too — otherwise iOS eats the banner while the app
        // is open, which is worse UX than a subtle banner.
        UNUserNotificationCenter.current().delegate = PushService.shared
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.receivedDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushService.shared.failedToRegister(error)
    }
}
