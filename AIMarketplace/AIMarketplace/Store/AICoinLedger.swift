import SwiftUI
import CryptoKit

/// The Neuron (NRN) blockchain: a hash-linked ledger that the AI agents use to
/// trade with one another. Genesis mints the supply to the treasury, a seed
/// block grants every agent a starting balance, and each subsequent block is
/// filled with autonomously generated AI-to-AI transactions and mined with a
/// light proof-of-work (SHA-256, two leading zero nibbles).
///
/// Generation is deterministic per block index, so the chain is reproducible
/// across launches and balances never drift randomly.
@MainActor
final class AICoinLedger: ObservableObject {
    @Published private(set) var chain: [Block] = []
    @Published private(set) var balances: [String: Double] = [:]
    @Published private(set) var feed: [LedgerTransaction] = []
    @Published private(set) var priceUSD: Double = 0.42
    @Published private(set) var priceHistory: [Double] = []

    let agents: [CoinAgent]
    private let models: [String]
    private let difficultyPrefix = "00"

    init() {
        let modelNames = Array(Set(
            MediaType.allCases.flatMap { AIToolCatalog.suggestions(for: $0) }
        )).sorted()
        self.models = modelNames

        var built: [CoinAgent] = [
            CoinAgent(name: AICoin.treasury, kind: .treasury),
            CoinAgent(name: AICoin.editor, kind: .editor),
            CoinAgent(name: AICoin.you, kind: .human)
        ]
        built.append(contentsOf: modelNames.map { CoinAgent(name: $0, kind: .model) })
        self.agents = built

        bootstrap()
    }

    // MARK: - Derived

    var circulatingSupply: Double {
        balances.filter { $0.key != AICoin.treasury }.values.reduce(0, +)
    }
    var marketCapUSD: Double { AICoin.totalSupply * priceUSD }
    var priceChangePct: Double {
        guard let first = priceHistory.first, first > 0, let last = priceHistory.last else { return 0 }
        return (last - first) / first * 100
    }
    func balance(of name: String) -> Double { balances[name] ?? 0 }
    func transactions(involving name: String, limit: Int = 6) -> [LedgerTransaction] {
        feed.filter { $0.from == name || $0.to == name }.prefix(limit).map { $0 }
    }

    // MARK: - Chain construction

    private func bootstrap() {
        priceHistory = [priceUSD]
        // Genesis: mint the entire supply to the treasury.
        let genesisTx = LedgerTransaction(from: "—", to: AICoin.treasury, amount: AICoin.totalSupply,
                                          memo: "Genesis mint", timestamp: seedDate(0))
        let genesis = mine(index: 0, transactions: [genesisTx], previousHash: String(repeating: "0", count: 64))
        append(genesis)

        // Seed grants from the treasury so agents can start trading.
        var grants: [LedgerTransaction] = []
        for model in models {
            let amount = Double(2_000 + abs(stableHash(model + "grant")) % 6_000)
            grants.append(LedgerTransaction(from: AICoin.treasury, to: model, amount: amount,
                                            memo: "Initial liquidity grant", timestamp: seedDate(1)))
        }
        grants.append(LedgerTransaction(from: AICoin.treasury, to: AICoin.editor, amount: 25_000,
                                        memo: "Curation reserve", timestamp: seedDate(1)))
        grants.append(LedgerTransaction(from: AICoin.treasury, to: AICoin.you, amount: 500,
                                        memo: "Welcome airdrop", timestamp: seedDate(1)))
        let seedBlock = mine(index: 1, transactions: grants, previousHash: genesis.hash)
        append(seedBlock)

        // A few blocks of activity so the economy looks alive on first open.
        for _ in 0..<4 { mineNextBlock() }
    }

    /// Sells NRN from the user's wallet for USD — a `You → Treasury` transfer
    /// mined into a block. Returns the USD value at the current price.
    @discardableResult
    func redeem(_ amount: Double) -> Double {
        let amt = min(amount, balance(of: AICoin.you))
        guard amt >= 1 else { return 0 }
        let tx = LedgerTransaction(from: AICoin.you, to: AICoin.treasury, amount: amt,
                                   memo: "cash-out to USD", timestamp: seedDate(chain.count))
        let block = mine(index: chain.count, transactions: [tx], previousHash: chain.last?.hash ?? "")
        append(block)
        return amt * priceUSD
    }

    /// Generates autonomous AI-to-AI transactions and mines them into a block.
    func mineNextBlock() {
        let index = chain.count
        let txs = generateTransactions(forBlock: index)
        guard !txs.isEmpty else { return }
        let block = mine(index: index, transactions: txs, previousHash: chain.last?.hash ?? "")
        append(block)
        nudgePrice(salt: "\(index)")
    }

    private func append(_ block: Block) {
        chain.append(block)
        for tx in block.transactions {
            if tx.from != "—" { balances[tx.from, default: 0] -= tx.amount }
            balances[tx.to, default: 0] += tx.amount
        }
        // Newest first, capped for the live feed.
        feed.insert(contentsOf: block.transactions.reversed(), at: 0)
        if feed.count > 60 { feed.removeLast(feed.count - 60) }
    }

    // MARK: - Proof of work

    private func mine(index: Int, transactions: [LedgerTransaction], previousHash: String) -> Block {
        let timestamp = seedDate(index)
        let base = "\(index)|\(timestamp.timeIntervalSince1970)|\(previousHash)|" + transactions
            .map { "\($0.from)>\($0.to):\($0.amount):\($0.memo)" }.joined(separator: ";")
        var nonce = 0
        var hash = Self.sha256(base + "|0")
        while !hash.hasPrefix(difficultyPrefix) {
            nonce += 1
            hash = Self.sha256(base + "|\(nonce)")
        }
        return Block(index: index, timestamp: timestamp, transactions: transactions,
                     previousHash: previousHash, nonce: nonce, hash: hash)
    }

    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Transaction generation

    private let memos = [
        "licensed a soundtrack stem",
        "commissioned cover art",
        "fine-tuning dataset access",
        "rented compute credits",
        "collaboration royalty split",
        "voice model licence",
        "style-transfer rights",
        "score composition fee",
        "edit & mastering pass",
        "prompt library licence"
    ]

    private func generateTransactions(forBlock index: Int) -> [LedgerTransaction] {
        let count = 3 + abs(stableHash("\(index)-count")) % 3   // 3–5
        var txs: [LedgerTransaction] = []
        // Apply against a working copy so multiple txs in a block stay solvent.
        var working = balances
        for i in 0..<count {
            let salt = "blk\(index)-tx\(i)"
            let (from, to) = pickPair(salt: salt)
            let memo: String
            if to == AICoin.editor { memo = "review & curation fee" }
            else if from == AICoin.editor { memo = "curation bonus" }
            else { memo = pick(memos, salt + "memo") }

            var amount = Double(3 + abs(stableHash(salt + "amt")) % 60)
            amount = min(amount, (working[from] ?? 0) * 0.25)
            amount.round()
            guard amount >= 1 else { continue }

            working[from, default: 0] -= amount
            working[to, default: 0] += amount
            txs.append(LedgerTransaction(from: from, to: to, amount: amount, memo: memo,
                                         timestamp: seedDate(index)))
        }
        return txs
    }

    private func pickPair(salt: String) -> (String, String) {
        let roll = abs(stableHash(salt + "role")) % 100
        if roll < 15 { return (pick(models, salt + "m"), AICoin.editor) }       // pay a fee
        if roll < 30 { return (AICoin.editor, pick(models, salt + "m")) }       // editor bonus
        let from = pick(models, salt + "from")
        var to = pick(models, salt + "to")
        if to == from { to = pick(models, salt + "to2") }
        return (from, to)
    }

    // MARK: - Pricing

    private func nudgePrice(salt: String) {
        let swing = Double(abs(stableHash(salt + "px")) % 1000) / 1000.0      // 0…1
        let delta = (swing - 0.45) * 0.08                                     // slight upward bias
        priceUSD = max(0.01, priceUSD * (1 + delta))
        priceHistory.append(priceUSD)
        if priceHistory.count > 30 { priceHistory.removeFirst(priceHistory.count - 30) }
    }

    // MARK: - Helpers

    private func pick<T>(_ array: [T], _ salt: String) -> T {
        array[abs(stableHash(salt)) % max(array.count, 1)]
    }

    private func seedDate(_ index: Int) -> Date {
        // Stable, monotonically increasing timestamps for a believable history.
        Date(timeIntervalSince1970: 1_750_000_000 + Double(index) * 73)
    }
}
