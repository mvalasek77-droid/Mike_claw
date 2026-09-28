import SwiftUI

struct RootView: View {
    private enum Tab: Hashable { case marquee, nowShowing, positions, boxOffice, profile }
    @State private var tab: Tab = .marquee

    var body: some View {
        TabView(selection: $tab) {
            FeedView()
                .tabItem { Label("Marquee", systemImage: "flame") }
                .tag(Tab.marquee)
            MovieListView()
                .tabItem { Label("Now Showing", systemImage: "film") }
                .tag(Tab.nowShowing)
            PortfolioView()
                .tabItem { Label("Positions", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.positions)
            LeaderboardView()
                .tabItem { Label("Box Office", systemImage: "trophy") }
                .tag(Tab.boxOffice)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Theme.marqueeGold)
        .sensoryFeedback(.selection, trigger: tab)
        .background(Theme.stageBlack.ignoresSafeArea())
    }
}
