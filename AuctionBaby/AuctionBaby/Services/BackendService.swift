import Foundation
import Combine

/// Decodable for Worker error responses ({error: "..."} or {ok:false, reason: "..."})
struct BackendWorkerError: Decodable { let error: String?; let reason: String? }

/// Success-or-message result for Worker calls. A plain enum (rather than
/// Swift's `Result`) because the failure side is a display string, not an
/// `Error`, and the views render it directly.
enum BackendResult<T> {
    case success(T)
    case failure(String)

    func map<U>(_ transform: (T) -> U) -> BackendResult<U> {
        switch self {
        case .success(let value): return .success(transform(value))
        case .failure(let message): return .failure(message)
        }
    }
}

/// The app's client for the Auction Baby payout Worker (see `backend/`).
///
/// Owns the Worker URL + shared secret (seeded from `BackendConfig` /
/// Info.plist, editable in the admin console for staging) and exposes typed
/// calls for every admin surface: float funding, the money ledger, owed-women
/// recovery, and the moderation queue. Every failure is recorded to
/// `ErrorMonitor` under the "Backend" category so the admin console can show
/// what went wrong without a Mac attached.
@MainActor
final class BackendService: ObservableObject {

    /// Worker base URL, e.g. "https://auctionbaby-payout.you.workers.dev".
    @Published var workerURL: String {
        didSet { UserDefaults.standard.set(workerURL, forKey: Self.urlKey) }
    }
    /// Must match APP_SHARED_SECRET on the Worker.
    @Published var sharedSecret: String {
        didSet { UserDefaults.standard.set(sharedSecret, forKey: Self.secretKey) }
    }
    /// Stripe consumables Worker (the web Gavel shop), e.g.
    /// "https://auctionbaby-consumables.you.workers.dev". Optional — empty
    /// means no web shop is wired and the Gavel sync is a no-op. Shares
    /// `sharedSecret` with the payout Worker by convention.
    @Published var consumablesURL: String {
        didSet { UserDefaults.standard.set(consumablesURL, forKey: Self.consumablesKey) }
    }

    private static let urlKey = "auctionbaby.backend.url.v1"
    private static let secretKey = "auctionbaby.backend.secret.v1"
    private static let consumablesKey = "auctionbaby.backend.consumables.v1"

    init() {
        let savedURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        let savedSecret = UserDefaults.standard.string(forKey: Self.secretKey) ?? ""
        let savedConsumables = UserDefaults.standard.string(forKey: Self.consumablesKey) ?? ""
        // Baked build config wins only when nothing was saved locally, so a
        // staging URL typed into the admin console survives relaunch.
        workerURL = savedURL.isEmpty ? BackendConfig.workerURL : savedURL
        sharedSecret = savedSecret.isEmpty ? BackendConfig.sharedSecret : savedSecret
        consumablesURL = savedConsumables.isEmpty ? BackendConfig.consumablesURL : savedConsumables
    }

    var isConfigured: Bool {
        !workerURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !sharedSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The web Gavel shop is optional; sync only runs when both the
    /// consumables URL and the shared secret are present.
    var isConsumablesConfigured: Bool {
        !consumablesURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !sharedSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Payload types (mirror backend/src/index.ts responses)

    struct Funding: Decodable {
        let currency: String
        let availableUSD: Double
        let bufferUSD: Double
        let topUpNeededUSD: Double
        let salesTodayCount: Int
        let salesTodayUSD: Double
    }

    struct LedgerEntry: Decodable, Identifiable {
        let ts: String
        let type: String
        let status: String
        let amountCents: Int
        let currency: String
        let scope: String
        let refId: String?
        let stripeId: String?
        let note: String?

        let id = UUID()
        private enum CodingKeys: String, CodingKey {
            case ts, type, status, amountCents, currency, scope, refId, stripeId, note
        }
        var amountLabel: String {
            String(format: "%.2f %@", Double(amountCents) / 100, currency.uppercased())
        }
    }

    struct UnfundedEntry: Decodable, Identifiable {
        let id: String
        let ts: String
        let accountId: String
        let amountCents: Int
        let currency: String
        let ref: String?
        let reason: String
        var amountUSD: Double { Double(amountCents) / 100 }
    }

    struct Report: Decodable, Identifiable {
        let id: String
        let ts: String
        let status: String
        let profile_id: String
        let profile_name: String
        let reason: String
        let details: String
        let reporter_email: String
        let disposition: String
        let resolved_at: String
        let resolution_note: String
    }

    struct HealthInfo: Decodable {
        let service: String
        let version: String
    }

    /// One queued refund the Worker learned about via Apple's ASSN V2, waiting
    /// for the client to claw back the matching Gavels.
    struct RefundEntry: Decodable {
        let transactionId: String
        let productId: String
        /// "refunded" (claw back Gavels) or "refund_reversed" (restore them).
        let kind: String
    }

    // MARK: - Calls

    /// GET / — verifies the URL + reachability (no auth needed, but we send
    /// it anyway; the route ignores it).
    func checkHealth() async -> BackendResult<HealthInfo> {
        await get("/", as: HealthInfo.self)
    }

    /// GET /payouts/funding — float snapshot for the admin money card.
    func fetchFunding() async -> BackendResult<Funding> {
        await get("/payouts/funding", as: Funding.self)
    }

    /// GET /ledger?scope=… — newest-first money record.
    func fetchLedger(scope: String, limit: Int = 100) async -> BackendResult<[LedgerEntry]> {
        struct Wrapper: Decodable { let entries: [LedgerEntry] }
        let query = "scope=\(scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope)&limit=\(limit)"
        return await get("/ledger?\(query)", as: Wrapper.self).map(\.entries)
    }

    /// GET /payouts/unfunded — women owed a failed transfer.
    func fetchUnfunded() async -> BackendResult<[UnfundedEntry]> {
        struct Wrapper: Decodable { let entries: [UnfundedEntry] }
        return await get("/payouts/unfunded", as: Wrapper.self).map(\.entries)
    }

    /// POST /payouts/manual-fund — operator re-pays an owed woman. Returns
    /// nil on success, or the error message.
    func manualFund(_ entry: UnfundedEntry) async -> String? {
        struct Response: Decodable { let transferId: String }
        let body: [String: Any] = [
            "account_id": entry.accountId,
            "amount_usd": entry.amountUSD,
            "unfunded_id": entry.id,
            "reason": "Manual re-pay from admin console",
        ]
        switch await post("/payouts/manual-fund", body: body, as: Response.self) {
        case .success: return nil
        case .failure(let message): return message
        }
    }

    /// GET /moderation/reports?status=…
    func fetchReports(resolved: Bool) async -> BackendResult<[Report]> {
        struct Wrapper: Decodable { let reports: [Report] }
        return await get("/moderation/reports?status=\(resolved ? "resolved" : "pending")",
                         as: Wrapper.self).map(\.reports)
    }

    /// POST /moderation/reports/{id}/resolve — returns nil on success.
    func resolveReport(id: String, disposition: String, note: String) async -> String? {
        struct Response: Decodable { let resolved: Bool }
        switch await post("/moderation/reports/\(id)/resolve",
                          body: ["disposition": disposition, "note": note],
                          as: Response.self) {
        case .success: return nil
        case .failure(let message): return message
        }
    }

    /// POST /payouts/topup — manually run the float top-up (also on cron).
    func triggerTopUp() async -> BackendResult<String> {
        struct Response: Decodable { let toppedUp: Double; let availableUSD: Double }
        return await post("/payouts/topup", body: [:], as: Response.self).map { r in
            r.toppedUp > 0
                ? String(format: "Topped up $%.2f (balance was $%.2f).", r.toppedUp, r.availableUSD)
                : String(format: "Float healthy at $%.2f — no top-up needed.", r.availableUSD)
        }
    }

    /// GET /refunds/pending?app_account_token=<uuid> — Apple ASSN refund events
    /// that landed at the Worker while the app was closed. The Worker keeps the
    /// queue keyed by the buyer's per-user `appAccountToken` so refunds route
    /// to the right wallet without any account concept.
    func fetchPendingRefunds(appAccountToken: UUID) async -> BackendResult<[RefundEntry]> {
        struct Wrapper: Decodable { let refunds: [RefundEntry] }
        let token = appAccountToken.uuidString.lowercased()
        return await get("/refunds/pending?app_account_token=\(token)", as: Wrapper.self).map(\.refunds)
    }

    /// POST /refunds/ack — tell the Worker the client has applied these
    /// transaction ids so they don't re-serve every foreground.
    func ackRefunds(appAccountToken: UUID, transactionIDs: [String]) async {
        guard !transactionIDs.isEmpty else { return }
        _ = await post("/refunds/ack",
                       body: ["app_account_token": appAccountToken.uuidString.lowercased(),
                              "transaction_ids": transactionIDs],
                       as: AckResponse.self)
    }
    private struct AckResponse: Decodable { let acked: Int }

    /// POST /payouts/digest — manually email the payout digest.
    func triggerDigest() async -> BackendResult<String> {
        struct Response: Decodable { let accounts: Int; let owedUSD: Double }
        return await post("/payouts/digest", body: [:], as: Response.self).map { r in
            String(format: "Digest sent — %d owed, $%.2f total.", r.accounts, r.owedUSD)
        }
    }

    // MARK: - Web Gavel shop (Stripe consumables Worker)

    /// GET /balance on the consumables Worker — Gavels bought on the web shop
    /// that haven't been drained into the app wallet yet.
    func fetchWebGavels(appAccountToken: UUID) async -> BackendResult<Int> {
        struct Response: Decodable { let gavels: Int }
        let token = appAccountToken.uuidString.lowercased()
        return await get("/balance?userId=\(token)", base: consumablesURL, as: Response.self)
            .map(\.gavels)
    }

    /// POST /consume on the consumables Worker — drains `gavels` from the web
    /// balance so they can be credited to the local wallet. Idempotent per
    /// `idempotencyKey`: a retried drain returns the prior result (`replay`)
    /// instead of double-spending the web balance.
    func drainWebGavels(appAccountToken: UUID, gavels: Int,
                        idempotencyKey: String) async -> BackendResult<Int> {
        struct Response: Decodable { let ok: Bool; let spent: Int? }
        let body: [String: Any] = [
            "userId": appAccountToken.uuidString.lowercased(),
            "gavels": gavels,
            "reason": "drain-to-app-wallet",
            "idempotencyKey": idempotencyKey,
        ]
        return await post("/consume", base: consumablesURL, body: body, as: Response.self)
            .map { $0.spent ?? gavels }
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, base: String? = nil, as type: T.Type) async -> BackendResult<T> {
        await request(path: path, method: "GET", body: nil, baseOverride: base, as: type)
    }

    private func post<T: Decodable>(_ path: String, base: String? = nil, body: [String: Any], as type: T.Type) async -> BackendResult<T> {
        await request(path: path, method: "POST", body: body, baseOverride: base, as: type)
    }

    private func request<T: Decodable>(path: String, method: String,
                                       body: [String: Any]?, baseOverride: String? = nil,
                                       as type: T.Type) async -> BackendResult<T> {
        let rawBase = baseOverride ?? workerURL
        guard !rawBase.trimmingCharacters(in: .whitespaces).isEmpty,
              !sharedSecret.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .failure("Backend not configured — set the Worker URL and shared secret first.")
        }
        let base = rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase
        guard let url = URL(string: "\(base)\(path)") else {
            return .failure("Worker URL looks malformed: '\(rawBase)'.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                // Workers use two failure shapes: `{error: "…"}` on plain
                // errors and `{ok:false, reason:"…"}` on domain failures like
                // /consume's 402 insufficient_gavels. Read both, or the
                // caller only ever sees "HTTP 402" and can't branch on why.
                let decoded = try? JSONDecoder().decode(BackendWorkerError.self, from: data)
                let message = decoded?.error ?? decoded?.reason ?? "HTTP \(status)"
                ErrorMonitor.shared.record(category: "Backend",
                                           message: "\(method) \(path) failed", detail: message)
                return .failure(message)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return .success(decoded)
        } catch {
            ErrorMonitor.shared.record(category: "Backend",
                                       message: "\(method) \(path) failed", error: error)
            return .failure(error.localizedDescription)
        }
    }
}
