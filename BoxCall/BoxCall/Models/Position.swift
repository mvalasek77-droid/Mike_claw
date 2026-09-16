import Foundation

struct Position: Identifiable, Codable, Hashable {
    let id: UUID
    let contractId: String
    let movieId: String
    let side: ContractSide
    let strikeMillions: Double
    let multiplier: Double
    let quantity: Int
    let entryPremium: Double
    let openedAt: Date
    var settledPayout: Double?   // nil until settled
    var actualOWMillions: Double?

    var cost: Double { entryPremium * Double(quantity) }
    var isOpen: Bool { settledPayout == nil }

    func pnl(mark: Double, bid: Double = 0) -> Double {
        if let payout = settledPayout { return payout - cost }
        let exitPrice = bid > 0 ? bid : mark
        return (exitPrice - entryPremium) * Double(quantity)
    }
}
