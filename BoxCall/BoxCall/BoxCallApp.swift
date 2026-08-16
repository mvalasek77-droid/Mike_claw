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

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
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
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) { RewardToastOverlay() }
            .task {
                if hasCompletedOnboarding { notifications.requestAuthorizationIfNeeded() }
                market.startMarket()
                await market.refreshCatalog()
                market.startAutoRefresh()
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { rewards.dismissToast() }
            }
        }
    }
}
