import SwiftUI

/// The next film to open, as a full-bleed hero with a ticking
/// DAYS : HRS : MIN : SEC countdown. Tapping opens the movie.
struct OpeningNightHero: View {
    @EnvironmentObject var market: MarketService
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var next: Movie? {
        market.movies
            .filter { $0.opensAt > now }
            .min(by: { $0.opensAt < $1.opensAt })
    }

    var body: some View {
        if let movie = next {
            NavigationLink(value: movie) {
                ZStack(alignment: .bottomLeading) {
                    backdrop(movie)
                    VStack(alignment: .leading, spacing: 8) {
                        MarqueeBulbs(count: 14)
                        Text("OPENING NIGHT")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(Theme.bulbGlow)
                        Text(movie.title)
                            .font(Theme.Type.marqueeH1)
                            .foregroundStyle(Theme.cream)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                        if let dir = movie.director {
                            Text("A film by \(dir)")
                                .font(.caption)
                                .foregroundStyle(Theme.cream.opacity(0.75))
                        }
                        countdown(to: movie.opensAt)
                            .padding(.top, 4)
                        HStack(spacing: 10) {
                            Label("$\(market.impliedConsensus(for: movie.id), specifier: "%.0f")M implied",
                                  systemImage: "chart.bar")
                            Label(movie.studio, systemImage: "building.2")
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.cream.opacity(0.8))
                    }
                    .padding(Theme.Space.lg)
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                        .stroke(Theme.marqueeGold.opacity(0.55), lineWidth: 1.5)
                )
                .shadow(color: Theme.marqueeGold.opacity(0.25), radius: 20, y: 8)
            }
            .buttonStyle(.plain)
            .onReceive(clock) { now = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Opening night: \(movie.title) opens in \(movie.daysToRelease) days.")
        }
    }

    @ViewBuilder
    private func backdrop(_ movie: Movie) -> some View {
        ZStack {
            if let s = movie.posterURL, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else { emojiBackdrop(movie) }
                }
            } else {
                emojiBackdrop(movie)
            }
            LinearGradient(colors: [.clear, Theme.stageBlack.opacity(0.55), Theme.stageBlack.opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func emojiBackdrop(_ movie: Movie) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.velvetRed, Theme.stageBlack],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(movie.posterEmoji)
                .font(.system(size: 160))
                .opacity(0.22)
                .offset(x: 80, y: -30)
                .rotationEffect(.degrees(-12))
        }
    }

    private func countdown(to date: Date) -> some View {
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let d = secs / 86400
        let h = (secs % 86400) / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        return HStack(spacing: 8) {
            unit(d, "DAYS")
            colon
            unit(h, "HRS")
            colon
            unit(m, "MIN")
            colon
            unit(s, "SEC")
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 22, weight: .heavy, design: .monospaced))
            .foregroundStyle(Theme.marqueeGold)
            .offset(y: -6)
    }

    private func unit(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%02d", n))
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.cream)
                .contentTransition(.numericText())
                .animation(.snappy, value: n)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.marqueeGold)
        }
        .frame(minWidth: 42)
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.45)))
    }
}
