import SwiftUI

/// Subscription badge (ticket / star / crown) shown next to the player's own
/// name. It marks a paid membership — never trading skill, which is what the
/// earned rank beside it shows.
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
