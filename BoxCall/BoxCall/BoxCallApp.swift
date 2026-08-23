import SwiftUI

@main
struct BoxCallApp: App {
    @StateObject private var market = MarketService.shared
    @StateObject private var portfolio = PortfolioService.shared
    @StateObject private var social = SocialService.shared
    @StateObject private var rewards = RewardsService.shared
    @StateObject private var notifications = NotificationsService.shared
    @StateObject private var coordinator = TradeCoordinator.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var auth = AuthService.shared

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("passedAgeGate") private var passedAgeGate: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !passedAgeGate {
                    AgeGateView(passed: $passedAgeGate)
                } else if hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView(hasCompleted: $hasCompletedOnboarding)
                }
            }
            .environmentObject(market)
            .environmentObject(portfolio)
            .environmentObject(social)
            .environmentObject(rewards)
            .environmentObject(notifications)
            .environmentObject(coordinator)
            .environmentObject(store)
            .environmentObject(auth)
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) { RewardToastOverlay() }
            .task {
                AnalyticsService.shared.installCrashHandler()
                AnalyticsService.shared.track(.appOpen)
                Haptics.warmUp()
                if hasCompletedOnboarding { notifications.requestAuthorizationIfNeeded() }
                market.startMarket()
                await market.refreshCatalog()
                market.startAutoRefresh()
                WidgetSyncService.sync()
            }
            .sheet(item: $coordinator.pendingCopy) { intent in
                TradeSheet(contract: intent.contract, movie: intent.movie)
            }
        }
    }
}

struct RewardToastOverlay: View {
    @EnvironmentObject var rewards: RewardsService
    var body: some View {
        if let toast = rewards.lastToast {
            HStack(spacing: 10) {
                Text(toast.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title).font(.subheadline.weight(.bold))
                    Text(toast.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(Theme.Space.md)
            .glassSurface(radius: Theme.Radius.md,
                          stroke: Theme.accent.opacity(0.35))
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.sm)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                removal: .move(edge: .top).combined(with: .opacity)))
            .animation(Theme.Motion.toast, value: toast.id)
            .task(id: toast.id) {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation(Theme.Motion.toast) { rewards.dismissToast() }
            }
        }
    }
}
