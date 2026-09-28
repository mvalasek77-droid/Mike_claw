import SwiftUI

/// Invite friends to play. No coin reward: invites can't be verified without
/// a server, and coins that don't come from trading would muddy the
/// profit-only leaderboard.
struct ReferralView: View {
    @EnvironmentObject var portfolio: PortfolioService

    private var message: String {
        let rank = portfolio.myRank.map { " I'm #\($0) in profit." } ?? ""
        return "I'm calling opening weekends on BoxCall as @\(portfolio.user.handle).\(rank) Think you can out-trade me? It's free and all play money."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Challenge your friends.")
                    .font(.title2.bold())
                Text("Send BoxCall to your group chat and see who really knows the box office. Everyone starts with the same 1,000 RC stake, and the leaderboard only counts trading profit — so the only way past you is to out-call you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.08)))
                Button {
                    Sharer.share(Text(message), message: message)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .primaryActionStyle()
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle("Challenge friends")
        .navigationBarTitleDisplayMode(.inline)
    }
}
