import Foundation

/// Build-time-baked backend configuration.
///
/// The Worker URL and the app↔Worker shared secret are read from `Info.plist`
/// so a user who downloads the app from the App Store never has to know what
/// a Cloudflare Worker is.
///
/// The two keys in `Info.plist` are:
///   • `AB_WORKER_URL`     — full https URL of the deployed payout Worker
///   • `AB_SHARED_SECRET`  — must match APP_SHARED_SECRET on the Worker
///
/// They ship as empty strings in the repo. **Fill them in before archiving
/// for the App Store** by editing `Info.plist` directly, or (cleaner) via
/// user-defined build settings + an xcconfig that substitutes
/// `$(AB_WORKER_URL)` / `$(AB_SHARED_SECRET)` at build time, so the actual
/// values never sit in git.
///
/// Caveat (same as every "shared secret embedded in a mobile app" design):
/// a jailbroken device can extract the value from the IPA. The Worker's
/// rate limits are the mitigating rail; the longer-term move is per-user
/// bearer tokens issued after a server-side auth handshake.
enum BackendConfig {
    static var workerURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "AB_WORKER_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var sharedSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "AB_SHARED_SECRET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// True iff a Worker has been wired into the build. The admin backend
    /// panel checks this to decide whether the config card needs attention.
    static var isBundled: Bool { !workerURL.isEmpty && !sharedSecret.isEmpty }
}
