import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var market: MarketService
    @EnvironmentObject var social: SocialService
    @State private var tradeTarget: Contract?
    @State private var showPutSide = false
    @State private var showLearn = false
    @State private var showWriteReview = false
    @State private var expandedReview: Review?

    var chain: [Contract] {
        market.chain(for: movie.id).filter { $0.side == (showPutSide ? .put : .call) }
    }

    var events: [MarketEvent] {
        market.events(for: movie.id)
    }

    var reviewsForMovie: [Review] {
        social.reviews(for: movie.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                consensusCard
                if !events.isEmpty { newsTicker }
                ticketButtons
                sidePicker
                chainHeader
                chainTable
                reviewsSection
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showWriteReview = true
                    } label: {
                        Label("Write a review", systemImage: "square.and.pencil")
                    }
                    Button {
                        showLearn = true
                    } label: {
                        Label("How this works", systemImage: "questionmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $tradeTarget) { contract in
            TradeSheet(contract: contract, movie: movie)
        }
        .sheet(isPresented: $showLearn) {
            NavigationStack {
                LearnView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLearn = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showWriteReview) {
            WriteReviewSheet(movie: movie)
        }
        .sheet(item: $expandedReview) { r in
            ReviewDetailSheet(review: r)
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reviews").font(.headline)
                Spacer()
                Button {
                    showWriteReview = true
                } label: {
                    Label("Write", systemImage: "square.and.pencil")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.orange)
            }
            if reviewsForMovie.isEmpty {
                Text("No reviews yet. Be the first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(reviewsForMovie) { r in
                    Button {
                        expandedReview = r
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("@\(r.authorHandle)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(r.authorTier.color)
                                Text(r.stars).font(.caption).foregroundStyle(.yellow)
                                Spacer()
                                Text("\(r.likes) ♥").font(.caption2).foregroundStyle(.pink)
                            }
                            Text(r.headline).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                            Text(r.body).font(.caption).lineLimit(2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterThumb(url: movie.posterURL, emoji: movie.posterEmoji,
                        width: 100, height: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(movie.title).font(.title2.bold())
                Text(movie.studio).font(.subheadline).foregroundStyle(.secondary)
                Text(movie.tagline).font(.footnote).italic().foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Label("\(movie.daysToRelease) days to open", systemImage: "calendar")
                    .font(.caption)
            }
            Spacer()
        }
    }

    private var consensusCard: some View {
        let implied = market.impliedConsensus(for: movie.id)
        let delta = market.consensusDeltaPct(for: movie.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Implied opening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LivePulse()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$\(implied, specifier: "%.1f")M")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                deltaTag(delta)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("IV \(Int(movie.impliedVolPct))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(movie.genre)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Sparkline(points: market.consensusHistoryFor(movieId: movie.id),
                      color: delta >= 0 ? .green : .red,
                      height: 28)
                .padding(.top, 2)
            Text("Base tracker: $\(Int(movie.consensusOpeningMillions))M · moves with buys, sells, and news.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
    }

    private func deltaTag(_ pct: Double) -> some View {
        let up = pct >= 0
        return HStack(spacing: 2) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
            Text(pct * 100, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
            Text("%")
        }
        .font(.caption.weight(.bold))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill((up ? Color.green : .red).opacity(0.2)))
        .foregroundStyle(up ? .green : .red)
    }

    private var ticketButtons: some View {
        HStack(spacing: 8) {
            ticketButton("Fandango", color: .red,
                         url: TicketAffiliate.fandangoURL(for: movie.title))
            ticketButton("AMC", color: .orange,
                         url: TicketAffiliate.amcURL(for: movie.title))
            ticketButton("Atom", color: .blue,
                         url: TicketAffiliate.atomURL(for: movie.title))
        }
    }

    private func ticketButton(_ label: String, color: Color, url: URL?) -> some View {
        Link(destination: url ?? URL(string: "https://boxcall.com")!) {
            HStack(spacing: 4) {
                Image(systemName: "ticket")
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
        }
    }

    private var newsTicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.orange)
                Text("Market news")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(events.prefix(3)) { event in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: event.isBullish ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(event.isBullish ? .green : .red)
                        .font(.caption2.weight(.bold))
                    Text(event.headline)
                        .font(.caption)
                    Spacer()
                    Text(shortTime(event.time)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private var sidePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Side", selection: $showPutSide) {
                Text("BIGGER · Calls").tag(false)
                Text("SMALLER · Puts").tag(true)
            }
            .pickerStyle(.segmented)
            Text(showPutSide
                 ? "Puts pay you when the movie opens BELOW your chosen number."
                 : "Calls pay you when the movie opens ABOVE your chosen number.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chainHeader: some View {
        HStack(spacing: 6) {
            LivePulse()
            Text("Live chain · updates every ~3s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortTime(market.lastTickAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var chainTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Strike").frame(width: 60, alignment: .leading)
                Text("Mark").frame(width: 60, alignment: .trailing)
                Text("Trend").frame(maxWidth: .infinity)
                Text("OI").frame(width: 50, alignment: .trailing)
                Text("").frame(width: 30)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ForEach(chain) { contract in
                Button {
                    tradeTarget = contract
                } label: {
                    HStack {
                        Text("$\(Int(contract.strikeMillions))M")
                            .frame(width: 60, alignment: .leading)
                            .fontWeight(.medium)
                        Text(contract.premium, format: .number.precision(.fractionLength(2)))
                            .frame(width: 60, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(contract.side == .call ? .green : .red)
                        Sparkline(points: market.priceHistory(contractId: contract.id),
                                  color: contract.side == .call ? .green : .red)
                            .frame(maxWidth: .infinity)
                        Text("\(contract.openInterest)")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Image(systemName: "cart.badge.plus")
                            .frame(width: 30)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.08)))
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

struct LivePulse: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
            .opacity(on ? 1.0 : 0.35)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
