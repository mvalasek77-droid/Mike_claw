import SwiftUI

@main
struct MetaBroApp: App {
    init() {
        // Size the shared URL cache generously so avatar + post images stay
        // in memory across scroll, and are served from disk on re-launch
        // without a network round-trip.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50 MB in-memory
            diskCapacity:  200 * 1024 * 1024,   // 200 MB on-disk
            diskPath: "com.valasek.metabro.urlcache"
        )

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
