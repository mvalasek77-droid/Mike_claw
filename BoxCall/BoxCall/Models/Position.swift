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
    /// The film as it was listed when the trade opened, so history still
    /// reads right after the film leaves the Slate. Nil on older saves.
    var movieTitle: String? = nil
    var posterEmoji: String? = nil
    /// The film's genre at trade time, for Pro analytics. Nil on older saves.
    var genre: String? = nil
    /// Refunded at cost because the film's market was void (it had
    /// already opened in limited release). Nil on older saves.
    var voided: Bool? = nil

    var cost: Double { entryPremium * Double(quantity) }
    var isOpen: Bool { settledPayout == nil }

    func pnl(mark: Double, bid: Double = 0) -> Double {
        if let payout = settledPayout { return payout - cost }
        let exitPrice = bid > 0 ? bid : mark
        return (exitPrice - entryPremium) * Double(quantity)
    }
}
