import Foundation

/// Resolves whether MetaBro talks to a live backend or runs on in-memory mocks.
///
/// Values come from the app's Info.plist (substituted from `Config/Build.xcconfig`
/// at build time):
///   • `METABRO_API_BASE_URL` — e.g. https://api.metabro.app/v1
///   • `METABRO_USE_LIVE`     — "YES" to use the live backend
///
/// Missing or malformed values mean "use mocks", so the app always launches and
/// is fully interactive even with nothing configured.
struct BackendConfig {
    let baseURL: URL?
    let useLive: Bool

    /// Live mode requires both the flag *and* a valid URL.
    var resolvedBaseURL: URL? { useLive ? baseURL : nil }

    init(bundle: Bundle = .main) {
        let raw = (bundle.object(forInfoDictionaryKey: "METABRO_API_BASE_URL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = raw.flatMap { $0.isEmpty ? nil : URL(string: $0) }

        let flag = (bundle.object(forInfoDictionaryKey: "METABRO_USE_LIVE") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.useLive = (flag == "YES" || flag == "1" || flag == "TRUE")
    }

    /// Explicit init for tests.
    init(baseURL: URL?, useLive: Bool) {
        self.baseURL = baseURL
        self.useLive = useLive
    }
}
