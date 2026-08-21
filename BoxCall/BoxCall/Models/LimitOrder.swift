import Foundation

/// Resting limit order — sits until the live mark crosses the limit
/// price, then fills at the limit and creates a Position. Buy limits
/// fire when the mark drops to (or below) the limit; MMs already
/// tend to work the mark against support, so buy-limits near support
/// are the classic setup.
struct LimitOrder: Identifiable, Codable, Hashable {
    let id: UUID
    let contractId: String
    let movieId: String
    let side: ContractSide
    let strikeMillions: Double
    let multiplier: Double
    let quantity: Int
    let limitPrice: Double        // Reel Coins per contract
    let placedAt: Date
    var status: Status

    enum Status: String, Codable { case working, filled, cancelled }
}
