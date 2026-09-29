import Foundation

/// Launch arguments the UI tests use to start the app from a known state.
/// Debug builds only — none of this exists in a Release binary.
enum UITestSupport {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    static var isUITesting: Bool { arguments.contains("-uiTesting") }

    /// Must run before any service singleton is created.
    static func prepareIfNeeded() {
        guard isUITesting else { return }
        if arguments.contains("-resetState") {
            for name in ["portfolio.json", "open_orders.json", "social.json", "catalog.json"] {
                try? FileManager.default.removeItem(
                    at: URL.applicationSupportDirectory.appendingPathComponent(name))
            }
            if let id = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: id)
            }
        }
        if arguments.contains("-skipIntro") {
            UserDefaults.standard.set(true, forKey: "passedAgeGate")
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }
    #else
    static let isUITesting = false
    static func prepareIfNeeded() {}
    #endif
}
