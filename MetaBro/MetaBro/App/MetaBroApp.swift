import SwiftUI

@main
struct MetaBroApp: App {
    @State private var container = AppContainer.live()

    init() {
        CrashReporter.install()
        if let lastCrash = CrashReporter.lastCrash() {
            BroLog.error("Previous session ended in an uncaught exception:\n\(lastCrash)", category: "crash")
            CrashReporter.clear()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .task { HapticsEngine.shared.prepare() }
        }
    }
}
