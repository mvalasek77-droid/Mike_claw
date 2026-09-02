import SwiftUI

/// A theater-marquee-styled scrolling ticker of live marks across the
/// whole catalog. Sits at the top of Now Showing. Pure SwiftUI — the
/// content is duplicated once so the loop is seamless, and a
/// TimelineView drives the offset for a smooth 60fps scroll.
struct MarqueeTicker: View {
    @EnvironmentObject var market: MarketService

    /// Points per second. ~40 reads comfortably; bump for a faster tape.
    var speed: CGFloat = 40

    private struct Item: Identifiable {
        let id: String
        let title: String
        let side: ContractSide
        let mark: Double
        let delta: Double   // vs base premium, as a fraction
    }

    private var items: [Item] {
        market.movies.flatMap { movie -> [Item] in
            let chain = market.chain(for: movie.id)
            // Pick the at-the-money call and put for each movie.
            let center = movie.consensusOpeningMillions
            let atmCall = chain.filter { $0.side == .call }
                .min(by: { abs($0.strikeMillions - center) < abs($1.strikeMillions - center) })
            let atmPut  = chain.filter { $0.side == .put }
                .min(by: { abs($0.strikeMillions - center) < abs($1.strikeMillions - center) })
            return [atmCall, atmPut].compactMap { c in
                guard let c else { return nil }
                let delta = c.basePremium > 0 ? (c.premium - c.basePremium) / c.basePremium : 0
                return Item(id: c.id, title: movie.title, side: c.side,
                            mark: c.premium, delta: delta)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let contentWidth = max(geo.size.width, estimatedWidth)
                let offset = -CGFloat(t * Double(speed)).truncatingRemainder(dividingBy: contentWidth)
                HStack(spacing: 0) {
                    tape
                    tape   // duplicate for seamless wrap
                }
                .offset(x: offset)
            }
        }
        .frame(height: 30)
        .clipped()
        .background(
            Rectangle().fill(Theme.stageBlack)
                .overlay(
                    LinearGradient(colors: [Theme.velvetRed.opacity(0.35), .clear, Theme.velvetRed.opacity(0.35)],
                                   startPoint: .leading, endPoint: .trailing)
                )
        )
        .overlay(alignment: .top) { MarqueeBulbs(count: 40).scaleEffect(0.6).offset(y: -1) }
        .overlay(alignment: .bottom) { MarqueeBulbs(count: 40).scaleEffect(0.6).offset(y: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live ticker of at-the-money call and put marks for every movie now showing.")
    }

    private var estimatedWidth: CGFloat {
        CGFloat(items.count) * 190
    }

    private var tape: some View {
        HStack(spacing: 22) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Text(item.title.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text(item.side.plain)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill((item.side == .call ? Theme.bull : Theme.bear).opacity(0.25)))
                        .foregroundStyle(item.side == .call ? Theme.bull : Theme.bear)
                    Text(item.mark, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.bulbGlow)
                    Text(item.delta, format: .percent.precision(.fractionLength(1)).sign(strategy: .always()))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(item.delta >= 0 ? Theme.bull : Theme.bear)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}
