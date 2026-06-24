import SwiftUI

/// The user's own profile and live "credit score" — Auction Credit for bidders,
/// Showcase score for lots — plus reviews and account settings.
struct MyProfileView: View {
    @EnvironmentObject private var store: AuctionStore
    @State private var editingBid = false
    @State private var bidText = ""
    @State private var showReset = false

    private var me: Profile { store.me }
    private var isMan: Bool { store.role == .man }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if isMan { manStats } else { womanStats }
                    if !me.reviews.isEmpty {
                        GlassCard(title: isMan ? "What dates said about you" : "What bidders said",
                                  icon: "star.bubble.fill", tint: Theme.gold) {
                            VStack(spacing: 12) { ForEach(me.reviews) { ReviewRow(review: $0) } }
                        }
                    }
                    settingsCard
                    Text("Auction Baby · demo build · v1.0").font(.system(size: 11))
                        .foregroundStyle(Theme.inkFaint)
                    Spacer(minLength: 24)
                }
                .screenPadding().padding(.top, 6)
            }
            .background(AppBackground())
            .navigationTitle("You")
            .alert("Reset account?", isPresented: $showReset) {
                Button("Reset", role: .destructive) { store.resetAccount() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Clears your profile, bids, matches and reviews, and returns to onboarding.") }
        }
    }

    private var headerCard: some View {
        GlassSurface(corner: Theme.cornerXL) {
            VStack(spacing: 0) {
                AvatarView(name: me.name, hue: me.hue, corner: Theme.cornerXL)
                    .frame(height: 260)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(me.name.isEmpty ? "You" : me.name)
                                    .font(.system(size: 28, weight: .heavy, design: .serif))
                                Text("\(me.age)").font(.system(size: 20, design: .serif)).foregroundStyle(Theme.inkSoft)
                            }.foregroundStyle(Theme.ink)
                            HStack(spacing: 8) {
                                Chip(text: me.role.sideTitle, systemImage: me.role.systemImage,
                                     color: isMan ? Theme.gold : Theme.rose)
                                if me.masterpiece { MasterpieceBadge(compact: true) }
                            }
                        }.padding(16)
                    }
                if !me.bio.isEmpty {
                    Text(me.bio).font(.system(size: 14)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
        }
    }

    // MARK: Man stats

    private var manStats: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Auction Credit", icon: "creditcard.fill", tint: Theme.gold) {
                HStack(spacing: 16) {
                    ScoreGauge(value: me.auctionCredit, range: 300...850, label: me.creditTier, tint: Theme.gold, size: 124)
                    VStack(alignment: .leading, spacing: 10) {
                        ArchetypeBadge(archetype: me.archetype)
                        DeadbeatTag(score: me.deadbeatScore)
                        StatPill(icon: "calendar", label: "dates", value: "\(me.datesCompleted)", tint: Theme.rose)
                        if me.copycatBids > 0 {
                            StatPill(icon: "sparkles", label: "copycat bids", value: "\(me.copycatBids)", tint: Theme.copycat)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let next = me.archetype.next {
                    Divider().overlay(Theme.hairline)
                    HStack {
                        Text("Next tier: \(next.title)").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text(Money.compact(next.price)).font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    // MARK: Woman stats

    private var womanStats: some View {
        VStack(spacing: 16) {
            GlassCard(title: "Showcase score", icon: "rosette", tint: Theme.rose) {
                HStack(spacing: 16) {
                    ScoreGauge(value: me.showcaseScore, range: 0...100, label: "Showcase", tint: Theme.rose, size: 124)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Market value").font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.inkFaint)
                        Text(Money.compact(me.marketValue)).font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        StarRow(value: me.overallStars)
                        StatPill(icon: "dollarsign.circle.fill", label: "accepted", value: Money.compact(store.earnings), tint: Theme.rose)
                    }
                    Spacer(minLength: 0)
                }
                if !me.traitAverages.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Trait.allCases) { t in
                            if let v = me.traitAverages[t] { StatBar(label: t.rawValue, value: v, tint: Theme.rose) }
                        }
                    }.padding(.top, 4)
                }
            }

            GlassCard(title: "Your floor", icon: "dollarsign.circle.fill", tint: Theme.gold) {
                if editingBid {
                    HStack {
                        TextField("", text: $bidText,
                                  prompt: Text("e.g. 250").foregroundStyle(Theme.inkFaint))
                            .keyboardType(.numberPad).textFieldStyle(.plain)
                            .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                            .padding(10).background(RoundedRectangle(cornerRadius: Theme.cornerS).fill(.white.opacity(0.06)))
                        Button("Save") {
                            store.setStartingBid(bidText.isEmpty ? nil : Int(bidText))
                            Haptics.commit(); editingBid = false
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(Theme.goldGradient))
                        Button("Clear") { store.setStartingBid(nil); bidText = ""; editingBid = false }
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSoft)
                    }
                } else {
                    HStack {
                        Text(me.startingBid.map { Money.full($0) } ?? "No floor — open bidding")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(me.startingBid == nil ? Theme.rose : Theme.gold)
                        Spacer()
                        Button { bidText = me.startingBid.map(String.init) ?? ""; editingBid = true } label: {
                            Label("Edit", systemImage: "pencil").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        GlassCard(title: "Settings", icon: "gearshape.fill") {
            HStack {
                Text("Reduce Motion / Dark Mode honoured system-wide")
                    .font(.system(size: 12)).foregroundStyle(Theme.inkFaint)
                Spacer()
            }
            Button(role: .destructive) { showReset = true } label: {
                Label("Reset account", systemImage: "trash")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.danger.opacity(0.12)))
            }
        }
    }
}
