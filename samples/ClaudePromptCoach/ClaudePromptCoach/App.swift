import SwiftUI

@main
struct ClaudePromptCoachApp: App {
    @StateObject private var store = SkillStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            CoachHomeView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
    }
}
