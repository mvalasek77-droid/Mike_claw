#if os(watchOS)
import SwiftUI

@main
struct WatchFighterApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
        }
    }
}
#endif
