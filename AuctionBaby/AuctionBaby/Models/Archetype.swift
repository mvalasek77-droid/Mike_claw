import SwiftUI

/// A purchasable status tier a man can attach to his profile. The point of the
/// app is to surface whether a man has money, so the tier *is* the price — the
/// more he pays, the louder the flex. Buying nothing is allowed; it just means
/// no badge.
///
/// The top tier, **Trillionaire**, is the only one that can mint a woman's
/// "Masterpiece" rating (see ``Profile/masterpiece``).
enum Archetype: Int, Codable, CaseIterable, Identifiable, Comparable {
    case none = 0
    case goodGuy
    case inAndOut
    case whyNot
    case goodJob
    case inheritance
    case influencer
    case ferrari
    case trillionaire

    var id: Int { rawValue }

    /// USD price of the tier. `none` is free.
    var price: Int {
        switch self {
        case .none: return 0
        case .goodGuy: return 5
        case .inAndOut: return 10
        case .whyNot: return 20
        case .goodJob: return 100
        case .inheritance: return 1_000
        case .influencer: return 10_000
        case .ferrari: return 100_000
        case .trillionaire: return 1_000_000
        }
    }

    var title: String {
        switch self {
        case .none: return "No Rating"
        case .goodGuy: return "Good Guy"
        case .inAndOut: return "In & Out Guy"
        case .whyNot: return "Why Not Guy"
        case .goodJob: return "Got a Good Job"
        case .inheritance: return "Inheritance Money Guy"
        case .influencer: return "Influencer"
        case .ferrari: return "I Drive a Ferrari"
        case .trillionaire: return "Trillionaire"
        }
    }

    var blurb: String {
        switch self {
        case .none: return "Unbadged. She'll have to take your word for it."
        case .goodGuy: return "Texts back. Probably splits the bill."
        case .inAndOut: return "Efficient. Knows what he wants."
        case .whyNot: return "The shrug that launched a thousand dates."
        case .goodJob: return "Salaried, LinkedIn-verified energy."
        case .inheritance: return "Didn't earn it. Will absolutely spend it."
        case .influencer: return "Will film the date. You signed nothing."
        case .ferrari: return "The car is leased. The flex is real."
        case .trillionaire: return "Can mint a Masterpiece. The whole floor turns."
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "circle.dashed"
        case .goodGuy: return "hand.thumbsup.fill"
        case .inAndOut: return "bolt.fill"
        case .whyNot: return "face.smiling.fill"
        case .goodJob: return "briefcase.fill"
        case .inheritance: return "building.columns.fill"
        case .influencer: return "camera.fill"
        case .ferrari: return "car.side.fill"
        case .trillionaire: return "crown.fill"
        }
    }

    /// Badge tint by prestige.
    var tint: Color {
        switch self {
        case .none: return Theme.inkFaint
        case .goodGuy, .inAndOut, .whyNot: return Theme.success
        case .goodJob, .inheritance: return Theme.gold
        case .influencer, .ferrari: return Theme.rose
        case .trillionaire: return Theme.goldSoft
        }
    }

    /// Trillionaire (and only trillionaire) renders with the prestige shimmer.
    var usesPrestigeStyle: Bool { self == .trillionaire }

    /// The next tier up, for the upgrade nudge. `nil` at the top.
    var next: Archetype? { Archetype(rawValue: rawValue + 1) }

    static func < (lhs: Archetype, rhs: Archetype) -> Bool { lhs.rawValue < rhs.rawValue }
}
