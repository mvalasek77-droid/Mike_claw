import SwiftUI

/// The Standing — weekly cosmetic leaderboards for the user's city. Two lists:
/// top bidders (sorted by Auction Credit) and most-contested lots (sorted by
/// Showcase Credit). Client-computed, deterministic per-week. Auction Baby's
/// most on-brand retention lever: the whole app is about rank.
struct StandingView: View {
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    section(title: "Top bidders",
                            subtitle: "Ranked by Auction Credit — the floor keeps score.",
                            icon: "trophy.fill",
                            entries: store.topBiddersInCity,
                            tint: Theme.gold)
                    section(title: "Most-contested lots",
                            subtitle: "Ranked by Showcase Credit — the lots the floor is watching.",
                            icon: "flame.fill",
                            entries: store.mostContestedLots,
                            tint: Theme.rose)
                    footer
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 8)
            }
            .background(AppBackground())
            .navigationTitle("The Standing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.gold)
                }
            }
        }
    }

    private var header: some View {
        GlassCard(tint: Theme.gold) {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black).frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.goldGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week of \(store.currentWeekLabel)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.inkFaint)
                    Text(store.me.location.isEmpty ? "The Floor" : store.me.location)
                        .font(.system(size: 20, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.gold)
                }
                Spacer()
            }
        }
    }

    private func section(title: String, subtitle: String, icon: String,
                         entries: [AuctionStore.StandingEntry],
                         tint: Color) -> some View {
        GlassCard(title: title, icon: icon, tint: tint) {
            Text(subtitle)
                .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            if entries.isEmpty {
                Text("Nothing to rank yet this week.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { rank, entry in
                        row(rank: rank + 1, entry: entry, tint: tint)
                    }
                }
            }
        }
    }

    private func row(rank: Int, entry: AuctionStore.StandingEntry, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(rank == 1 ? tint : Theme.inkSoft)
                .frame(width: 22, alignment: .center)
            AvatarCircle(name: entry.name, hue: entry.hue,
                         photoName: entry.photoName, photoData: entry.photoData, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.system(size: 14, weight: .heavy, design: .serif))
                        .foregroundStyle(Theme.ink)
                    if entry.isYou {
                        Text("YOU").font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(tint))
                    }
                }
                Text(entry.subtitle).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            Text("\(entry.value)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.vertical, 4)
        .background(
            entry.isYou
                ? RoundedRectangle(cornerRadius: Theme.cornerS).fill(tint.opacity(0.08))
                : nil
        )
    }

    private var footer: some View {
        Text("Cosmetic only. Ranks refresh every week from your Auction Credit and Showcase score — nothing you do here can move them directly.")
            .font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}
