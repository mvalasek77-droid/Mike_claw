import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var social: SocialService
    @State private var showPaywall = false

    var user: User { portfolio.user }
    var myReviews: [Review] {
        social.reviews.filter { $0.authorIsCurrentUser }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identityCard
                    AuthCard()
                    membershipCard
                    tierProgressCard
                    statsRow
                    badgeShelf
                    trophyShelf
                    perksCard
                    reviewsBlock
                    learnLinks
                }
                .padding()
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    private var membershipCard: some View {
        let m = user.membership
        return HStack(spacing: 12) {
            Image(systemName: m.isPaid ? "star.circle.fill" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(m.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(m.accentColor)
                Text("\(Int(m.weeklyAllowance)) RC weekly · same rules for every \(m.displayName) member")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showPaywall = true
            } label: {
                Text(m.isPaid ? "Manage" : "Upgrade")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(m.accentColor)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(m.accentColor.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(m.accentColor.opacity(m.isPaid ? 0.5 : 0.15), lineWidth: 1)
        )
    }

    private var reviewsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your reviews").font(.headline)
                Spacer()
                if myReviews.isEmpty == false {
                    Text("\(myReviews.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if myReviews.isEmpty {
                Text("Write a review from any movie's detail page. Land in the top-5 leaderboard and your latest gets spotlighted on the Feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            } else {
                ForEach(myReviews.prefix(3)) { r in
                    HStack(spacing: 8) {
                        Text(r.moviePosterEmoji).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.movieTitle).font(.subheadline.weight(.semibold))
                            Text(r.headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(r.stars).font(.caption2).foregroundStyle(.yellow)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                }
            }
        }
    }

    private var learnLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Learn the game").font(.headline)
            NavigationLink {
                LearnView()
            } label: {
                learnRow(icon: "book.pages", title: "How BoxCall works",
                         subtitle: "The full guide — Calls, Puts, strikes, settlement, rewards.")
            }
            NavigationLink {
                LearnView(initialSection: .whatsACall)
            } label: {
                learnRow(icon: "arrow.up.right.circle", title: "Calls explained",
                         subtitle: "Bullish bets, payoff diagram, worked example.")
            }
            NavigationLink {
                LearnView(initialSection: .whatsAPut)
            } label: {
                learnRow(icon: "arrow.down.right.circle", title: "Puts explained",
                         subtitle: "Bearish bets, payoff diagram, worked example.")
            }
            NavigationLink {
                LearnView(initialSection: .losingCoins)
            } label: {
                learnRow(icon: "exclamationmark.shield", title: "Losing coins",
                         subtitle: "What happens when a trade goes wrong. Max loss, weekly refills, no negative balance.")
            }
            NavigationLink {
                DataSourcesView()
            } label: {
                learnRow(icon: "server.rack", title: "Data sources",
                         subtitle: "Where the catalog and settlement numbers come from. TMDB, Box Office Mojo, and more.")
            }
            NavigationLink {
                BlockedUsersView()
            } label: {
                learnRow(icon: "hand.raised", title: "Blocked users",
                         subtitle: "Manage the handles whose posts, reviews, and comments won't show up in your feed.")
            }
            NavigationLink {
                LearnView(initialSection: .glossary)
            } label: {
                learnRow(icon: "text.book.closed", title: "Glossary",
                         subtitle: "Strike, premium, IV, DTE, mark, and more.")
            }
        }
    }

    private func learnRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.orange).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(user.tier.color.opacity(0.25))
                    .frame(width: 72, height: 72)
                Text(String(user.handle.prefix(1)).uppercased())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(user.tier.color)
            }
            .overlay(
                Circle()
                    .stroke(user.tier.color, lineWidth: user.tier >= .producer ? 3 : 0)
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("@\(user.handle)")
                        .font(.title3.bold())
                        .foregroundStyle(user.tier >= .insider ? Color.yellow : .primary)
                    if user.tier >= .analyst {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(user.tier.color)
                    }
                }
                HStack(spacing: 6) {
                    Text(user.tier.name)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(user.tier.color.opacity(0.25)))
                        .foregroundStyle(user.tier.color)
                    Text("· \(user.followerCount) followers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(user.bio).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var tierProgressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(user.xp) XP")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                if let next = Tier(rawValue: user.tier.rawValue + 1) {
                    Text("\(next.minXP - user.xp) to \(next.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Max tier reached")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ProgressView(value: user.tierProgress)
                .tint(user.tier.color)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("Streak", "\(user.currentStreakWeeks)w", subtitle: "best \(user.longestStreakWeeks)w", color: .orange)
            stat("Lifetime P&L", String(format: "%+.0f", user.lifetimePnL), subtitle: "RC", color: user.lifetimePnL >= 0 ? .green : .red)
            stat("Following", "\(user.followingHandles.count)", subtitle: "traders", color: .blue)
        }
    }

    private func stat(_ label: String, _ value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var badgeShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Badges").font(.headline)
            if user.badges.isEmpty {
                Text("Make winning calls to earn badges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 12) {
                    ForEach(user.badges) { badge in
                        VStack(spacing: 4) {
                            Text(badge.emoji).font(.system(size: 34))
                            Text(badge.name).font(.caption2.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                }
            }
        }
    }

    private var trophyShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trophies").font(.headline)
            if user.trophies.isEmpty {
                Text("Finish #1 in a season to earn a trophy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(user.trophies, id: \.self) { t in
                    HStack {
                        Image(systemName: "trophy.fill").foregroundStyle(.orange)
                        Text(t).font(.callout.weight(.semibold))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                }
            }
        }
    }

    private var perksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(user.tier.name) perks").font(.headline)
            ForEach(user.tier.perks, id: \.self) { perk in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(user.tier.color)
                    Text(perk).font(.callout)
                }
            }
            if let next = Tier(rawValue: user.tier.rawValue + 1) {
                Divider().padding(.vertical, 4)
                Text("Unlock at \(next.name):")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(next.perks, id: \.self) { perk in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock").foregroundStyle(.secondary)
                        Text(perk).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(user.tier.color.opacity(0.08)))
    }
}
