import SwiftUI

/// Subscription badge (ticket / star / crown) shown next to the player's own
/// name. It marks a paid membership — never trading skill, which is what the
/// earned rank beside it shows.
/// Marks a trader the app simulates. There's no server, so every other
/// name on the leaderboard, in the feed and on spotlighted reviews is one
/// of BoxCall's automated rivals — and the app says so wherever it shows one.
struct SimulatedTag: View {
    var body: some View {
        Text("SIM")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.6)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(Capsule().stroke(.secondary.opacity(0.6), lineWidth: 0.75))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Simulated trader")
    }
}

struct MemberFlair: View {
    @ObservedObject var portfolio = PortfolioService.shared

    var body: some View {
        let m = portfolio.user.membership
        if let icon = m.badgeIcon {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(m.accentColor)
                .accessibilityLabel("\(m.displayName) member")
        }
    }
}
