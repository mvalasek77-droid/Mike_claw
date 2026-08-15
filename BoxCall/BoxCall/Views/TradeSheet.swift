import SwiftUI

struct TradeSheet: View {
    let contract: Contract
    let movie: Movie
    @EnvironmentObject var portfolio: PortfolioService
    @EnvironmentObject var social: SocialService
    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int = 1
    @State private var shareAsPost: Bool = true
    @State private var hotTake: String = ""
    @State private var errorMessage: String?

    var cost: Double { contract.premium * Double(quantity) }

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

                Section("Order") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
                    HStack {
                        Text("Premium (each)"); Spacer()
                        Text(contract.premium, format: .number.precision(.fractionLength(2)))
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

                Section("Payoff at settlement") {
                    let hi = movie.consensusOpeningMillions * 1.5
                    let lo = movie.consensusOpeningMillions * 0.5
                    let mid = movie.consensusOpeningMillions
                    payoffRow(label: "If bomb ($\(Int(lo))M)", value: contract.intrinsic(atMillions: lo) * Double(quantity))
                    payoffRow(label: "If tracks ($\(Int(mid))M)", value: contract.intrinsic(atMillions: mid) * Double(quantity))
                    payoffRow(label: "If blockbuster ($\(Int(hi))M)", value: contract.intrinsic(atMillions: hi) * Double(quantity))
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
                            let positionId = try portfolio.buy(contract: contract, quantity: quantity)
                            if shareAsPost {
                                social.share(positionId: positionId, contract: contract,
                                             movie: movie, quantity: quantity, hotTake: hotTake)
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
