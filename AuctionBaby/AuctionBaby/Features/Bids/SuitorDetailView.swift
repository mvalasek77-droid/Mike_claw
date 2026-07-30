import SwiftUI

/// The full dossier on a bidder, from the lot's side. His reputation is an open
/// book — Auction Credit, deadbeat history, archetype, reviews — but his face
/// stays frosted until she accepts.
struct SuitorDetailView: View {
    let bid: Bid
    @EnvironmentObject private var store: AuctionStore
    @EnvironmentObject private var matching: MatchingService
    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false

    // Slice 4b1b: route through the matching Worker when the bid came from
    // the real inbox; fall back to the sim `accept`/`decline` otherwise.
    private func doAccept() {
        Task { await store.acceptRemote(bid, matching: matching) }
        dismiss()
    }
    private func doDecline() {
        Task { await store.declineRemote(bid, matching: matching) }
        dismiss()
    }

    private var man: Profile { bid.man }
    private var accepted: Bool { bid.status == .accepted }

    var body: some View {
        // A whisper is anonymous by contract — the dossier below would leak
        // his archetype, credit, reviews and a nonsensical "$0 bid" CTA.
        if bid.isWhisper {
            whisperBody
        } else {
            dossierBody
        }
    }

    /// Anonymous whisper sheet: no identity signals, just the nod choice.
    private var whisperBody: some View {
        VStack(spacing: 20) {
            Capsule().fill(Theme.hairline).frame(width: 38, height: 5).padding(.top, 8)
            Spacer(minLength: 8)
            AvatarCircle(name: "?", hue: 0.85, size: 84, locked: true)
            VStack(spacing: 6) {
                Text("Someone whispered")
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("A whisper is an anonymous nod — no name, no number, no strings. Nod back and he'll return with a real bid; let it fade and he'll never know you saw it.")
                    .font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if bid.status == .pending {
                HStack(spacing: 12) {
                    GhostButton(title: "Let it fade", systemImage: "xmark") { doDecline() }
                    PrimaryButton(title: "Nod back", systemImage: "hand.wave.fill",
                                  gradient: Theme.roseGradient) {
                        // acceptRemote special-cases whispers server-side —
                        // it calls nodRemoteWhisper for the correct response
                        // shape; sim path stays local via the same method.
                        doAccept()
                    }
                }
                .screenPadding()
            } else {
                Text(bid.status == .accepted ? "You nodded back." : "It faded.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppBackground().opacity(0.5))
    }

    private var dossierBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    Capsule().fill(Theme.hairline).frame(width: 38, height: 5)
                    HStack {
                        Spacer()
                        Menu {
                            Button(role: .destructive) { showReport = true } label: {
                                Label("Report & Block", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.system(size: 18))
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .padding(.top, 8)

                AvatarView(name: man.name, hue: man.hue, photoName: man.photoName, locked: !accepted, corner: Theme.cornerXL)
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
                        ArchetypeBadge(archetype: man.archetype, pending: man.showsPendingTrillionaire)
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
                        ScoreGauge(value: man.auctionCredit, range: 300...900, label: man.creditTier,
                                   tint: Theme.gold, size: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            if man.verified {
                                StatPill(icon: "checkmark.seal.fill", label: "identity", value: "Verified", tint: Theme.verify)
                            }
                            DeadbeatTag(score: man.deadbeatScore)
                            StatPill(icon: "calendar", label: "dates", value: "\(man.datesCompleted)", tint: Theme.rose)
                            if man.copycatBids > 0 {
                                StatPill(icon: "sparkles", label: "copycat bids", value: "\(man.copycatBids)", tint: Theme.copycat)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                CreditReportCard(title: "Credit report", factors: man.creditFactors)

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
        .sheet(isPresented: $showReport) {
            ReportSheet(profile: man) { dismiss() }.presentationDetents([.medium, .large])
        }
        .safeAreaInset(edge: .bottom) {
            if bid.status == .pending {
                HStack(spacing: 12) {
                    GhostButton(title: "Pass", systemImage: "xmark") { doDecline() }
                    PrimaryButton(title: "Accept \(Money.compact(bid.amount))", systemImage: "checkmark",
                                  gradient: Theme.roseGradient) { doAccept() }
                }
                .screenPadding().padding(.bottom, 8)
                .background(LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}
