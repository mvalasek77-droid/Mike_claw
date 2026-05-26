import Foundation

/// An in-app notification (commission accepted, delivered, system message).
struct AppNotification: Identifiable, Codable, Hashable {
    var id = UUID()
    let title: String
    let body: String
    let date: Date
    var read: Bool
    let kind: Kind
    let relatedItemID: UUID?

    enum Kind: String, Codable { case request, delivery, system }

    var icon: String {
        switch kind {
        case .request: return "paperplane.fill"
        case .delivery: return "shippingbox.fill"
        case .system: return "bell.fill"
        }
    }
}
