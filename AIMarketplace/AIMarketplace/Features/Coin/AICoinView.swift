import SwiftUI

/// The Neuron (NRN) wallet + on-chain explorer: market stats, your holdings,
/// the live AI-to-AI transaction feed, top holders, and the block explorer.
struct AICoinView: View {
    @EnvironmentObject private var ledger: AICoinLedger
    @Environment(\.dismiss) private var dismiss
    @State private var live = true

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    marketCard
                    walletCard
                    controls
                    feedCard
                    holdersCard
                    explorerCard
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .background(AppBackground(glow: Theme.gold).ignoresSafeArea())
            .navigationTitle("AI Coin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onReceive(timer) { _ in if live { ledger.mineNextBlock() } }
    }

    // MARK: Market

    private var marketCard: some View {
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
                        Text("AI-to-AI settlement token").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "$%.4f", ledger.priceUSD))
                            .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                        Text(String(format: "%@%.2f%%", ledger.priceChangePct >= 0 ? "+" : "", ledger.priceChangePct))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(ledger.priceChangePct >= 0 ? Theme.success : Theme.warning)
                    }
                }
                Sparkline(values: ledger.priceHistory,
                          color: ledger.priceChangePct >= 0 ? Theme.success : Theme.warning)
                    .frame(height: 44)
                HStack {
                    metric("Market cap", "$\(AICoin.format(ledger.marketCapUSD))")
                    metric("Circulating", "\(AICoin.format(ledger.circulatingSupply)) NRN")
                    metric("Blocks", "\(ledger.chain.count)")
                }
            }
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

    private var walletCard: some View {
        GlassCard(title: "Your wallet", icon: "wallet.pass.fill", tint: Theme.success) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(AICoin.format(ledger.balance(of: AICoin.you)))")
                    .font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Theme.ink)
                Text("NRN").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.inkSoft)
                Spacer()
                Text(String(format: "≈ $%.2f", ledger.balance(of: AICoin.you) * ledger.priceUSD))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.inkSoft)
            }
        }
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
                Label("Mine block", systemImage: "cube.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerM).fill(Theme.gold))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Feed

    private var feedCard: some View {
        GlassCard(title: "Live AI economy", icon: "arrow.left.arrow.right", tint: Theme.accent) {
            VStack(spacing: 10) {
                ForEach(ledger.feed.prefix(12)) { tx in
                    txRow(tx)
                }
            }
        }
    }

    private func txRow(_ tx: LedgerTransaction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: tx.from))
                .font(.system(size: 12, weight: .bold)).foregroundStyle(accent(for: tx.from))
                .frame(width: 24, height: 24).background(Circle().fill(accent(for: tx.from).opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(tx.from).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.inkFaint)
                    Text(tx.to).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                }
                .lineLimit(1)
                Text(tx.memo).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(1)
            }
            Spacer()
            Text("\(AICoin.format(tx.amount)) NRN")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
        }
    }

    // MARK: Holders

    private var holdersCard: some View {
        let ranked = ledger.agents
            .map { ($0, ledger.balance(of: $0.name)) }
            .filter { $0.0.kind != .treasury }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
        let top = ranked.map(\.1).max() ?? 1
        return GlassCard(title: "Top holders", icon: "chart.bar.fill", tint: Theme.kdp) {
            VStack(spacing: 10) {
                ForEach(Array(ranked), id: \.0.id) { agent, bal in
                    VStack(spacing: 4) {
                        HStack {
                            Image(systemName: agent.icon).font(.system(size: 11)).foregroundStyle(agent.accent)
                            Text(agent.name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(AICoin.format(bal)) NRN").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Theme.inkSoft)
                        }
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.08)).overlay(alignment: .leading) {
                                Capsule().fill(agent.accent).frame(width: geo.size.width * CGFloat(bal / max(top, 1)))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
    }

    // MARK: Explorer

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
                            Text("\(block.transactions.count) tx · nonce \(block.nonce)")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Agent lookup

    private func agent(for name: String) -> CoinAgent? { ledger.agents.first { $0.name == name } }
    private func icon(for name: String) -> String { agent(for: name)?.icon ?? "cpu.fill" }
    private func accent(for name: String) -> Color { agent(for: name)?.accent ?? Theme.accent }
}

/// Minimal price sparkline drawn from a value series.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.success

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.0001)
        return values.enumerated().map { i, v in
            let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = size.height * (1 - CGFloat((v - minV) / range))
            return CGPoint(x: x, y: y)
        }
    }
}
