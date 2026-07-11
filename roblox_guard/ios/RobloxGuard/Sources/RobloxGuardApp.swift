import SwiftUI

@main
struct RobloxGuardApp: App {
    @StateObject private var store = Store()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(store)
            } else {
                ConsentOnboardingView {
                    hasCompletedOnboarding = true
                }
                .environmentObject(store)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "shield.lefthalf.filled") }
            ResourcesView()
                .tabItem { Label("Get Help", systemImage: "lifepreserver") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await store.loadAll() }
    }
}
