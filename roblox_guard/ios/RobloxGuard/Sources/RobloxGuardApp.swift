import SwiftUI

@main
struct RobloxGuardApp: App {
    @StateObject private var store = Store()
    @StateObject private var purchases = PurchaseManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(store)
                    .environmentObject(purchases)
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
    @EnvironmentObject var purchases: PurchaseManager

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
        .task { await purchases.start() }
    }
}
