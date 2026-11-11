import Foundation

/// How this launch was started.
///
/// The only switch is for automated UI tests, and it exists only in
/// debug builds. A release build has no way to reach the simulated
/// builder: showing a person a build that did not happen is the one
/// thing this app must never do.
enum AppEnvironment {

    static let isUITesting: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UITests")
        #else
        return false
        #endif
    }()

    /// Honour `-resetDefaults`, which the test suite passes to start
    /// from a clean install. Must run before anything reads defaults.
    static func prepareForLaunch() {
        #if DEBUG
        guard isUITesting else { return }
        // A half-typed description is kept between launches for real
        // users; between tests it would leak one test's typing into
        // the next.
        if !ProcessInfo.processInfo.arguments.contains("-keepDrafts") {
            UserDefaults.standard.removeObject(forKey: "describe.draft.title")
            UserDefaults.standard.removeObject(forKey: "describe.draft.prompt")
        }
        guard ProcessInfo.processInfo.arguments.contains("-resetDefaults"),
              let domain = Bundle.main.bundleIdentifier
        else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
        #endif
    }
}
