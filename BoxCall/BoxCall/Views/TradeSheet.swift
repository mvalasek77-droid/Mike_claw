import SwiftUI

struct TradeSheet: View {
    let contract: Contract
    let movie: Movie
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var social: SocialService
    @EnvironmentObject var market: MarketService
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int = 1
    @State private var shareAsPost: Bool = true
    @State private var hotTake: String = ""
    @State private var errorMessage: String?
    @State private var showLearn: Bool = false
    @State private var showChart: Bool = false

    /// Latest live contract from the market (mark ticks while sheet is open).
    var liveContract: Contract {
        market.chain(for: contract.movieId).first(where: { $0.id == contract.id }) ?? contract
    }

    var cost: Double { liveContract.premium * Double(quantity) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("\(movie.title)")
                        Spacer()
                        Text("\(contract.side.display) $\(Int(contract.strikeMillions))M")
                            .foregroundStyle(contract.side == .call ? .green : .red)
                            .fontWeight(.semibold)
                    }
                }

                Section {
                    PriceChart(points: market.priceHistory(contractId: contract.id),
                               color: contract.side == .call ? .green : .red)
                        .padding(.vertical, 4)
                } header: {
                    HStack(spacing: 6) {
                        LivePulse()
                        Text("Live mark").font(.caption.weight(.semibold))
                        Spacer()
                        Text(liveContract.premium, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(contract.side == .call ? .green : .red)
                    }
                }

                Section("Order") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
                    HStack {
                        Text("Premium (each)"); Spacer()
                        Text(liveContract.premium, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Total cost"); Spacer()
                        Text(cost, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Your Reel Coins"); Spacer()
                        Text(portfolio.user.reelCoins, format: .number.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    let mid = market.impliedConsensus(for: movie.id)
                    let hi = mid * 1.5
                    let lo = mid * 0.5
                    payoffRow(label: "If bomb ($\(Int(lo))M)", value: contract.intrinsic(atMillions: lo) * Double(quantity))
                    payoffRow(label: "If tracks ($\(mid, specifier: "%.1f")M implied)", value: contract.intrinsic(atMillions: mid) * Double(quantity))
                    payoffRow(label: "If blockbuster ($\(Int(hi))M)", value: contract.intrinsic(atMillions: hi) * Double(quantity))
                    DisclosureGroup(isExpanded: $showChart) {
                        PayoffChart(side: contract.side,
                                    strike: contract.strikeMillions,
                                    premium: liveContract.premium,
                                    multiplier: contract.multiplier)
                            .padding(.vertical, 4)
                        Text("Green = profit zone. Orange dashed = your strike. Blue dashed = break-even.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } label: {
                        Label("Payoff diagram", systemImage: "chart.xyaxis.line")
                    }
                } header: {
                    HStack {
                        Text("Payoff at settlement")
                        Spacer()
                        Button {
                            showLearn = true
                        } label: {
                            Label("Learn", systemImage: "questionmark.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Share this call") {
                    Toggle("Post to Hot Takes", isOn: $shareAsPost)
                    if shareAsPost {
                        TextField("Say why — 280 chars", text: $hotTake, axis: .vertical)
                            .lineLimit(2...4)
                        if portfolio.user.tier < .analyst {
                            Text("Rookies post to their followers only. Reach Analyst to hit the public feed.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        do {
                            let live = liveContract
                            let positionId = try portfolio.buy(contract: live, quantity: quantity)
                            if shareAsPost {
                                social.share(positionId: positionId, contract: live,
                                             movie: movie, quantity: quantity, hotTake: hotTake)
                            }
                            if let placed = portfolio.positions.first(where: { $0.id == positionId }) {
                                NotificationsService.shared.scheduleOpeningReminder(movie: movie, position: placed)
                            }
                            portfolio.refreshLeaderboard()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text("Buy \(quantity) \(contract.side.display) for \(cost, format: .number.precision(.fractionLength(2)))")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .navigationTitle("Place Trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showLearn = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .sheet(isPresented: $showLearn) {
                NavigationStack {
                    LearnView(initialSection: contract.side == .call ? .whatsACall : .whatsAPut)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showLearn = false }
                            }
                        }
                }
            }
        }
    }

    private func payoffRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            let net = value - cost
            Text(net, format: .number.precision(.fractionLength(2)).sign(strategy: .always()))
                .monospacedDigit()
                .foregroundStyle(net >= 0 ? .green : .red)
        }
    }
}
