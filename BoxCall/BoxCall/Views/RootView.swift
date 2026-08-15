import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Feed", systemImage: "flame") }
            MovieListView()
                .tabItem { Label("Slate", systemImage: "film") }
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis") }
            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.orange)
    }
}
