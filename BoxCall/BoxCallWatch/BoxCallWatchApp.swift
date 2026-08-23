import SwiftUI
import WatchConnectivity

@main
struct BoxCallWatchApp: App {
    @StateObject private var bridge = WatchBridge.shared
    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(bridge)
        }
    }
}
