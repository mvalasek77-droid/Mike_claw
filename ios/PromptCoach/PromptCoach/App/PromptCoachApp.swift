import SwiftUI

@main
struct PromptCoachApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RambleView()
                .environmentObject(app)
                .tint(Glass.accent)
        }
    }
}
