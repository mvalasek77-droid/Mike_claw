import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .chat
    @State private var showSettings = false
    @State private var showNewChat = false

    enum Tab { case chat, tools, settings }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                ConversationListView(showNewChat: $showNewChat)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                    .tag(Tab.chat)

                MCPServersView()
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                    .tag(Tab.tools)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(.green)
        }
        .onAppear {
            Task { await appState.refreshTools() }
            if appState.apiKey.isEmpty { selectedTab = .settings }
        }
    }
}
