import SwiftUI

@main
struct RobloxGuardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store()
    @StateObject private var purchases = PurchaseManager()
    @StateObject private var push = PushManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environmentObject(store)
                    .environmentObject(purchases)
                    .environmentObject(push)
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
    @EnvironmentObject var push: PushManager

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
        .task {
            push.configure(api: store.api)
            await push.refreshStatus()
        }
    }
}
