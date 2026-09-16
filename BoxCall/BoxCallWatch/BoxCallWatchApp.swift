import SwiftUI
import WatchConnectivity

@main
struct BoxCallWatchApp: App {
    @StateObject private var bridge = WatchBridge.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(bridge)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { bridge.refresh() }
                }
        }
    }
}
