import SwiftUI

@main
struct WatchfighterApp: App {
    init() {
        CrashMonitor.install()
    }

    var body: some Scene {
        WindowGroup {
            GameScreen()
        }
    }
}
