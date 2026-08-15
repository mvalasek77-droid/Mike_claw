import SwiftUI

struct MovieDetailView: View {
    let movie: Movie
    @EnvironmentObject var market: MarketService
    @State private var tradeTarget: Contract?
    @State private var showPutSide = false

    var chain: [Contract] {
        market.chain(for: movie.id).filter { $0.side == (showPutSide ? .put : .call) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                consensusCard
                sidePicker
                chainTable
            }
            .padding()
        }
        .navigationTitle(movie.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tradeTarget) { contract in
            TradeSheet(contract: contract, movie: movie)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(movie.posterEmoji)
                .font(.system(size: 72))
                .frame(width: 100, height: 140)
                .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.2)))
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Consensus opening")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text("$\(Int(movie.consensusOpeningMillions))M")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
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
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
    }

    private var sidePicker: some View {
        Picker("Side", selection: $showPutSide) {
            Text("CALLS (bullish)").tag(false)
            Text("PUTS (bearish)").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private var chainTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Strike").frame(maxWidth: .infinity, alignment: .leading)
                Text("Premium").frame(maxWidth: .infinity, alignment: .trailing)
                Text("OI").frame(width: 60, alignment: .trailing)
                Text("").frame(width: 44)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fontWeight(.medium)
                        Text(contract.premium, format: .number.precision(.fractionLength(2)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .monospacedDigit()
                            .foregroundStyle(contract.side == .call ? .green : .red)
                        Text("\(contract.openInterest)")
                            .frame(width: 60, alignment: .trailing)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Image(systemName: "cart.badge.plus")
                            .frame(width: 44)
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
}
