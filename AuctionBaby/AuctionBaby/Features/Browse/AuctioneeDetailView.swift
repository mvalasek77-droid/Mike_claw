import SwiftUI

/// Full profile for a woman on the floor: her always-visible photo, prompts,
/// interests, reviews, and her Showcase score — plus the bid CTA.
struct AuctioneeDetailView: View {
    let woman: Profile
    var onBid: () -> Void
    @EnvironmentObject private var storeKit: StoreKitService
    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false
    @State private var bidPrompt: Prompt?

    private var hasReserve: Bool {
        guard let tier = storeKit.activeTier else { return false }
        return tier == .reserve || tier == .blackcard
    }

    private static func formatHeight(_ cm: Int) -> String {
        let totalInches = Double(cm) / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        return "\(feet)′\(inches)″"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    AvatarView(name: woman.name, hue: woman.hue, photoName: woman.photoName,
                               corner: Theme.cornerXL)
                        .frame(height: 380)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                        .frame(height: 380).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(woman.name).font(.system(size: 30, weight: .heavy, design: .serif))
                            if woman.verified { VerifiedBadge(size: 20) }
                            Text("\(woman.age)").font(.system(size: 22, design: .serif)).foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            ArtTierBadge(tier: woman.artTier, compact: true)
                        }
                        .foregroundStyle(Theme.ink)
                        Text(woman.location).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous))

                if !woman.bio.isEmpty {
                    GlassCard(title: "About", icon: "text.quote") {
                        Text(woman.bio).font(.system(size: 15)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if hasReserve, let reserve = woman.startingBid {
                    GlassSurface(corner: Theme.cornerL, tint: Theme.gold) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill").font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Her reserve price").font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.inkFaint)
                                Text(Money.full(reserve))
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.gold)
                            }
                            Spacer()
                            Chip(text: "Reserve perk", systemImage: "lock.open.fill", color: Theme.rose)
                        }
                        .padding(14)
                    }
                }

                ForEach(woman.prompts) { prompt in
                    GlassSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            PromptBubble(prompt: prompt)
                            Button { bidPrompt = prompt } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.raised.fill")
                                    Text("Bid on this answer")
                                    Spacer()
                                }
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.rose)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.rose.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                    }
                }

                if !woman.interests.isEmpty {
                    GlassCard(title: "Interests", icon: "sparkles") {
                        FlexLayout { ForEach(woman.interests, id: \.self) { Chip(text: $0, color: Theme.rose) } }
                    }
                }

                if woman.hasAnyLifestyle {
                    GlassCard(title: "Lifestyle", icon: "person.text.rectangle") {
                        FlexLayout {
                            if let h = woman.lifestyle.heightCm { Chip(text: Self.formatHeight(h), systemImage: "ruler", color: Theme.gold) }
                            if let v = woman.lifestyle.smoking { Chip(text: "Smokes: \(v.rawValue)", systemImage: "smoke", color: Theme.inkFaint) }
                            if let v = woman.lifestyle.drinking { Chip(text: "Drinks: \(v.rawValue)", systemImage: "wineglass", color: Theme.inkFaint) }
                            if let v = woman.lifestyle.kids { Chip(text: v.rawValue, systemImage: "figure.and.child.holdinghands", color: Theme.rose) }
                            if let v = woman.lifestyle.education { Chip(text: v.rawValue, systemImage: "graduationcap", color: Theme.verify) }
                        }
                    }
                }

                ShowcaseScoreCard(woman: woman)

                CreditReportCard(title: "Showcase report", factors: woman.showcaseFactors, tint: Theme.rose)

                if !woman.reviews.isEmpty {
                    GlassCard(title: "Date reviews", icon: "star.bubble.fill", tint: Theme.gold) {
                        VStack(spacing: 12) {
                            ForEach(woman.reviews) { ReviewRow(review: $0) }
                        }
                    }
                }

                Spacer(minLength: 90)
            }
            .screenPadding()
            .padding(.top, 8)
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { showReport = true } label: {
                        Label("Report & Block", systemImage: "flag")
                    }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.inkSoft) }
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(profile: woman) { dismiss() }.presentationDetents([.medium, .large])
        }
        .sheet(item: $bidPrompt) { prompt in
            BidSheet(woman: woman, promptContext: prompt)
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: woman.startingBid.map { "Bid · floor \(Money.compact($0))" } ?? "Place a bid",
                          systemImage: "hand.raised.fill") {
                onBid()
            }
            .screenPadding()
            .padding(.bottom, 8)
            .background(LinearGradient(colors: [.clear, Theme.bg], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// Her Showcase score + per-trait breakdown.
struct ShowcaseScoreCard: View {
    let woman: Profile
    var body: some View {
        GlassCard(title: "Showcase Credit", icon: "rosette", tint: Theme.rose) {
            HStack(alignment: .center, spacing: 16) {
                ScoreGauge(value: woman.showcaseCredit, range: 300...900, label: woman.showcaseTier,
                           tint: Theme.rose, size: 116)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        StarRow(value: woman.overallStars)
                        Text(woman.reviews.isEmpty ? "New" : String(format: "%.1f", woman.overallStars))
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    }
                    Text("Market value")
                        .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.inkFaint)
                    Text(Money.compact(woman.marketValue))
                        .font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                }
                Spacer(minLength: 0)
            }
            if !woman.traitAverages.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Trait.allCases) { trait in
                        if let v = woman.traitAverages[trait] {
                            StatBar(label: trait.rawValue, value: v, tint: Theme.rose)
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

/// A single date review row, adapts to direction (trait review vs deadbeat verdict).
struct ReviewRow: View {
    let review: DateReview
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarCircle(name: review.authorName, hue: review.authorHue, size: 30)
                Text(review.authorName).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                if review.gavelConfirmed {
                    Label("Gavel Confirmed", systemImage: "checkmark.seal.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.verify)
                        .accessibilityLabel("Gavel Confirmed date")
                }
                Spacer()
                if let paid = review.paidBid {
                    DeadbeatTag(score: paid ? 100 : 10, compact: true)
                } else {
                    StarRow(value: Double(review.stars), size: 11)
                }
            }
            Text(review.text).font(.system(size: 13)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if !review.interestCategories.isEmpty {
                FlexLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(review.interestCategories, id: \.self) {
                        Chip(text: $0, systemImage: "tag.fill", color: Theme.gold)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.04)))
    }
}
