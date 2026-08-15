import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            MovieListView()
                .tabItem { Label("Slate", systemImage: "film") }
            PortfolioView()
                .tabItem { Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis") }
            LeaderboardView()
                .tabItem { Label("Leaders", systemImage: "trophy") }
        }
        .tint(.orange)
    }
}
