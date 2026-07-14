import Foundation

/// Build-time-baked backend configuration.
///
/// The Worker URL and the app↔Worker shared secret are read from `Info.plist`,
/// which itself references `$(AB_WORKER_URL)` and `$(AB_SHARED_SECRET)` build
/// settings. Those settings come from `Config/Secrets.xcconfig` (untracked;
/// see `Config/Secrets.xcconfig.example` for the template).
///
/// A fresh checkout without `Secrets.xcconfig` still compiles — the plist gets
/// empty strings, and `BackendConfig.isBundled` returns false; the admin
/// backend view already handles that state by showing an "unconfigured" card.
///
/// **Provisioning steps:** copy `Config/Secrets.xcconfig.example` to
/// `Config/Secrets.xcconfig`, paste the deployed Worker URL and the shared
/// secret you set with `wrangler secret put APP_SHARED_SECRET`, rebuild.
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
