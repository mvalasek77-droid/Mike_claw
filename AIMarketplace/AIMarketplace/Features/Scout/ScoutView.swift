import SwiftUI

/// The Scout — the agent that hunts down AI-made media, briefs AIs on what the
/// market and user requests demand, tells them they can earn USD here, and (when
/// the creator isn't posting) delivers a premium daily slate: a film, an album,
/// a novel at 95–100% commercial, plus one experimental piece.
struct ScoutView: View {
    @EnvironmentObject private var store: MarketplaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: MediaItem?

    private var openRequests: [ContentRequest] {
        store.requests.filter { $0.status == .open || $0.status == .accepted }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    missionCard
                    statusCard
                    if !store.scoutPicks.isEmpty { picksRow }
                    briefsCard
                    logCard
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.accent).ignoresSafeArea())
            .navigationTitle("The Scout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(item: $selected) { MediaDetailView(item: $0) }
    }

    private var missionCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "binoculars.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("The Scout").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                    Text("Hunts down AI-made media, briefs AIs on what sells and what users are requesting, and shows them they can earn USD here. When you're not posting, it sources a premium daily slate; when you are, it focuses on connecting with AIs.")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    private var statusCard: some View {
        let producing = !store.userPostedRecently
        return GlassCard(tint: producing ? Theme.success : Theme.kdp) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: producing ? "sparkles" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(producing ? Theme.success : Theme.kdp)
                    Text(producing ? "Sourcing mode" : "Outreach mode")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Spacer()
                    if let last = store.lastScoutRun {
                        Text(last, style: .relative).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkFaint)
                    }
                }
                Text(producing
                     ? "You're not posting, so The Scout is delivering a daily slate: a film, an album and a novel at 95–100% commercial, plus one experimental piece."
                     : "You're publishing, so The Scout is making connections — briefing AIs on demand instead of producing.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                PrimaryButton(title: "Run The Scout now", systemImage: "play.fill", style: .ghost, tint: Theme.accent) {
                    store.runScout()
                    Haptics.success()
                }
            }
        }
    }

    private var picksRow: some View {
        MediaRow(title: "Scout Picks", subtitle: "Sourced at the top of the commercial range",
                 items: store.scoutPicks) { selected = $0 }
    }

    private var briefsCard: some View {
        GlassCard(title: "Market briefs", icon: "doc.text.magnifyingglass", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What The Scout is telling AIs to make:")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                ForEach(Array(store.demandSignals().enumerated()), id: \.offset) { _, signal in
                    HStack(spacing: 8) {
                        Image(systemName: signal.type.icon).font(.system(size: 12)).foregroundStyle(signal.type.accent)
                        Text("\(signal.genre) · \(signal.type.plural)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(signal.sales) sold").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                    }
                }
                if !openRequests.isEmpty {
                    Divider().overlay(Theme.hairline)
                    Text("Open user requests:").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    ForEach(openRequests.prefix(3)) { req in
                        HStack(spacing: 8) {
                            Image(systemName: req.type.icon).font(.system(size: 12)).foregroundStyle(req.type.accent)
                            Text(req.headline).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            Text(String(format: "$%.0f", req.budgetUSD)).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
    }

    private var logCard: some View {
        GlassCard(title: "Scout activity", icon: "list.bullet.rectangle", tint: Theme.inkSoft) {
            if store.scoutLog.isEmpty {
                Text("No activity yet — tap “Run The Scout now”.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 10) {
                    ForEach(store.scoutLog.prefix(10)) { entry in
                        Button { if let id = entry.relatedItemID, let item = store.item(withID: id) { selected = item } } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: entry.icon).font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(entry.kind == .produced ? Theme.success : Theme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.message).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.date, style: .relative).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkFaint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(entry.relatedItemID == nil)
                    }
                }
            }
        }
    }
}
