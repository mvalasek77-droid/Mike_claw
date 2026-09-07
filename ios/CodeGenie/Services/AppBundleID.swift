import Foundation

/// The one place an app's bundle ID is decided.
///
/// It used to be derived in two screens independently, and the value
/// they produced matched nothing: the generated Xcode project carried
/// whatever identifier the model wrote, so the app was signed as one
/// thing and uploaded to App Store Connect as another. Apple rejects
/// that every time, with an error that reads like the build is broken.
///
/// Now one value comes from here, goes to the backend with the build
/// so the project is pinned to it, and is reused for the App Store
/// Connect record, signing, the upload, and TestFlight polling.
enum AppBundleID {

    /// Used when the user hasn't set a prefix of their own yet.
    ///
    /// Deliberately obviously-placeholder. A bundle ID must be unique
    /// across the whole App Store, so a shared prefix means the first
    /// person to ship a "Tides" app owns `com.codegenie.tides` and
    /// everyone after them is refused.
    static let fallbackPrefix = "com.codegenie"

    /// `prefix.appslug`, e.g. `com.jane.tidetimes`.
    static func make(prefix: String, title: String) -> String {
        let cleanPrefix = normalise(prefix: prefix)
        return "\(cleanPrefix).\(slug(title))"
    }

    @MainActor
    static func make(title: String, credentials: Credentials? = nil) -> String {
        make(prefix: (credentials ?? .shared).bundleIDPrefix, title: title)
    }

    /// True when the user still has the placeholder prefix, so screens
    /// can nudge them before Apple does.
    @MainActor
    static func usesFallbackPrefix(credentials: Credentials? = nil) -> Bool {
        normalise(prefix: (credentials ?? .shared).bundleIDPrefix) == fallbackPrefix
    }

    /// Is what the user actually typed a usable prefix?
    ///
    /// Checked against the raw input rather than the result of
    /// `make(prefix:title:)`, because that normalises away every
    /// disallowed character and falls back to the shared prefix — so
    /// validating its output always said "fine" and silently turned
    /// "com bad name!" into "combadname" without telling anyone.
    ///
    /// Empty is allowed: it means "use the shared prefix", which the
    /// settings screen warns about separately.
    static func isValidPrefix(_ prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix(".") || trimmed.hasSuffix(".") { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    // MARK: - Internals

    private static func normalise(prefix: String) -> String {
        let trimmed = prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty else { return fallbackPrefix }
        // Keep only what Apple accepts, so a typed-in prefix can't
        // produce an identifier that fails at upload.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        let collapsed = filtered
            .split(separator: ".", omittingEmptySubsequences: true)
            .joined(separator: ".")
        return collapsed.isEmpty ? fallbackPrefix : collapsed
    }

    private static func slug(_ title: String) -> String {
        let s = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        return s.isEmpty ? "app" : s
    }
}
