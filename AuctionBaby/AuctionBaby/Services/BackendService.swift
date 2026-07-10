import Foundation
import Combine

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

    private static let urlKey = "auctionbaby.backend.url.v1"
    private static let secretKey = "auctionbaby.backend.secret.v1"

    init() {
        let savedURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        let savedSecret = UserDefaults.standard.string(forKey: Self.secretKey) ?? ""
        // Baked build config wins only when nothing was saved locally, so a
        // staging URL typed into the admin console survives relaunch.
        workerURL = savedURL.isEmpty ? BackendConfig.workerURL : savedURL
        sharedSecret = savedSecret.isEmpty ? BackendConfig.sharedSecret : savedSecret
    }

    var isConfigured: Bool {
        !workerURL.trimmingCharacters(in: .whitespaces).isEmpty
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

    /// POST /payouts/digest — manually email the payout digest.
    func triggerDigest() async -> BackendResult<String> {
        struct Response: Decodable { let accounts: Int; let owedUSD: Double }
        return await post("/payouts/digest", body: [:], as: Response.self).map { r in
            String(format: "Digest sent — %d owed, $%.2f total.", r.accounts, r.owedUSD)
        }
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> BackendResult<T> {
        await request(path: path, method: "GET", body: nil, as: type)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], as type: T.Type) async -> BackendResult<T> {
        await request(path: path, method: "POST", body: body, as: type)
    }

    private func request<T: Decodable>(path: String, method: String,
                                       body: [String: Any]?, as type: T.Type) async -> BackendResult<T> {
        guard isConfigured else {
            return .failure("Backend not configured — set the Worker URL and shared secret first.")
        }
        let base = workerURL.hasSuffix("/") ? String(workerURL.dropLast()) : workerURL
        guard let url = URL(string: "\(base)\(path)") else {
            return .failure("Worker URL looks malformed: '\(workerURL)'.")
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
                struct WorkerError: Decodable { let error: String }
                let message = (try? JSONDecoder().decode(WorkerError.self, from: data))?.error
                    ?? "HTTP \(status)"
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
