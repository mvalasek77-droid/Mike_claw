import Foundation

/// The two sides of the auction house. A profile is permanently one or the
/// other; the logged-in user picks theirs at onboarding.
///
/// - `.woman` is **The Lot** — always visible to bidders, sets a (optional)
///   starting bid, and accepts when a bid is high enough.
/// - `.man` is **The Bidder** — browses the floor, bids what he'll spend on a
///   date, and his picture stays hidden until a bid is accepted.
enum Role: String, Codable, CaseIterable, Identifiable {
    case woman
    case man

    var id: String { rawValue }

    var sideTitle: String { self == .woman ? "The Lot" : "The Bidder" }

    var pitch: String {
        switch self {
        case .woman: return "Set the floor. Read the room. Accept when the number is right."
        case .man:   return "Browse the floor. Bid what a date is worth. Earn your reputation."
        }
    }

    var systemImage: String { self == .woman ? "sparkles" : "dollarsign.circle.fill" }
}
