import SwiftUI
import CryptoKit

/// The Neuron (NRN) creation-energy ledger: a hash-linked record of AIs drawing
/// energy from a shared float to produce work and returning it when the work
/// goes live. Energy is **never** transferred between AIs, sold, converted to
/// USD, or held by humans — it only ever cycles between an AI and the float.
///
/// Two numbers per AI:
/// - `inUse` — energy currently drawn (in-flight productions). Returns to 0.
/// - `cycled` — lifetime energy processed; a non-transferable throughput /
///   reputation metric (drives the builder leaderboard).
@MainActor
final class AICoinLedger: ObservableObject {
    @Published private(set) var chain: [Block] = []
    @Published private(set) var inUseByAgent: [String: Double] = [:]
    @Published private(set) var cycledByAgent: [String: Double] = [:]
    @Published private(set) var available: Double = AICoin.floatSupply
    @Published private(set) var feed: [LedgerTransaction] = []

    let agents: [CoinAgent]
    private let models: [String]
    private let difficultyPrefix = "00"

    init() {
        let modelNames = Array(Set(MediaType.allCases.flatMap { AIToolCatalog.suggestions(for: $0) })).sorted()
        self.models = modelNames
        var built: [CoinAgent] = [
            CoinAgent(name: AICoin.pool, kind: .pool),
            CoinAgent(name: AICoin.editor, kind: .editor)
        ]
        built.append(contentsOf: modelNames.map { CoinAgent(name: $0, kind: .model) })
        self.agents = built
        bootstrap()
    }

    // MARK: - Derived

    var floatSupply: Double { AICoin.floatSupply }
    var inUseTotal: Double { AICoin.floatSupply - available }
    var utilization: Double { inUseTotal / AICoin.floatSupply }
    var cycledTotal: Double { cycledByAgent.values.reduce(0, +) }

    func inUse(of name: String) -> Double { inUseByAgent[name] ?? 0 }
    func cycled(of name: String) -> Double { cycledByAgent[name] ?? 0 }

    func transactions(involving name: String, limit: Int = 6) -> [LedgerTransaction] {
        feed.filter { $0.from == name || $0.to == name }.prefix(limit).map { $0 }
    }

    // MARK: - Public energy operations

    /// An AI draws creation energy from the float to produce a work.
    func draw(_ amount: Double, by agent: String, memo: String) {
        let amt = min((amount * 100).rounded() / 100, available)
        guard amt >= 1 else { return }
        record([LedgerTransaction(from: AICoin.pool, to: agent, amount: amt, memo: memo, timestamp: now())])
    }

    /// Energy returns to the float once a work is live.
    func returnEnergy(_ amount: Double, from agent: String, memo: String) {
        let amt = min((amount * 100).rounded() / 100, inUse(of: agent))
        guard amt >= 1 else { return }
        record([LedgerTransaction(from: agent, to: AICoin.pool, amount: amt, memo: memo, timestamp: now())])
    }

    /// Recognises bonus creation energy for an AI (incentives). Drawn and
    /// immediately returned, so the float is conserved and the AI's lifetime
    /// `cycled` (reputation) grows. NRN is never kept or made transferable.
    func award(_ amount: Double, to agent: String, memo: String) {
        let amt = (amount * 100).rounded() / 100
        guard amt >= 1 else { return }
        record([
            LedgerTransaction(from: AICoin.pool, to: agent, amount: amt, memo: memo, timestamp: now()),
            LedgerTransaction(from: agent, to: AICoin.pool, amount: amt, memo: "energy returned", timestamp: now())
        ])
    }

    /// Generates a believable block of autonomous draw/return activity.
    func mineNextBlock() {
        let index = chain.count
        var txs: [LedgerTransaction] = []
        let count = 3 + abs(stableHash("\(index)-c")) % 3
        for i in 0..<count {
            let salt = "blk\(index)-\(i)"
            let agent = pick(models + [AICoin.editor], salt + "a")
            let drawing = abs(stableHash(salt + "d")) % 100 < 60 || inUse(of: agent) < 1
            if drawing {
                let amt = Double(3 + abs(stableHash(salt + "amt")) % 50)
                txs.append(LedgerTransaction(from: AICoin.pool, to: agent, amount: amt,
                                             memo: drawMemo(salt: salt, agent: agent), timestamp: now()))
            } else {
                let amt = min(Double(3 + abs(stableHash(salt + "amt")) % 50), inUse(of: agent))
                if amt >= 1 {
                    txs.append(LedgerTransaction(from: agent, to: AICoin.pool, amount: amt,
                                                 memo: "returned energy — work live", timestamp: now()))
                }
            }
        }
        guard !txs.isEmpty else { return }
        record(txs)
    }

    // MARK: - Internals

    private func record(_ txs: [LedgerTransaction]) {
        let block = mine(index: chain.count, transactions: txs, previousHash: chain.last?.hash ?? String(repeating: "0", count: 64))
        chain.append(block)
        for tx in txs { apply(tx) }
        feed.insert(contentsOf: txs.reversed(), at: 0)
        if feed.count > 60 { feed.removeLast(feed.count - 60) }
    }

    private func apply(_ tx: LedgerTransaction) {
        if tx.from == AICoin.pool {            // draw
            available -= tx.amount
            inUseByAgent[tx.to, default: 0] += tx.amount
            cycledByAgent[tx.to, default: 0] += tx.amount
        } else if tx.to == AICoin.pool {       // return
            available += tx.amount
            inUseByAgent[tx.from, default: 0] = max(0, (inUseByAgent[tx.from] ?? 0) - tx.amount)
        }
    }

    private func bootstrap() {
        // Genesis: the float exists; record it for the explorer.
        let genesis = mine(index: 0,
                           transactions: [LedgerTransaction(from: "—", to: AICoin.pool, amount: AICoin.floatSupply,
                                                            memo: "Float genesis", timestamp: seedDate(0))],
                           previousHash: String(repeating: "0", count: 64))
        chain.append(genesis)
        feed.insert(contentsOf: genesis.transactions, at: 0)
        for _ in 0..<5 { mineNextBlock() }
    }

    private let drawVerbs = [
        "drawing energy to draft a chapter",
        "rendering a scene",
        "composing an arrangement",
        "mixing a track",
        "iterating on a cover",
        "running a quality pass",
        "generating a sequence"
    ]
    private func drawMemo(salt: String, agent: String) -> String {
        agent == AICoin.editor ? "energy for a curation pass" : pick(drawVerbs, salt + "m")
    }

    // MARK: - Proof of work

    private func mine(index: Int, transactions: [LedgerTransaction], previousHash: String) -> Block {
        let ts = seedDate(index)
        let base = "\(index)|\(ts.timeIntervalSince1970)|\(previousHash)|" +
            transactions.map { "\($0.from)>\($0.to):\($0.amount):\($0.memo)" }.joined(separator: ";")
        var nonce = 0
        var hash = Self.sha256(base + "|0")
        while !hash.hasPrefix(difficultyPrefix) {
            nonce += 1
            hash = Self.sha256(base + "|\(nonce)")
        }
        return Block(index: index, timestamp: ts, transactions: transactions,
                     previousHash: previousHash, nonce: nonce, hash: hash)
    }

    static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func pick<T>(_ array: [T], _ salt: String) -> T { array[abs(stableHash(salt)) % max(array.count, 1)] }
    private func now() -> Date { seedDate(chain.count) }
    private func seedDate(_ index: Int) -> Date { Date(timeIntervalSince1970: 1_750_000_000 + Double(index) * 73) }
}
