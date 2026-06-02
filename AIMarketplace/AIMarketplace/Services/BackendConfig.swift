import Foundation

/// Build-time-baked backend configuration.
///
/// The Worker URL and the app↔Worker shared secret are read from `Info.plist`
/// so a creator who downloads the app from the App Store NEVER has to know
/// what a Cloudflare Worker is. Their Stripe-onboarding flow is one tap →
/// Safari → done.
///
/// The two keys in `Info.plist` are:
///   • `AIMKT_WORKER_URL`     — full https URL of the deployed Worker
///   • `AIMKT_SHARED_SECRET`  — must match APP_SHARED_SECRET on the Worker
///
/// They ship as empty strings in the repo. **Fill them in before archiving
/// for the App Store** by editing `Info.plist` directly, or (cleaner) by
/// setting them as user-defined build settings + xcconfig that
/// substitutes `$(AIMKT_WORKER_URL)` / `$(AIMKT_SHARED_SECRET)` at build
/// time, so the actual values never sit in git.
///
/// Caveat (same as every "shared secret embedded in a mobile app" design):
/// a jailbroken device can extract the value from the IPA. That matches the
/// current security posture; the longer-term move is per-user bearer tokens
/// issued by the Worker after a server-side auth handshake. For launch, the
/// shared secret + a rate-limited Worker is fine.
enum BackendConfig {
    static var workerURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "AIMKT_WORKER_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var sharedSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "AIMKT_SHARED_SECRET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// True iff a Worker has been wired into the build. The Payout-Setup
    /// admin panel checks this to decide whether to show its config card.
    static var isBundled: Bool { !workerURL.isEmpty && !sharedSecret.isEmpty }
}
