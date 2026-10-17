import SwiftUI

@main
struct WatchsmashApp: App {
    init() {
        CrashMonitor.install()
    }

    var body: some Scene {
        WindowGroup {
            GameScreen()
        }
    }
}
