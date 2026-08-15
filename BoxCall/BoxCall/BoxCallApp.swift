import SwiftUI

@main
struct BoxCallApp: App {
    @StateObject private var market = MarketService.shared
    @StateObject private var portfolio = PortfolioService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(market)
                .environmentObject(portfolio)
                .preferredColorScheme(.dark)
        }
    }
}
