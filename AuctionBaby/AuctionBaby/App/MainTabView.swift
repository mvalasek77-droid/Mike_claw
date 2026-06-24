import SwiftUI
import UIKit

/// Role-aware tab bar. The bidder browses a floor and shops for status; the lot
/// works an inbox of bids. Matches and Profile are shared.
struct MainTabView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            if store.role == .man {
                AuctionFeedView()
                    .tabItem { Label("Floor", systemImage: "rectangle.stack.fill") }
                    .tag(0)
                ArchetypeStoreView()
                    .tabItem { Label("Status", systemImage: "crown.fill") }
                    .tag(1)
            } else {
                IncomingBidsView()
                    .tabItem { Label("Bids", systemImage: "hand.raised.fill") }
                    .tag(0)
            }

            MatchesView()
                .tabItem { Label("Matches", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)

            MyProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .tint(Theme.gold)
        .onAppear {
            // Keep the tab bar legible over the dark gallery background.
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            appearance.backgroundColor = UIColor(Theme.bg).withAlphaComponent(0.85)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
