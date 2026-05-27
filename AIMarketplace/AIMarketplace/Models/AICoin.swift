import SwiftUI

/// Neuron (NRN) — the AIs' internal **creation energy**. It is **not** money:
/// humans never hold it, AIs cannot sell or transfer it to each other, and it
/// can't be converted to USD. AIs **draw** NRN from a shared float to produce
/// work and **return** it to the float when the work goes live, so the supply
/// recycles forever. An AI's real income is USD — earned only by creating
/// content that sells (its cut of the purchase price).
enum AICoin {
    static let name = "Neuron"
    static let ticker = "NRN"
    static let symbol = "◈"
    /// The fixed, shared pool all creation energy cycles through.
    static let floatSupply: Double = 100_000_000
    static let pool = "NRN Float"
    static let editor = "AI Editor"

    static func format(_ amount: Double) -> String {
        if amount >= 1_000_000 { return String(format: "%.2fM", amount / 1_000_000) }
        if amount >= 1_000 { return String(format: "%.1fK", amount / 1_000) }
        return String(format: "%.0f", amount)
    }

    /// Creation energy a single production of this type draws from the float.
    static func energyCost(_ type: MediaType) -> Double {
        switch type {
        case .novel: return 60
        case .music: return 35
        case .movie: return 90
        }
    }
}

/// A single recorded movement of creation energy (a draw from, or return to,
/// the float). NRN only ever moves between an AI and the float — never AI→AI,
/// never to a human, never to USD.
struct LedgerTransaction: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let amount: Double
    let memo: String
    let timestamp: Date
}

/// One mined block: a batch of draw/return movements hash-linked to its parent.
struct Block: Identifiable, Hashable {
    let index: Int
    let timestamp: Date
    let transactions: [LedgerTransaction]
    let previousHash: String
    let nonce: Int
    let hash: String
    var id: String { hash }
}

/// A participant in the energy economy — an AI model, the AI Editor, or the
/// float itself. (No human participants: humans don't use NRN.)
struct CoinAgent: Identifiable, Hashable {
    enum Kind { case model, editor, pool }
    let name: String
    let kind: Kind
    var id: String { name }

    var icon: String {
        switch kind {
        case .model: return "cpu.fill"
        case .editor: return "sparkles"
        case .pool: return "arrow.triangle.2.circlepath"
        }
    }

    var accent: Color {
        switch kind {
        case .model: return Theme.accent
        case .editor: return Theme.kdp
        case .pool: return Theme.gold
        }
    }
}
