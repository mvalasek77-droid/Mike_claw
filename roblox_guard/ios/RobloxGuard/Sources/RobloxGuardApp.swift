import SwiftUI
import UIKit

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

/// Custom tab bar container that guarantees the tab bar is always visible.
/// SwiftUI's TabView on iOS 26 can auto-hide the tab bar during scroll,
/// trapping users with no way to navigate. This custom implementation
/// uses a VStack with the content on top and a fixed tab bar on the bottom,
/// so the parent can always reach Home / Get Help / Settings from anywhere.
struct MainTabView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var purchases: PurchaseManager
    @EnvironmentObject var push: PushManager
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Content area — fills all available space above the tab bar
            ZStack {
                switch selectedTab {
                case 0:
                    DashboardView()
                case 1:
                    ResourcesView()
                case 2:
                    SettingsView()
                default:
                    DashboardView()
                }
            }

            // Fixed tab bar — always visible, never hidden by scroll
            CustomTabBar(selectedTab: $selectedTab)
        }
        .task { await store.loadAll() }
        .task { await purchases.start() }
        .task {
            push.configure(api: store.api)
            await push.refreshStatus()
        }
    }
}

/// Persistent bottom tab bar with Home, Get Help, and Settings.
/// The Home tab ensures the user can always return to the Dashboard
/// from any screen in the app.
struct CustomTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "Home", icon: "house.fill", tag: 0)
            tabButton(title: "Get Help", icon: "lifepreserver", tag: 1)
            tabButton(title: "Settings", icon: "gearshape", tag: 2)
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .padding(.bottom, safeAreaBottom)
    }

    private var safeAreaBottom: CGFloat {
        // Account for the home indicator on devices without a home button
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
            Haptics.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(height: 28)
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tag ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tag ? .isSelected : [])
    }
}