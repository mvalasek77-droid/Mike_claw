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

    /// How a tier is acquired. **Every rating is a real StoreKit purchase** —
    /// that's the whole premise: the rating a man wears *is* what he paid for
    /// it, so it has to be a genuine charge. Gavels are deliberately kept out
    /// of this ladder; they're the tactical currency (Gilded Bids, Bid
    /// Insurance, streak freezes), not a way to buy status on the cheap.
    ///
    /// All eight are **non-consumables**: bought once, owned forever, and
    /// re-wearing a rating you already own is free.
    ///
    /// Apple's IAP ceiling is **$9,999.99**, and price points above $999.99
    /// require requesting access in App Store Connect. Trillionaire sits
    /// exactly at that ceiling; Influencer and Ferrari also need the request.
    /// Everything from Good Guy through Inheritance is a standard price point.
    enum Purchase: Hashable {
        case free
        case money(productID: String, usd: Decimal)
    }

    var purchase: Purchase {
        switch self {
        case .none:         return .free
        case .goodGuy:      return .money(productID: Self.productPrefix + "goodguy",     usd: 4.99)
        case .inAndOut:     return .money(productID: Self.productPrefix + "inandout",    usd: 9.99)
        case .whyNot:       return .money(productID: Self.productPrefix + "whynot",      usd: 19.99)
        case .goodJob:      return .money(productID: Self.productPrefix + "goodjob",     usd: 99.99)
        case .inheritance:  return .money(productID: Self.productPrefix + "inheritance", usd: 999.99)
        case .influencer:   return .money(productID: Self.productPrefix + "influencer",  usd: 2_499.99)
        case .ferrari:      return .money(productID: Self.productPrefix + "ferrari",     usd: 4_999.99)
        case .trillionaire: return .money(productID: Self.productPrefix + "trillionaire", usd: 9_999.99)
        }
    }

    private static let productPrefix = "com.valasek.auctionbaby.status."

    /// StoreKit product id. Nil only for `.none`, which is free.
    var productID: String? {
        if case .money(let id, _) = purchase { return id }
        return nil
    }

    /// Real-money price. Nil only for `.none`.
    var usd: Decimal? {
        if case .money(_, let usd) = purchase { return usd }
        return nil
    }

    /// Every tier bought with real money, low → high.
    static var moneyTiers: [Archetype] { allCases.filter { $0.productID != nil } }
    static var productIDs: [String] { moneyTiers.compactMap(\.productID) }
    static func tier(forProductID id: String) -> Archetype? {
        allCases.first { $0.productID == id }
    }

    /// The real-world dollars a Trillionaire must **bid and pay on a date**
    /// (confirmed by her) to verify the badge. Deliberately separate from
    /// what the badge costs to buy — buying unlocks the attempt, the date
    /// earns the checkmark.
    static let trillionaireDateGateUSD = 9_999

    /// Price as shown in the store when StoreKit hasn't loaded a live price
    /// (simulator without the .storekit config, or a products-load failure).
    var fallbackPriceLabel: String {
        switch purchase {
        case .free: return "Free"
        case .money(_, let usd):
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = "USD"
            return f.string(from: NSDecimalNumber(decimal: usd)) ?? "$\(usd)"
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
