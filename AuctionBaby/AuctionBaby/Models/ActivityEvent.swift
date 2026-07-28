import SwiftUI

/// A single entry in the Activity feed. The tint/icon are derived from `kind`
/// (so nothing un-Codable is persisted).
enum ActivityKind: String, Codable {
    case bidReceived, bidAccepted, bidDeclined, reviewReceived
    case verified, trillionaire, masterpiece, boost, rebid, daily, credit, honors
    case admin

    var icon: String {
        switch self {
        case .bidReceived: return "hand.raised.fill"
        case .bidAccepted: return "checkmark.seal.fill"
        case .bidDeclined: return "xmark.circle.fill"
        case .reviewReceived: return "star.bubble.fill"
        case .verified: return "checkmark.shield.fill"
        case .trillionaire: return "crown.fill"
        case .masterpiece: return "rosette"
        case .boost: return "bolt.fill"
        case .rebid: return "arrow.up.circle.fill"
        case .daily: return "gift.fill"
        case .credit: return "gauge.with.needle"
        case .honors: return "photo.artframe"
        case .admin: return "person.2.badge.gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bidReceived: return Theme.gold
        case .bidAccepted: return Theme.success
        case .bidDeclined: return Theme.inkFaint
        case .reviewReceived: return Theme.rose
        case .verified: return Theme.verify
        case .trillionaire, .masterpiece: return Theme.goldSoft
        case .boost: return Theme.rose
        case .rebid: return Theme.gold
        case .daily: return Theme.success
        case .credit: return Theme.verify
        case .honors: return Theme.gold
        case .admin: return Theme.verify
        }
    }
}

struct ActivityEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: ActivityKind
    var text: String

    init(id: UUID = UUID(), date: Date = Date(), kind: ActivityKind, text: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.text = text
    }

    // Tolerant decode — same persistence invariant as Profile/Bid/Match: a
    // missing field never throws and wipes the snapshot. An unknown future
    // ActivityKind (older build reading a newer store) falls back to .credit
    // instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        kind = (try? c.decode(ActivityKind.self, forKey: .kind)) ?? .credit
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    }
}
