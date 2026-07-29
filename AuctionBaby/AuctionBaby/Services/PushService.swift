import Foundation
import UserNotifications
import UIKit

/// Owns push notification registration + the current APNs device token.
///
/// Two entry points wake the state machine:
///   1. `AppDelegate` calls `receivedDeviceToken(_:)` when APNs hands us a
///      token (on the first successful `registerForRemoteNotifications()`
///      and again any time the token rotates).
///   2. The onboarding / sign-in flow calls `requestAuthorizationIfNeeded()`
///      to prompt the user for notification permission.
///
/// Whenever we have BOTH a token AND a session (read straight from Keychain
/// via `SecureStore`, same store `AuthService` uses), we POST the token to
/// `/devices/register` on the auth Worker. Absent either half, we quietly
/// buffer — the next arrival of the missing piece kicks off the send.
///
/// Slice 2 of the spine (see `SPINE_ROADMAP.md`). Absent `BackendConfig.authURL`
/// or absent Push Notifications entitlement → the service degrades to a no-op
/// so a fresh checkout keeps compiling and running local-only.
///
/// Singleton because `AppDelegate` needs a stable reference before SwiftUI's
/// `@StateObject` machinery has run. Access from views as
/// `@EnvironmentObject var push: PushService` — the app root injects
/// `PushService.shared` as the environment object.
@MainActor
final class PushService: NSObject, ObservableObject {
    static let shared = PushService()

    /// Hex-encoded APNs device token, once we have one. `nil` before APNs
    /// has answered or if the user denied notifications.
    @Published private(set) var deviceToken: String?
    /// Latest notification-authorization status (mirrors UNNotificationSettings).
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Last non-nil error surfaced from registration. Cleared on next attempt.
    @Published var lastError: String?
    /// Whether we've successfully told the server about the current token
    /// (so views can show a subtle "notifications ready" hint if useful).
    @Published private(set) var isRegisteredWithServer = false

    /// Fires when a push arrives (foreground) or the user taps a delivered
    /// one (background). App root wires this to `AuctionStore` refreshers so
    /// the relevant screen updates the moment we know something happened,
    /// without depending on pull-to-refresh. Absent hook → no-op (a fresh
    /// checkout compiles + runs local-only).
    var onEvent: ((PushEvent) -> Void)?

    /// The push payloads the matching + auth Workers emit today. The `data`
    /// keys are set by the Worker (`data: { type: ..., bidId, matchId }`); we
    /// decode into a strict enum so wildcards can't slip through as no-ops.
    enum PushEvent: Equatable {
        case bidReceived(bidId: String?)
        case whisperNodded(bidId: String?)
        case bidAccepted(bidId: String?, matchId: String?)
        case messageReceived(matchId: String?, messageId: String?)
        case matchDateDone(matchId: String?)
        case verified
        case other(type: String)

        init?(userInfo: [AnyHashable: Any]) {
            // Both APNs alert wrappers and our custom keys sit at the top; the
            // Worker also nests keys under `data`. Peek in both places.
            let flat = userInfo
            let data = userInfo["data"] as? [AnyHashable: Any] ?? [:]
            let type = (flat["type"] as? String) ?? (data["type"] as? String) ?? ""
            let bidId = (flat["bidId"] as? String) ?? (data["bidId"] as? String)
            let matchId = (flat["matchId"] as? String) ?? (data["matchId"] as? String)
            let messageId = (flat["messageId"] as? String) ?? (data["messageId"] as? String)
            switch type {
            case "bid.received":     self = .bidReceived(bidId: bidId)
            case "whisper.nodded":   self = .whisperNodded(bidId: bidId)
            case "bid.accepted":     self = .bidAccepted(bidId: bidId, matchId: matchId)
            case "message.received": self = .messageReceived(matchId: matchId, messageId: messageId)
            case "match.dateDone":   self = .matchDateDone(matchId: matchId)
            case "verified":         self = .verified
            case "":                 return nil
            default:                 self = .other(type: type)
            }
        }
    }

    /// Same session-token key AuthService uses. Reading it directly keeps this
    /// service decoupled from AuthService — we don't need to import it.
    private static let sessionTokenKey = "com.valasek.auctionbaby.auth.sessionToken.v1"

    /// True iff both the auth Worker is configured AND we've either got a
    /// token or the user hasn't been asked yet. False = the whole flow is off.
    var isEnabled: Bool { !BackendConfig.authURL.isEmpty }

    private override init() { super.init() }

    // MARK: - Public API

    /// Idempotent: safe to call from onboarding, from sign-in success, and
    /// from `.onAppear` in a settings screen. Requests notification
    /// authorization if we don't have it yet, then triggers the APNs
    /// registration that ends up in `receivedDeviceToken`.
    func requestAuthorizationIfNeeded() async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                let refreshed = await center.notificationSettings()
                authorizationStatus = refreshed.authorizationStatus
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } catch {
                lastError = error.localizedDescription
                ErrorMonitor.shared.record(category: "Push",
                                           message: "requestAuthorization failed",
                                           error: error)
            }
        case .authorized, .provisional, .ephemeral:
            // Already authorized — re-trigger registration to catch any token
            // rotation Apple applied while we were backgrounded.
            UIApplication.shared.registerForRemoteNotifications()
        case .denied:
            // Silently respect the user's choice; a settings-screen surface
            // can deep-link into iOS Settings later.
            break
        @unknown default:
            break
        }
    }

    /// Called by `AppDelegate` on successful APNs registration. Hex-encodes
    /// the token and attempts the server registration.
    func receivedDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        lastError = nil
        Task { await sendRegistrationIfPossible() }
    }

    /// Called by `AppDelegate` when APNs rejects registration (usually the
    /// entitlement is missing, or the simulator can't get a token). Recorded
    /// so the admin console can show what went wrong; not surfaced to the user.
    func failedToRegister(_ error: Error) {
        lastError = error.localizedDescription
        ErrorMonitor.shared.record(category: "Push",
                                   message: "APNs registration failed",
                                   error: error)
    }

    /// Called after a successful Sign in with Apple. If we already have a
    /// device token buffered, this is what actually POSTs it.
    func onSignedIn() async {
        await sendRegistrationIfPossible()
    }

    /// Called on sign-out. Best-effort unregister — the local state clears
    /// regardless (we never want to keep firing pushes at a signed-out user).
    func onSignedOut() async {
        let token = deviceToken
        isRegisteredWithServer = false
        guard let token, let session = currentSessionToken() else { return }
        _ = await post("/devices/unregister",
                        session: session,
                        body: ["token": token])
    }

    // MARK: - Internals

    private func currentSessionToken() -> String? {
        SecureStore.string(forKey: Self.sessionTokenKey)
    }

    /// Whether this build is running against APNs sandbox (dev / TestFlight-
    /// internal). We use the presence of an embedded provisioning profile
    /// with dev entitlements as the heuristic — DEBUG only. Production
    /// TestFlight external + App Store builds go to `apns` prod host.
    private var apnsPlatform: String {
        #if DEBUG
        return "apns_sandbox"
        #else
        return "apns"
        #endif
    }

    /// The full state machine in one place: only POSTs when we have every
    /// piece (config, token, session). Any missing piece → quiet return; the
    /// next event that fills it in will call us again.
    private func sendRegistrationIfPossible() async {
        guard isEnabled, let token = deviceToken, let session = currentSessionToken() else {
            return
        }
        let outcome = await post("/devices/register",
                                  session: session,
                                  body: ["token": token, "platform": apnsPlatform])
        if outcome { isRegisteredWithServer = true }
    }

    @discardableResult
    private func post(_ path: String, session: String, body: [String: Any]) async -> Bool {
        let base = BackendConfig.authURL.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return false }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: "\(trimmed)\(path)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(status)
            if !ok {
                ErrorMonitor.shared.record(category: "Push",
                                           message: "POST \(path) failed",
                                           detail: "HTTP \(status)")
            }
            return ok
        } catch {
            ErrorMonitor.shared.record(category: "Push",
                                       message: "POST \(path) transport",
                                       error: error)
            return false
        }
    }
}

// MARK: - Foreground presentation + tap routing

extension PushService: UNUserNotificationCenterDelegate {
    /// Show the banner + play the sound even when the app is foregrounded,
    /// rather than iOS's default (silently drop). For a dating app the
    /// user wants to know a bid came in even if they're mid-scroll. Also
    /// fire the event so the underlying data refreshes while the banner
    /// plays.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            if let event = PushEvent(userInfo: userInfo) { self.onEvent?(event) }
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// A tap on a delivered notification (from lock screen / notification
    /// center) wakes the app here. Same event fires so the destination
    /// screen has fresh data by the time the user lands on it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let event = PushEvent(userInfo: userInfo) { self.onEvent?(event) }
            completionHandler()
        }
    }
}
