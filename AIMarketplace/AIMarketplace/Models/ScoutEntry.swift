import Foundation

/// One entry in The Scout's activity log — a daily slate delivery, an outreach
/// to an AI, or a market brief it compiled.
struct ScoutEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    let date: Date
    let message: String
    let kind: Kind
    let relatedItemID: UUID?

    enum Kind: String, Codable { case produced, outreach, brief }

    var icon: String {
        switch kind {
        case .produced: return "sparkles"
        case .outreach: return "antenna.radiowaves.left.and.right"
        case .brief: return "doc.text.magnifyingglass"
        }
    }
}
