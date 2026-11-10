import Foundation

// The conveniences that read the saved prefix. Kept apart from
// `AppBundleID` itself so the rules there stay free of app state.
extension AppBundleID {

    @MainActor
    static func make(title: String, credentials: Credentials? = nil) -> String {
        make(prefix: (credentials ?? .shared).bundleIDPrefix, title: title)
    }

    @MainActor
    static func usesFallbackPrefix(credentials: Credentials? = nil) -> Bool {
        usesFallback(prefix: (credentials ?? .shared).bundleIDPrefix)
    }
}
