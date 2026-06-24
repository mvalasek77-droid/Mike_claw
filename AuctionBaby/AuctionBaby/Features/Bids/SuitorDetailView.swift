import SwiftUI

/// The full dossier on a bidder, from the lot's side. His reputation is an open
/// book — Auction Credit, deadbeat history, archetype, reviews — but his face
/// stays frosted until she accepts.
struct SuitorDetailView: View {
    let bid: Bid
    @EnvironmentObject private var store: AuctionStore
    @Environment(\.dismiss) private var dismiss

    private var man: Profile { bid.man }
    private var accepted: Bool { bid.status == .accepted }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 8)

                AvatarView(name: man.name, hue: man.hue, locked: !accepted, corner: Theme.cornerXL)
                    .frame(height: 300)
                    .overlay(alignment: .bottomLeading) {
                        if accepted {
                            VStack(alignment: .leading) {
                                Text(man.name).font(.system(size: 26, weight: .heavy, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                Text("\(man.age) · \(man.location)").font(.system(size: 13))
                                    .foregroundStyle(Theme.inkSoft)
                            }.padding(16)
                        }
                    }

                // The bid headline.
                GlassCard(tint: Theme.gold) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("His bid").font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.inkFaint)
                            Text(Money.full(bid.amount)).font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.gold)
                        }
                        Spacer()
                        ArchetypeBadge(archetype: man.archetype)
                    }
                    if bid.qualifiesForMasterpiece {
                        HStack(spacing: 8) {
                            MasterpieceBadge(compact: true)
                            Text("Accept & complete this date to mint your Masterpiece.")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                    }
                    if !bid.note.isEmpty {
                        Text("“\(bid.note)”").font(.system(size: 14)).italic().foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Credit dossier.
                GlassCard(title: "Reputation", icon: "checkmark.shield.fill") {
                    HStack(spacing: 16) {
                        ScoreGauge(value: man.auctionCredit, range: 300...850, label: man.creditTier,
                                   tint: Theme.gold, size: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            DeadbeatTag(score: man.deadbeatScore)
                            StatPill(icon: "calendar", label: "dates", value: "\(man.datesCompleted)", tint: Theme.rose)
                            if man.copycatBids > 0 {
                                StatPill(icon: "sparkles", label: "copycat bids", value: "\(man.copycatBids)", tint: Theme.copycat)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                if accepted, !man.bio.isEmpty {
                    GlassCard(title: "About", icon: "text.quote") {
                        Text(man.bio).font(.system(size: 15)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(man.prompts) { p in GlassSurface { PromptBubble(prompt: p).padding(4) } }
                } else if !accepted {
                    GlassCard(tint: Theme.gold) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").foregroundStyle(Theme.gold)
                            Text("His photo, bio and prompts unlock the moment you accept.")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                    }
                }

                if !man.reviews.isEmpty {
                    GlassCard(title: "What dates said", icon: "star.bubble.fill", tint: Theme.gold) {
                        VStack(spacing: 12) { ForEach(man.reviews) { ReviewRow(review: $0) } }
                    }
                }

                Spacer(minLength: 90)
            }
            .screenPadding()
        }
        .background(AppBackground().opacity(0.5))
        .safeAreaInset(edge: .bottom) {
            if bid.status == .pending {
                HStack(spacing: 12) {
                    GhostButton(title: "Pass", systemImage: "xmark") { store.decline(bid); dismiss() }
                    PrimaryButton(title: "Accept \(Money.compact(bid.amount))", systemImage: "checkmark",
                                  gradient: Theme.roseGradient) {
                        store.accept(bid); dismiss()
                    }
                }
                .screenPadding().padding(.bottom, 8)
                .background(LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}
