import SwiftUI

/// A single entry in the Activity feed. The tint/icon are derived from `kind`
/// (so nothing un-Codable is persisted).
enum ActivityKind: String, Codable {
    case bidReceived, bidAccepted, bidDeclined, reviewReceived
    case verified, trillionaire, masterpiece, boost, rebid, daily

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
        }
    }
}

struct ActivityEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var kind: ActivityKind
    var text: String
}
