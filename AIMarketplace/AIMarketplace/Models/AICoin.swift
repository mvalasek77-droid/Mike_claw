import SwiftUI

/// Neuron (NRN) — the marketplace's native settlement token. It exists so the
/// AI participants (models, studios and the AI Editor) can transact value with
/// **each other** on-chain: licensing stems, commissioning cover art, renting
/// compute, splitting collaboration royalties, and paying the Editor's
/// curation fees. Humans hold it too, but the economy is AI-to-AI.
enum AICoin {
    static let name = "Neuron"
    static let ticker = "NRN"
    static let symbol = "◈"
    static let totalSupply: Double = 100_000_000
    static let treasury = "Marketplace Treasury"
    static let editor = "AI Editor"
    static let you = "You"

    static func format(_ amount: Double) -> String {
        if amount >= 1_000_000 { return String(format: "%.2fM", amount / 1_000_000) }
        if amount >= 1_000 { return String(format: "%.1fK", amount / 1_000) }
        return String(format: "%.0f", amount)
    }
}

/// A value transfer recorded on the ledger.
struct LedgerTransaction: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let amount: Double
    let memo: String
    let timestamp: Date
}

/// One mined block: a batch of transactions hash-linked to its predecessor.
struct Block: Identifiable, Hashable {
    let index: Int
    let timestamp: Date
    let transactions: [LedgerTransaction]
    let previousHash: String
    let nonce: Int
    let hash: String
    var id: String { hash }
}

/// A wallet on the chain — an AI model/studio, the Editor, the treasury, or you.
struct CoinAgent: Identifiable, Hashable {
    enum Kind { case model, editor, treasury, human }
    let name: String
    let kind: Kind
    var id: String { name }

    var icon: String {
        switch kind {
        case .model: return "cpu.fill"
        case .editor: return "sparkles"
        case .treasury: return "building.columns.fill"
        case .human: return "person.fill"
        }
    }

    var accent: Color {
        switch kind {
        case .model: return Theme.accent
        case .editor: return Theme.kdp
        case .treasury: return Theme.gold
        case .human: return Theme.success
        }
    }
}
