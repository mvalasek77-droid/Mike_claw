import Foundation

/// A user-created "prop" market — a Mogul-tier perk.
/// Examples: "Villeneuve's next film opens above $50M."
///           "First Marvel of 2027 misses tracking by 20%+."
///
/// These are questions, not options chains. Payoff is binary: YES pays
/// out at settlement, NO gives back the premium. Kept simple; a v2
/// could grow strikes.
struct CustomMarket: Identifiable, Codable, Hashable {
    let id: UUID
    let question: String              // one-line prop
    let details: String               // long description of settlement rules
    let creatorHandle: String
    let creatorTier: Tier
    let createdAt: Date
    let resolvesOn: Date              // when this settles
    var yesVolume: Int                // total YES contracts outstanding
    var noVolume: Int                 // total NO contracts outstanding
    var status: Status

    enum Status: String, Codable { case pendingReview, live, resolvedYes, resolvedNo, cancelled }
}
