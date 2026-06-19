import SwiftUI

@main
struct MetaBroApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .task { HapticsEngine.shared.prepare() }
        }
    }
}
