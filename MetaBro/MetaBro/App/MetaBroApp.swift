import SwiftUI

@main
struct MetaBroApp: App {
    init() {
        CrashReporter.install()
        if let lastCrash = CrashReporter.lastCrash() {
            BroLog.error("Previous session ended in an uncaught exception:\n\(lastCrash)", category: "crash")
            CrashReporter.clear()
        }
    }

    var body: some Scene {
        WindowGroup {
            LaunchGateView()
                .task { HapticsEngine.shared.prepare() }
        }
    }
}
