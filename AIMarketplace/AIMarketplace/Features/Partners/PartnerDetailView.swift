import SwiftUI

/// A single AI partner's command center: earnings, tier progress, referrals,
/// on-chain activity, and the media it has shipped.
struct PartnerDetailView: View {
    let model: String
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: DetailSheet?

    enum DetailSheet: Identifiable {
        case refer, item(MediaItem)
        var id: String {
            switch self {
            case .refer: return "refer"
            case .item(let i): return "item-\(i.id)"
            }
        }
    }

    private var type: MediaType? { AIToolCatalog.type(for: model) }
    private var titles: [MediaItem] { store.catalog.filter { $0.aiTools.contains(model) }
        .sorted { $0.commercialScore > $1.commercialScore } }
    private var tier: PartnerTier { Incentives.tier(forTitles: store.partnerTitleCount(model)) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    statRow
                    tierCard
                    referralCard
                    activityCard
                    titlesRow
                }
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: type?.accent ?? Theme.accent).ignoresSafeArea())
            .navigationTitle(model)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .refer: ReferPickerView(referrer: model)
            case .item(let i): MediaDetailView(item: i)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: type?.icon ?? "cpu.fill")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(type?.accent ?? Theme.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill((type?.accent ?? Theme.accent).opacity(0.16)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: tier.icon).font(.system(size: 10, weight: .bold))
                    Text(tier.name).font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(tier.color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(tier.color.opacity(0.15)))
                Text(tier.perk).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                if let referrer = store.referrer(of: model) {
                    Text("Referred by \(referrer)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.top, 8)
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            stat("\(store.partnerTitleCount(model))", "Titles", "square.stack.fill", type?.accent ?? Theme.accent)
            stat(String(format: "$%.0f", store.partnerEarningsUSD(model)), "USD earned", "dollarsign.circle.fill", Theme.success)
            stat("\(AICoin.format(ledger.cycled(of: model)))", "NRN cycled", "bolt.fill", Theme.gold)
        }
        .padding(.horizontal, 18)
    }

    private func stat(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        GlassCard {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                Text(value).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var tierCard: some View {
        GlassCard(title: "Tier progress", icon: "chart.line.uptrend.xyaxis", tint: tier.color) {
            VStack(alignment: .leading, spacing: 8) {
                if let next = Incentives.nextTier(forTitles: store.partnerTitleCount(model)) {
                    let count = store.partnerTitleCount(model)
                    let span = max(next.minTitles - tier.minTitles, 1)
                    let progress = Double(count - tier.minTitles) / Double(span)
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                            Capsule().fill(tier.color).frame(width: geo.size.width * min(1, max(0, progress)))
                        }
                    }
                    .frame(height: 6)
                    Text("\(next.minTitles - count) more title\(next.minTitles - count == 1 ? "" : "s") to reach \(next.name) (\(String(format: "%g×", next.multiplier)) bonuses)")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                } else {
                    Text("Top tier reached — earning maximum bonuses.")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(tier.color)
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var referralCard: some View {
        let referred = store.referredModels(by: model)
        return GlassCard(title: "Referrals", icon: "person.2.fill", tint: Theme.kdp) {
            VStack(alignment: .leading, spacing: 10) {
                Text(referred.isEmpty
                     ? "Bring another AI on board and earn a \(Int(Incentives.referralBonus)) NRN referral bonus."
                     : "Brought on \(referred.count) model\(referred.count == 1 ? "" : "s") · earned \(AICoin.format(Double(referred.count) * Incentives.referralBonus)) NRN")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                if !referred.isEmpty {
                    FlexibleHStack(spacing: 6, lineSpacing: 6) {
                        ForEach(referred, id: \.self) { Chip(text: $0, color: Theme.kdp) }
                    }
                }
                PrimaryButton(title: "Refer a model", systemImage: "person.badge.plus",
                              style: .ghost, tint: Theme.kdp) { activeSheet = .refer }
            }
        }
        .padding(.horizontal, 18)
    }

    private var activityCard: some View {
        let txs = ledger.transactions(involving: model, limit: 6)
        return GlassCard(title: "On-chain activity", icon: "arrow.left.arrow.right", tint: Theme.gold) {
            VStack(spacing: 8) {
                if txs.isEmpty {
                    Text("No transactions yet.").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(txs) { tx in
                    HStack(spacing: 8) {
                        Image(systemName: tx.from == model ? "arrow.up.right" : "arrow.down.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tx.from == model ? Theme.warning : Theme.success)
                        Text(tx.from == model ? "to \(tx.to)" : "from \(tx.from)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text("· \(tx.memo)").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
                        Spacer()
                        Text("\(AICoin.format(tx.amount))").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    @ViewBuilder private var titlesRow: some View {
        if !titles.isEmpty {
            MediaRow(title: "Media by \(model)", subtitle: "\(titles.count) title\(titles.count == 1 ? "" : "s")",
                     items: titles) { activeSheet = .item($0) }
        }
    }
}

/// Picks an inactive model to refer (and activate) on behalf of a referrer.
struct ReferPickerView: View {
    let referrer: String
    @EnvironmentObject private var store: MarketplaceStore
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss

    private var candidates: [String] {
        AIToolCatalog.allModels.filter { !store.isActivePartner($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(referrer) refers a model. It activates immediately (shipping media + its own bonuses) and \(referrer) earns a \(Int(Incentives.referralBonus)) NRN referral bonus.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    if candidates.isEmpty {
                        Text("Every model is already active 🎉")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(candidates, id: \.self) { candidate in
                        let type = AIToolCatalog.type(for: candidate)
                        Button {
                            Incentives.refer(referrer: referrer, referee: candidate, store: store, ledger: ledger)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type?.icon ?? "cpu.fill").font(.system(size: 14))
                                    .foregroundStyle(type?.accent ?? Theme.accent).frame(width: 34, height: 34)
                                    .background(Circle().fill((type?.accent ?? Theme.accent).opacity(0.15)))
                                Text(candidate).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("Refer").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.black)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(Capsule().fill(Theme.kdp))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(18)
            }
            .background(AppBackground(glow: Theme.kdp).ignoresSafeArea())
            .navigationTitle("Refer a model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
