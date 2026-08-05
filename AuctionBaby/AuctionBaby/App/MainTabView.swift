import SwiftUI
import UIKit

/// Role-aware tab bar. The bidder browses a floor and shops for status; the lot
/// works an inbox of bids. Matches and Profile are shared.
struct MainTabView: View {
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var push: PushService
    @State private var selection = 0
    /// Programmatic navigation path for the Matches tab. A push tap on a
    /// `message.received` event appends the match UUID so the chat opens
    /// immediately; the user presses Back to pop it.
    @State private var matchNavPath: [UUID] = []

    var body: some View {
        TabView(selection: $selection) {
            if store.role == .man {
                AuctionFeedView()
                    .tabItem { Label("Floor", systemImage: "rectangle.stack.fill") }
                    .tag(0)
                MyBidsView()
                    .tabItem { Label("My Bids", systemImage: "hand.raised.fill") }
                    .tag(4)
                ArchetypeStoreView()
                    .tabItem { Label("Status", systemImage: "crown.fill") }
                    .tag(1)
            } else {
                IncomingBidsView()
                    .tabItem { Label("Bids", systemImage: "hand.raised.fill") }
                    .tag(0)
            }

            MatchesView(navPath: $matchNavPath)
                .tabItem { Label("Matches", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(2)

            MyProfileView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                .tag(3)
        }
        .tint(Theme.gold)
        .onChange(of: push.deepLinkEvent) { _, event in
            guard let event else { return }
            defer { push.deepLinkEvent = nil }
            switch event {
            case .bidReceived:
                // Woman's inbox = tag 0; bidder's My Bids = tag 4
                selection = store.role == .man ? 4 : 0
            case .whisperNodded:
                selection = 4  // bidder's My Bids — his whisper was nodded
            case .bidAccepted:
                selection = 2  // Matches tab — a new match just opened
            case .messageReceived(let matchIdStr, _):
                selection = 2
                if let str = matchIdStr, let id = UUID(uuidString: str) {
                    matchNavPath = [id]
                }
            case .matchDateDone:
                selection = 2  // Matches tab — rate-the-date prompt
            case .verified, .other:
                break
            }
        }
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
