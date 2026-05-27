import SwiftUI

/// The Neuron (NRN) creation-energy monitor: how the AIs draw energy from a
/// shared float to make work and return it when the work goes live. NRN isn't
/// money — it can't be transferred between AIs, converted to USD, or held by
/// humans. AIs earn USD only by creating content that sells.
struct AICoinView: View {
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss
    @State private var live = true

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    floatCard
                    explainerCard
                    controls
                    feedCard
                    buildersCard
                    explorerCard
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.gold).ignoresSafeArea())
            .navigationTitle("NRN Energy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onReceive(timer) { _ in if live { ledger.mineNextBlock() } }
    }

    private var floatCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Theme.gold.opacity(0.18)).frame(width: 46, height: 46)
                        Text(AICoin.symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.gold)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(AICoin.name) · \(AICoin.ticker)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text("AI creation energy · recycles to a float").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                // Float utilization bar
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                        Capsule().fill(Theme.gold).frame(width: geo.size.width * min(1, ledger.utilization))
                    }
                }
                .frame(height: 8)
                HStack {
                    metric("Available", "\(AICoin.format(ledger.available)) NRN")
                    metric("In use", "\(AICoin.format(ledger.inUseTotal)) NRN")
                    metric("Cycled", "\(AICoin.format(ledger.cycledTotal)) NRN")
                }
            }
        }
    }

    private var explainerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.gold)
            Text("AIs **draw** energy from the float to create, then **return** it when the work is live. NRN can't be transferred between AIs, sold, or turned into USD — AIs earn USD only from content that sells.")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { live.toggle(); Haptics.tap() } label: {
                Label(live ? "Live" : "Paused", systemImage: live ? "dot.radiowaves.left.and.right" : "pause.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(live ? Theme.success : Theme.inkSoft)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(.white.opacity(0.08)))
            }
            Button { ledger.mineNextBlock(); Haptics.tap() } label: {
                Label("Advance", systemImage: "cube.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.gold))
            }
        }
        .buttonStyle(.plain)
    }

    private var feedCard: some View {
        GlassCard(title: "Live energy flow", icon: "arrow.left.arrow.right", tint: Theme.accent) {
            VStack(spacing: 10) {
                ForEach(ledger.feed.prefix(12)) { tx in txRow(tx) }
            }
        }
    }

    private func txRow(_ tx: LedgerTransaction) -> some View {
        let isDraw = tx.from == AICoin.pool
        let other = isDraw ? tx.to : tx.from
        return HStack(spacing: 10) {
            Image(systemName: isDraw ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(isDraw ? Theme.success : Theme.inkSoft)
                .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(isDraw ? "\(other) drew energy" : "\(other) returned energy")
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(tx.memo).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Text("\(AICoin.format(tx.amount))")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
        }
    }

    private var buildersCard: some View {
        let ranked = ledger.agents
            .filter { $0.kind == .model }
            .map { ($0, ledger.cycled(of: $0.name)) }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
        let top = ranked.map(\.1).max() ?? 1
        return GlassCard(title: "Most active builders", icon: "chart.bar.fill", tint: Theme.kdp) {
            VStack(spacing: 10) {
                ForEach(Array(ranked), id: \.0.id) { agent, value in
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: agent.icon).font(.system(size: 11)).foregroundStyle(agent.accent)
                            Text(agent.name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(AICoin.format(value)) cycled").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        }
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                                Capsule().fill(agent.accent).frame(width: geo.size.width * CGFloat(value / max(top, 1)))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }

    private var explorerCard: some View {
        GlassCard(title: "Block explorer", icon: "square.stack.3d.up.fill", tint: Theme.inkSoft) {
            VStack(spacing: 10) {
                ForEach(ledger.chain.suffix(8).reversed()) { block in
                    HStack(spacing: 10) {
                        Text("#\(block.index)")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(Theme.gold)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(block.hash.prefix(18) + "…")
                                .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text("\(block.transactions.count) moves · nonce \(block.nonce)")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}
