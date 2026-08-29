import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Marquee", systemImage: "flame") }
            MovieListView()
                .tabItem { Label("Now Showing", systemImage: "film") }
            PortfolioView()
                .tabItem { Label("Positions", systemImage: "chart.line.uptrend.xyaxis") }
            LeaderboardView()
                .tabItem { Label("Box Office", systemImage: "trophy") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Theme.marqueeGold)
        .background(Theme.stageBlack.ignoresSafeArea())
    }
}
