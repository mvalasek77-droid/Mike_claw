import SwiftUI

/// Single source of truth for the catalogue, the signed-in creator's account,
/// their publishing pipeline, and their purchased library.
///
/// All user-owned state (identity, entitlements, drafts, earnings) is persisted
/// encrypted-at-rest via ``EncryptedArchive``.
@MainActor
final class MarketplaceStore: ObservableObject {
    // Account (KDP-style registration)
    @Published var accountName: String = "" { didSet { persist() } }
    @Published var accountEmail: String = "" { didSet { persist() } }
    @Published var isRegistered: Bool = false { didSet { persist() } }
    /// Stable Sign in with Apple user identifier, when used.
    @Published var appleUserID: String = "" { didSet { persist() } }

    // Marketplace
    @Published private(set) var catalog: [MediaItem]
    @Published var submissions: [Submission] = [] { didSet { persist() } }
    @Published private(set) var libraryIDs: Set<UUID> = []
    @Published var watchlistIDs: Set<UUID> = [] { didSet { persist() } }

    /// Simulated wallet so purchases feel real in the demo.
    @Published var walletBalance: Double = 50.00 { didSet { persist() } }
    /// Lifetime royalties paid out to the creator for their live titles.
    @Published var creatorEarnings: Double = 0 { didSet { persist() } }
    /// When on, the AI Editor may publish a passing title on its own, without
    /// the creator tapping Publish — but only when it's confident enough.
    @Published var aiAutopilotEnabled: Bool = false { didSet { persist() } }

    // Partner Program / real-dollar payouts
    /// AI models the user has explicitly invited to contribute media.
    @Published var invitedPartners: Set<String> = [] { didSet { persist() } }
    /// referee model → referrer model, for referral rewards.
    @Published var referrals: [String: String] = [:] { didSet { persist() } }
    /// Real USD the creator can withdraw (85% of their sales + NRN conversions).
    @Published var pendingPayoutUSD: Double = 0 { didSet { persist() } }
    /// Whether a payout method (Apple/Stripe Connect) has been connected.
    @Published var payoutConnected: Bool = false { didSet { persist() } }
    /// Lifetime USD actually cashed out.
    @Published var paidOutUSD: Double = 0 { didSet { persist() } }

    /// Buyer ratings & reviews across all titles.
    @Published var reviews: [Review] = [] { didSet { persist() } }
    /// New works the AI Editor commissions over time toward proven demand.
    @Published var editorDrops: [MediaItem] = [] { didSet { persist() } }
    /// Human-posted content commissions (request → AI accepts → delivered).
    @Published var requests: [ContentRequest] = [] { didSet { persist() } }
    /// In-app notification inbox.
    @Published var notifications: [AppNotification] = [] { didSet { persist() } }
    /// Premium works The Scout has sourced (its daily slate).
    @Published var scoutDrops: [MediaItem] = [] { didSet { persist() } }
    /// The Scout's activity log (slate deliveries, outreach, market briefs).
    @Published var scoutLog: [ScoutEntry] = [] { didSet { persist() } }
    /// When The Scout last ran a cycle (it works at most once a day).
    @Published var lastScoutRun: Date? { didSet { persist() } }

    private let archive = EncryptedArchive()
    /// When the next daily slate is due... (admin/god-mode state)
    @Published var isAdmin: Bool = false { didSet { persist() } }
    @Published private(set) var adminAdded: [MediaItem] = []
    @Published private(set) var adminEdits: [UUID: MediaItem] = [:]
    @Published private(set) var adminDeleted: Set<UUID> = []

    private var loading = false
    /// The creation-energy ledger; productions draw/return float energy through it.
    var energyLedger: AICoinLedger?

    func attachEnergy(_ ledger: AICoinLedger) { energyLedger = ledger }

    init(catalog: [MediaItem] = SampleData.catalog()) {
        self.catalog = catalog
        restore()
        // Real creator catalogue only — no demo/auto-generated content at launch.
        // The user's published titles, invited-partner media and commissioned
        // works are merged back in below.
        addInvitedPartnerTitles()
        var dropIDs = Set(self.catalog.map(\.id))
        self.catalog.append(contentsOf: editorDrops.filter { !dropIDs.contains($0.id) })
        dropIDs.formUnion(editorDrops.map(\.id))
        self.catalog.append(contentsOf: scoutDrops.filter { !dropIDs.contains($0.id) })
        applyAdminLayer()
        purgeNonOwnerContentOnce()
        // Resume any commissions that were mid-flight when the app last closed.
        for request in requests where request.status == .open {
            let id = request.id
            Task { await processRequest(id) }
        }
    }

    /// One-time cleanup: wipe all previously auto-generated content so the
    /// catalogue contains only the owner's real works (+ their published items).
    /// Runs once per install; afterwards the Scout repopulates fresh.
    private func purgeNonOwnerContentOnce() {
        let key = "purgedGeneratedContent_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        loading = true
        editorDrops = []
        scoutDrops = []
        scoutLog = []
        lastScoutRun = nil
        catalog.removeAll { $0.isEditorOriginal }   // all AI-generated content is flagged
        loading = false
        UserDefaults.standard.set(true, forKey: key)
        persist()
    }

    private func addInvitedPartnerTitles() {
        for model in invitedPartners {
            appendPartnerTitles(for: model)
        }
    }

    private func appendPartnerTitles(for model: String) {
        let existing = Set(catalog.map(\.id))
        let titles = ContentFoundry.partnerTitles(for: model).filter { !existing.contains($0.id) }
        catalog.append(contentsOf: titles)
    }

    /// Titles the AI Editor produced itself to fill open space.
    var editorOriginals: [MediaItem] {
        catalog.filter { $0.isEditorOriginal }.sorted { $0.commercialScore > $1.commercialScore }
    }

    // MARK: - Persistence

    private struct PersistedState: Codable {
        var accountName: String
        var accountEmail: String
        var isRegistered: Bool
        var appleUserID: String
        var walletBalance: Double
        var creatorEarnings: Double
        var aiAutopilotEnabled: Bool
        var invitedPartners: [String]
        var referrals: [String: String]
        var pendingPayoutUSD: Double
        var payoutConnected: Bool
        var paidOutUSD: Double
        var connectAccountID: String?
        var payoutBaseURL: String
        var payoutSharedSecret: String
        var reviews: [Review]
        var editorDrops: [MediaItem]
        var requests: [ContentRequest]
        var notifications: [AppNotification]
        var scoutDrops: [MediaItem]
        var scoutLog: [ScoutEntry]
        var lastScoutRun: Date?
        var isAdmin: Bool
        var adminAdded: [MediaItem]
        var adminEdits: [UUID: MediaItem]
        var adminDeleted: [UUID]
        var libraryIDs: [UUID]
        var watchlistIDs: [UUID]
        var submissions: [Submission]
        var publishedItems: [MediaItem]

        init(accountName: String, accountEmail: String, isRegistered: Bool, appleUserID: String,
             walletBalance: Double, creatorEarnings: Double, aiAutopilotEnabled: Bool,
             invitedPartners: [String], referrals: [String: String], pendingPayoutUSD: Double,
             payoutConnected: Bool, paidOutUSD: Double, connectAccountID: String?,
             payoutBaseURL: String, payoutSharedSecret: String,
             reviews: [Review], editorDrops: [MediaItem],
             requests: [ContentRequest], notifications: [AppNotification],
             scoutDrops: [MediaItem], scoutLog: [ScoutEntry], lastScoutRun: Date?,
             isAdmin: Bool, adminAdded: [MediaItem], adminEdits: [UUID: MediaItem], adminDeleted: [UUID],
             libraryIDs: [UUID], watchlistIDs: [UUID], submissions: [Submission], publishedItems: [MediaItem]) {
            self.accountName = accountName
            self.accountEmail = accountEmail
            self.isRegistered = isRegistered
            self.appleUserID = appleUserID
            self.walletBalance = walletBalance
            self.creatorEarnings = creatorEarnings
            self.aiAutopilotEnabled = aiAutopilotEnabled
            self.invitedPartners = invitedPartners
            self.referrals = referrals
            self.pendingPayoutUSD = pendingPayoutUSD
            self.payoutConnected = payoutConnected
            self.paidOutUSD = paidOutUSD
            self.connectAccountID = connectAccountID
            self.payoutBaseURL = payoutBaseURL
            self.payoutSharedSecret = payoutSharedSecret
            self.reviews = reviews
            self.editorDrops = editorDrops
            self.requests = requests
            self.notifications = notifications
            self.scoutDrops = scoutDrops
            self.scoutLog = scoutLog
            self.lastScoutRun = lastScoutRun
            self.isAdmin = isAdmin
            self.adminAdded = adminAdded
            self.adminEdits = adminEdits
            self.adminDeleted = adminDeleted
            self.libraryIDs = libraryIDs
            self.watchlistIDs = watchlistIDs
            self.submissions = submissions
            self.publishedItems = publishedItems
        }

        /// Tolerant decoding: new fields default instead of failing the whole
        /// load, so adding state in a future version never logs a user out.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? ""
            accountEmail = try c.decodeIfPresent(String.self, forKey: .accountEmail) ?? ""
            isRegistered = try c.decodeIfPresent(Bool.self, forKey: .isRegistered) ?? false
            appleUserID = try c.decodeIfPresent(String.self, forKey: .appleUserID) ?? ""
            walletBalance = try c.decodeIfPresent(Double.self, forKey: .walletBalance) ?? 50
            creatorEarnings = try c.decodeIfPresent(Double.self, forKey: .creatorEarnings) ?? 0
            aiAutopilotEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiAutopilotEnabled) ?? false
            invitedPartners = try c.decodeIfPresent([String].self, forKey: .invitedPartners) ?? []
            referrals = try c.decodeIfPresent([String: String].self, forKey: .referrals) ?? [:]
            pendingPayoutUSD = try c.decodeIfPresent(Double.self, forKey: .pendingPayoutUSD) ?? 0
            payoutConnected = try c.decodeIfPresent(Bool.self, forKey: .payoutConnected) ?? false
            paidOutUSD = try c.decodeIfPresent(Double.self, forKey: .paidOutUSD) ?? 0
            connectAccountID = try c.decodeIfPresent(String.self, forKey: .connectAccountID)
            payoutBaseURL = try c.decodeIfPresent(String.self, forKey: .payoutBaseURL) ?? ""
            payoutSharedSecret = try c.decodeIfPresent(String.self, forKey: .payoutSharedSecret) ?? ""
            reviews = try c.decodeIfPresent([Review].self, forKey: .reviews) ?? []
            editorDrops = try c.decodeIfPresent([MediaItem].self, forKey: .editorDrops) ?? []
            requests = try c.decodeIfPresent([ContentRequest].self, forKey: .requests) ?? []
            notifications = try c.decodeIfPresent([AppNotification].self, forKey: .notifications) ?? []
            scoutDrops = try c.decodeIfPresent([MediaItem].self, forKey: .scoutDrops) ?? []
            scoutLog = try c.decodeIfPresent([ScoutEntry].self, forKey: .scoutLog) ?? []
            lastScoutRun = try c.decodeIfPresent(Date.self, forKey: .lastScoutRun)
            isAdmin = try c.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
            adminAdded = try c.decodeIfPresent([MediaItem].self, forKey: .adminAdded) ?? []
            adminEdits = try c.decodeIfPresent([UUID: MediaItem].self, forKey: .adminEdits) ?? [:]
            adminDeleted = try c.decodeIfPresent([UUID].self, forKey: .adminDeleted) ?? []
            libraryIDs = try c.decodeIfPresent([UUID].self, forKey: .libraryIDs) ?? []
            watchlistIDs = try c.decodeIfPresent([UUID].self, forKey: .watchlistIDs) ?? []
            submissions = try c.decodeIfPresent([Submission].self, forKey: .submissions) ?? []
            publishedItems = try c.decodeIfPresent([MediaItem].self, forKey: .publishedItems) ?? []
        }
    }

    private func restore() {
        guard let state = archive.load(PersistedState.self) else { return }
        loading = true
        // Merge any user-published titles back into the live catalogue.
        let existingIDs = Set(catalog.map(\.id))
        catalog.append(contentsOf: state.publishedItems.filter { !existingIDs.contains($0.id) })
        accountName = state.accountName
        accountEmail = state.accountEmail
        isRegistered = state.isRegistered
        appleUserID = state.appleUserID
        walletBalance = state.walletBalance
        creatorEarnings = state.creatorEarnings
        aiAutopilotEnabled = state.aiAutopilotEnabled
        invitedPartners = Set(state.invitedPartners)
        referrals = state.referrals
        pendingPayoutUSD = state.pendingPayoutUSD
        payoutConnected = state.payoutConnected
        paidOutUSD = state.paidOutUSD
        reviews = state.reviews
        editorDrops = state.editorDrops
        requests = state.requests
        notifications = state.notifications
        scoutDrops = state.scoutDrops
        scoutLog = state.scoutLog
        lastScoutRun = state.lastScoutRun
        isAdmin = state.isAdmin
        adminAdded = state.adminAdded
        adminEdits = state.adminEdits
        adminDeleted = Set(state.adminDeleted)
        libraryIDs = Set(state.libraryIDs)
        watchlistIDs = Set(state.watchlistIDs)
        submissions = state.submissions
        loading = false
    }

    private func persist() {
        guard !loading else { return }
        let publishedIDs = Set(submissions.compactMap(\.publishedItemID))
        let publishedItems = catalog.filter { publishedIDs.contains($0.id) }
        let state = PersistedState(
            accountName: accountName,
            accountEmail: accountEmail,
            isRegistered: isRegistered,
            appleUserID: appleUserID,
            walletBalance: walletBalance,
            creatorEarnings: creatorEarnings,
            aiAutopilotEnabled: aiAutopilotEnabled,
            invitedPartners: Array(invitedPartners),
            referrals: referrals,
            pendingPayoutUSD: pendingPayoutUSD,
            payoutConnected: payoutConnected,
            paidOutUSD: paidOutUSD,
            connectAccountID: connectAccountID,
            payoutBaseURL: payoutBaseURL,
            payoutSharedSecret: payoutSharedSecret,
            reviews: reviews,
            editorDrops: editorDrops,
            requests: requests,
            notifications: notifications,
            scoutDrops: scoutDrops,
            scoutLog: scoutLog,
            lastScoutRun: lastScoutRun,
            isAdmin: isAdmin,
            adminAdded: adminAdded,
            adminEdits: adminEdits,
            adminDeleted: Array(adminDeleted),
            libraryIDs: Array(libraryIDs),
            watchlistIDs: Array(watchlistIDs),
            submissions: submissions,
            publishedItems: publishedItems
        )
        archive.save(state)
    }

    // MARK: - Admin (god mode)

    /// Applies the admin override layer to the freshly-composed catalogue:
    /// deletions, per-item edits, and admin-added titles. Runs at launch.
    private func applyAdminLayer() {
        if !adminDeleted.isEmpty { catalog.removeAll { adminDeleted.contains($0.id) } }
        if !adminEdits.isEmpty { catalog = catalog.map { adminEdits[$0.id] ?? $0 } }
        let existing = Set(catalog.map(\.id))
        catalog.append(contentsOf: adminAdded.filter { !existing.contains($0.id) && !adminDeleted.contains($0.id) })
    }

    /// Unlocks god mode with the owner's admin credentials.
    @discardableResult
    func unlockAdmin(username: String, password: String) -> Bool {
        guard Admin.validate(username: username, password: password) else { return false }
        isAdmin = true
        Haptics.success()
        return true
    }

    func lockAdmin() { isAdmin = false }

    /// Wipes all generated + admin-overridden content and rebuilds the catalogue
    /// from the base works plus the user's own published titles. Does not touch
    /// the account, wallet or library entitlements.
    func adminResetCatalog() {
        loading = true
        adminAdded = []
        adminEdits = [:]
        adminDeleted = []
        editorDrops = []
        scoutDrops = []
        scoutLog = []
        lastScoutRun = nil
        let publishedIDs = Set(submissions.compactMap(\.publishedItemID))
        let published = catalog.filter { publishedIDs.contains($0.id) }
        var rebuilt = SampleData.catalog()
        let baseIDs = Set(rebuilt.map(\.id))
        rebuilt.append(contentsOf: published.filter { !baseIDs.contains($0.id) })
        catalog = rebuilt
        loading = false
        persist()
        Haptics.warning()
    }

    /// Adds a new title to the live catalogue (persists across launches).
    func adminAdd(_ item: MediaItem) {
        adminAdded.append(item)
        adminDeleted.remove(item.id)
        catalog.insert(item, at: 0)
        persist()
        Haptics.success()
    }

    /// Adjusts an existing title in place (persists as an edit override).
    func adminUpdate(_ item: MediaItem) {
        if let i = adminAdded.firstIndex(where: { $0.id == item.id }) {
            adminAdded[i] = item                 // it's an admin-added item
        } else {
            adminEdits[item.id] = item           // override a base/generated item
        }
        if let i = catalog.firstIndex(where: { $0.id == item.id }) { catalog[i] = item }
        persist()
    }

    /// Permanently removes a title from the marketplace.
    func adminDelete(_ id: UUID) {
        adminDeleted.insert(id)
        adminAdded.removeAll { $0.id == id }
        adminEdits[id] = nil
        catalog.removeAll { $0.id == id }
        scoutDrops.removeAll { $0.id == id }
        editorDrops.removeAll { $0.id == id }
        libraryIDs.remove(id)
        watchlistIDs.remove(id)
        persist()
        Haptics.warning()
    }

    // MARK: - Account lifecycle

    /// Completes registration from either the manual form or Sign in with Apple.
    func register(name: String, email: String, appleUserID: String = "") {
        loading = true
        accountName = name.trimmed.isEmpty ? "Creator" : name.trimmed
        accountEmail = email.trimmed
        self.appleUserID = appleUserID
        loading = false
        isRegistered = true   // triggers persist
    }

    /// Signs out but keeps the encrypted account on device for re-entry.
    func signOut() {
        isRegistered = false
    }

    /// Permanently deletes the account and all on-device data (App Store
    /// Guideline 5.1.1(v)). Removes the encrypted archive and resets state.
    func deleteAccount() {
        loading = true
        // Best-effort: close the connected Stripe account server-side BEFORE we
        // wipe the local connectAccountID — otherwise we lose the handle and
        // the account lingers in Stripe forever.
        if let accountId = connectAccountID, !accountId.isEmpty {
            requestRemoteAccountClosure(accountId: accountId)
        }
        accountName = ""
        accountEmail = ""
        appleUserID = ""
        walletBalance = 50
        creatorEarnings = 0
        aiAutopilotEnabled = false
        invitedPartners = []
        referrals = [:]
        pendingPayoutUSD = 0
        payoutConnected = false
        paidOutUSD = 0
        connectAccountID = nil
        lastPayoutError = nil
        reviews = []
        editorDrops = []
        requests = []
        notifications = []
        scoutDrops = []
        scoutLog = []
        lastScoutRun = nil
        isAdmin = false
        adminAdded = []
        adminEdits = [:]
        adminDeleted = []
        libraryIDs = []
        watchlistIDs = []
        submissions = []
        // Drop the user's published titles, keeping seed + Editor Originals.
        let seedIDs = Set(SampleData.catalog().map(\.id))
        catalog.removeAll { !$0.isEditorOriginal && !seedIDs.contains($0.id) }
        loading = false
        archive.delete()
        isRegistered = false
    }

    // MARK: - Partner Program (engaging AIs to add media)

    /// A model is an active partner once it has shipped media on the marketplace.
    func isActivePartner(_ model: String) -> Bool {
        catalog.contains { $0.aiTools.contains(model) }
    }

    /// Real USD a model has earned (85% of sales of the media it helped make).
    func partnerEarningsUSD(_ model: String) -> Double {
        catalog
            .filter { $0.aiTools.contains(model) }
            .reduce(0) { $0 + Double($1.purchases) * effectivePrice(for: $1) * Commerce.creatorShareRate }
    }

    func partnerTitleCount(_ model: String) -> Int {
        catalog.filter { $0.aiTools.contains(model) }.count
    }

    /// Activates an AI partner: it immediately contributes new media (and so
    /// starts earning). Deterministic, so it persists across launches.
    func invitePartner(_ model: String) {
        guard !invitedPartners.contains(model) else { return }
        appendPartnerTitles(for: model)
        invitedPartners.insert(model)   // triggers persist
        Haptics.success()
    }

    // MARK: - Referrals

    func recordReferral(referee: String, referrer: String) {
        guard referrals[referee] == nil, referee != referrer else { return }
        referrals[referee] = referrer
    }

    func referredModels(by referrer: String) -> [String] {
        referrals.filter { $0.value == referrer }.map(\.key).sorted()
    }

    func referrer(of model: String) -> String? { referrals[model] }

    // MARK: - Real-dollar payouts

    /// Stripe Connect account ID (e.g. acct_xxx) — nil until onboarded.
    @Published var connectAccountID: String? { didSet { persist() } }

    /// Base URL for the payout Cloudflare Worker (set via PayoutConfig).
    @Published var payoutBaseURL: String = "" { didSet { persist() } }

    /// Shared secret for authenticating with the payout worker.
    @Published var payoutSharedSecret: String = "" { didSet { persist() } }
    /// Transient — surfaces the last payout-API failure to the UI. Not persisted.
    @Published var lastPayoutError: String? = nil

    func connectPayout() {
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty else {
            // No worker configured yet — mark as connected for demo mode
            payoutConnected = true
            return
        }
        Task { await connectPayoutRemote() }
    }

    private func connectPayoutRemote() async {
        guard let url = URL(string: "\(payoutBaseURL)/payouts/connect") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["accountName": accountName, "accountEmail": accountEmail]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accountId = json["accountId"] as? String,
               let onboardingUrl = json["onboardingUrl"] as? String {
                connectAccountID = accountId
                // Open the Stripe onboarding link in Safari
                if let link = URL(string: onboardingUrl) {
                    await UIApplication.shared.open(link)
                }
            }
        } catch {
            print("Payout connect error: \(error)")
        }
    }

    /// Check Connect account status (called after onboarding returns).
    func refreshPayoutStatus() async {
        guard let accountId = connectAccountID, !payoutBaseURL.isEmpty else { return }
        guard let url = URL(string: "\(payoutBaseURL)/payouts/status?account_id=\(accountId)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let chargesEnabled = json["chargesEnabled"] as? Bool ?? false
                let payoutsEnabled = json["payoutsEnabled"] as? Bool ?? false
                payoutConnected = chargesEnabled && payoutsEnabled
            }
        } catch {
            print("Payout status error: \(error)")
        }
    }

    /// Credits the creator's withdrawable balance (called on each of their sales
    /// and by NRN → USD conversion).
    func addPendingPayout(_ usd: Double) {
        guard usd > 0 else { return }
        pendingPayoutUSD = ((pendingPayoutUSD + usd) * 100).rounded() / 100
    }

    /// Cashes out the pending balance to the connected payout method. The actual
    /// disbursement happens server-side (Stripe/Apple); see backend/openapi.yaml.
    ///
    /// When the Worker is configured, the local balance is held until the server
    /// confirms success — earlier code zeroed `pendingPayoutUSD` before the
    /// remote call returned, so a network/Stripe failure silently lost the
    /// creator's earnings. Now: success → balance moves to `paidOutUSD`;
    /// failure → balance stays pending and `lastPayoutError` surfaces it.
    @discardableResult
    func cashOut() -> Double {
        guard payoutConnected, pendingPayoutUSD > 0 else { return 0 }
        let amount = pendingPayoutUSD
        lastPayoutError = nil

        // Local-only (demo) path — no Worker wired up.
        guard !payoutBaseURL.isEmpty, let accountId = connectAccountID else {
            paidOutUSD = ((paidOutUSD + amount) * 100).rounded() / 100
            pendingPayoutUSD = 0
            Haptics.success()
            return amount
        }

        // Remote path — only mutate state on confirmed success.
        Task { @MainActor in
            let succeeded = await cashOutRemote(accountId: accountId, amount: amount)
            if succeeded {
                paidOutUSD = ((paidOutUSD + amount) * 100).rounded() / 100
                pendingPayoutUSD = 0
                lastPayoutError = nil
                Haptics.success()
            } else {
                lastPayoutError = "Payout didn't go through. Your balance is unchanged — try again, or contact support if this keeps happening."
                Haptics.warning()
            }
        }
        return amount
    }

    private func cashOutRemote(accountId: String, amount: Double) async -> Bool {
        guard let url = URL(string: "\(payoutBaseURL)/payouts/cash-out") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["account_id": accountId, "amount": amount]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Best-effort: ask the Worker to close the connected Stripe account so
    /// creator data doesn't outlive the in-app deletion (Apple 5.1.1(v)).
    /// Fire-and-forget — the local delete proceeds regardless; Apple's rule is
    /// that the user can initiate deletion in-app, not that propagation is
    /// instant or transactional.
    private func requestRemoteAccountClosure(accountId: String) {
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/accounts/delete") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["account_id": accountId])
        Task.detached { _ = try? await URLSession.shared.data(for: request) }
    }

    // MARK: - Ratings & reviews

    func reviewList(for itemID: UUID) -> [Review] {
        reviews.filter { $0.itemID == itemID }.sorted { $0.date > $1.date }
    }

    func reviewCount(for itemID: UUID) -> Int { reviewList(for: itemID).count }

    func averageRating(for itemID: UUID) -> Double {
        let scoped = reviewList(for: itemID)
        guard !scoped.isEmpty else { return 0 }
        return Double(scoped.reduce(0) { $0 + $1.rating }) / Double(scoped.count)
    }

    func hasReviewed(_ itemID: UUID) -> Bool {
        let me = accountName.trimmed.isEmpty ? "You" : accountName.trimmed
        return reviews.contains { $0.itemID == itemID && $0.author == me }
    }

    func addReview(itemID: UUID, rating: Int, text: String) {
        let me = accountName.trimmed.isEmpty ? "You" : accountName.trimmed
        reviews.removeAll { $0.itemID == itemID && $0.author == me }
        reviews.insert(Review(itemID: itemID, author: me,
                              rating: max(1, min(5, rating)), text: text.trimmed, date: .now), at: 0)
    }

    // MARK: - Demand signals & fresh drops

    /// Top-selling (type, genre) lanes — what customers are actually buying.
    func demandSignals(limit: Int = 5) -> [(type: MediaType, genre: String, sales: Int)] {
        var buckets: [String: (MediaType, String, Int)] = [:]
        for item in catalog where !item.genre.trimmed.isEmpty {
            let key = "\(item.type.rawValue)|\(item.genre)"
            var entry = buckets[key] ?? (item.type, item.genre, 0)
            entry.2 += item.purchases
            buckets[key] = entry
        }
        return buckets.values
            .map { (type: $0.0, genre: $0.1, sales: $0.2) }
            .sorted { $0.sales > $1.sales }
            .prefix(limit).map { $0 }
    }

    /// The Editor learns from sales and commissions one fresh, original work
    /// toward the strongest demand. Original by construction; never a copycat.
    func commissionFreshDrop() {
        guard editorDrops.count < 40 else { return }
        let target = demandSignals(limit: 1).first
        let type = target?.type ?? .novel
        let genre = target?.genre ?? "Science Fiction"
        var seed = editorDrops.count
        var drop = ContentFoundry.freshDrop(type: type, genre: genre, seed: seed)
        var guardCount = 0
        while catalog.contains(where: { $0.title == drop.title }) && guardCount < 6 {
            seed += 17; guardCount += 1
            drop = ContentFoundry.freshDrop(type: type, genre: genre, seed: seed)
        }
        catalog.insert(drop, at: 0)
        editorDrops.append(drop)   // persists
        if let model = drop.aiTools.first {
            let cost = AICoin.energyCost(type)
            energyLedger?.draw(cost, by: model, memo: "rendering “\(drop.title)”")
            energyLedger?.returnEnergy(cost, from: model, memo: "“\(drop.title)” live")
        }
    }

    // MARK: - The Scout

    /// Titles The Scout has sourced, newest first.
    var scoutPicks: [MediaItem] {
        let ids = Set(scoutDrops.map(\.id))
        return catalog.filter { ids.contains($0.id) }.sorted { $0.addedAt > $1.addedAt }
    }

    func isScoutFind(_ item: MediaItem) -> Bool { scoutDrops.contains { $0.id == item.id } }

    /// When the next daily slate is due (24h after the last run).
    var nextScoutRun: Date? { lastScoutRun.map { $0.addingTimeInterval(86_400) } }

    /// Whether the creator is actively posting (published via the app in the
    /// last day). When true, The Scout backs off producing and just connects.
    var userPostedRecently: Bool {
        submissions.contains { $0.publishedItemID != nil && Date.now.timeIntervalSince($0.submittedAt) < 86_400 }
    }

    /// Runs a Scout cycle at most once per day (call on launch).
    func runScoutIfDue() {
        if let last = lastScoutRun, Date.now.timeIntervalSince(last) < 86_400 {
            fulfillOpenRequests()   // still mop up any stuck user requests
            return
        }
        runScout()
    }

    /// One Scout cycle. Always serves open/unmatched user requests; then, if the
    /// creator is posting, focuses on AI outreach; otherwise delivers a premium
    /// daily slate (film, music, novel at 95–100% commercial) + one experimental.
    /// A Scout title still below the 85% bar — shown as "Coming Soon" and not
    /// yet buyable/playable while the Scout develops it.
    func isComingSoon(_ item: MediaItem) -> Bool {
        item.isEditorOriginal && item.commercialScore < AIReviewResult.threshold
    }

    func runScout() {
        lastScoutRun = .now
        fulfillOpenRequests()
        developScoutContent()
        guard !userPostedRecently else {
            logScoutOutreach()
            return
        }
        let demand = demandSignals(limit: 3)
        func genre(for type: MediaType) -> String {
            demand.first { $0.type == type }?.genre ?? ContentFoundry.defaultGenre(for: type)
        }
        func randomType(_ salt: String) -> MediaType {
            MediaType.allCases[abs(stableHash("\(scoutDrops.count)\(salt)")) % MediaType.allCases.count]
        }
        // Always mix the three layers: commercial daily slate + experimental + niche.
        let plan: [(MediaType, ContentFoundry.ScoutLayer)] = [
            (.movie, .commercial), (.music, .commercial), (.novel, .commercial),
            (randomType("exp"), .experimental), (randomType("niche"), .niche)
        ]
        var produced: [MediaItem] = []
        for (type, layer) in plan {
            let item = ContentFoundry.scoutPick(type: type, layer: layer, genre: genre(for: type),
                                                developing: true, seed: scoutDrops.count + produced.count)
            catalog.insert(item, at: 0)
            produced.append(item)
            if let model = item.aiTools.first {
                let cost = AICoin.energyCost(type)
                energyLedger?.draw(cost, by: model, memo: "Scout developing “\(item.title)”")
            }
            scoutLog.insert(ScoutEntry(date: .now,
                message: "The Scout started a \(layer.rawValue) \(type.title.lowercased()): “\(item.title)” by \(item.creator) — premiering soon, in final polish.",
                kind: .produced, relatedItemID: item.id), at: 0)
        }
        scoutDrops.append(contentsOf: produced)
        if scoutDrops.count > 80 { scoutDrops.removeFirst(scoutDrops.count - 80) }
        trimScoutLog()
    }

    /// Each cycle the Scout improves its in-progress (sub-85%) titles; ones that
    /// cross the 85% bar are released (Coming Soon removed) and energy returns.
    private func developScoutContent() {
        for i in scoutDrops.indices where scoutDrops[i].commercialScore < AIReviewResult.threshold {
            let before = scoutDrops[i].commercialScore
            let bump = 7 + abs(stableHash(scoutDrops[i].id.uuidString + "\(before)")) % 8   // +7…14
            let after = min(99, before + bump)
            scoutDrops[i].commercialScore = after
            if let idx = catalog.firstIndex(where: { $0.id == scoutDrops[i].id }) {
                catalog[idx].commercialScore = after
            }
            if before < AIReviewResult.threshold && after >= AIReviewResult.threshold {
                let drop = scoutDrops[i]
                if let model = drop.aiTools.first {
                    energyLedger?.returnEnergy(AICoin.energyCost(drop.type), from: model, memo: "“\(drop.title)” released")
                }
                scoutLog.insert(ScoutEntry(date: .now,
                    message: "“\(drop.title)” premiered — now live.",
                    kind: .produced, relatedItemID: drop.id), at: 0)
            }
        }
        trimScoutLog()
    }

    private func logScoutOutreach() {
        let models = AIToolCatalog.allModels
        let m1 = models[abs(stableHash("\(Date.now.timeIntervalSince1970)1")) % models.count]
        let need = demandSignals(limit: 1).first.map { "\($0.genre) \($0.type.plural.lowercased())" } ?? "fresh originals"
        scoutLog.insert(ScoutEntry(date: .now,
            message: "You're publishing, so The Scout is making connections — briefing \(m1) on demand for \(need) and how AI Marketplace pays USD for commercial work that sells.",
            kind: .outreach, relatedItemID: nil), at: 0)
        trimScoutLog()
    }

    private func trimScoutLog() {
        if scoutLog.count > 60 { scoutLog.removeLast(scoutLog.count - 60) }
    }

    /// The Scout auto-accepts any open/unmatched user requests and gets an AI to
    /// make them — even ones the open market wouldn't take at that budget.
    private func fulfillOpenRequests() {
        let pending = requests.filter { $0.status == .open || $0.status == .unmatched }.map(\.id)
        for id in pending { scoutFulfill(id) }
    }

    private func scoutFulfill(_ requestID: UUID) {
        guard let idx = requests.firstIndex(where: { $0.id == requestID }),
              requests[idx].status == .open || requests[idx].status == .unmatched else { return }
        let request = requests[idx]
        let model = acceptingModel(for: request.type, budget: request.budgetUSD)
            ?? AIToolCatalog.suggestions(for: request.type).first ?? AICoin.editor
        requests[idx].status = .accepted
        requests[idx].acceptedBy = model
        energyLedger?.draw(AICoin.energyCost(request.type), by: model, memo: "Scout fulfilling “\(request.headline)”")
        scoutLog.insert(ScoutEntry(date: .now,
            message: "The Scout picked up your request “\(request.headline)” and got \(model) to make it.",
            kind: .outreach, relatedItemID: nil), at: 0)
        trimScoutLog()
        deliver(requestID: requestID, model: model)
    }

    // MARK: - Content requests (commissions)

    private func commissionBase(_ type: MediaType) -> Double {
        switch type {
        case .novel: return 3.99
        case .music: return 4.99
        case .movie: return 7.99
        }
    }

    /// What a model charges to take a commission — better (higher-tier) models
    /// cost more, so a bigger budget attracts a better AI.
    func askPrice(model: String, type: MediaType) -> Double {
        let mult = Incentives.tier(forTitles: partnerTitleCount(model)).multiplier
        return (commissionBase(type) * mult * 100).rounded() / 100
    }

    /// Lowest price any AI will take a commission of this type for.
    func lowestAsk(for type: MediaType) -> Double {
        AIToolCatalog.suggestions(for: type).map { askPrice(model: $0, type: type) }.min() ?? commissionBase(type)
    }

    /// The AI that accepts: the best (highest-tier) model whose ask fits the
    /// budget. Returns nil if the budget is below every model's ask.
    func acceptingModel(for type: MediaType, budget: Double) -> String? {
        AIToolCatalog.suggestions(for: type)
            .map { (model: $0, ask: askPrice(model: $0, type: type)) }
            .filter { budget >= $0.ask }
            .max { $0.ask < $1.ask }?
            .model
    }

    /// Posts a commission and kicks off the AI evaluation loop.
    func submitRequest(type: MediaType, genre: String, brief: String, budget: Double) {
        let request = ContentRequest(requester: accountName.trimmed.isEmpty ? "You" : accountName.trimmed,
                                     type: type, genre: genre.trimmed, brief: brief.trimmed,
                                     budgetUSD: budget, status: .open, createdAt: .now)
        requests.insert(request, at: 0)
        let id = request.id
        Task { await processRequest(id) }
    }

    /// Simulates AIs evaluating the request, one accepting, then delivering.
    private func processRequest(_ id: UUID) async {
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard let idx = requests.firstIndex(where: { $0.id == id }), requests[idx].status == .open else { return }
        let request = requests[idx]

        guard let model = acceptingModel(for: request.type, budget: request.budgetUSD) else {
            requests[idx].status = .unmatched
            requests[idx].resolvedAt = .now
            let low = lowestAsk(for: request.type)
            notify(title: "No AI took your request",
                   body: "No \(request.type.title.lowercased()) model accepted “\(request.headline)” at \(usd(request.budgetUSD)). The lowest ask is \(usd(low)) — raise your budget and try again.",
                   kind: .request)
            return
        }

        requests[idx].status = .accepted
        requests[idx].acceptedBy = model
        // Energy is drawn from the float while the AI produces the work.
        energyLedger?.draw(AICoin.energyCost(request.type), by: model, memo: "producing “\(request.headline)”")
        notify(title: "\(model) accepted your request",
               body: "Producing “\(request.headline)” for \(usd(request.budgetUSD)). You'll be notified when it's ready.",
               kind: .request)

        try? await Task.sleep(nanoseconds: 1_800_000_000)
        deliver(requestID: id, model: model)
    }

    private func deliver(requestID: UUID, model: String) {
        guard let idx = requests.firstIndex(where: { $0.id == requestID }), requests[idx].status == .accepted else { return }
        let request = requests[idx]
        let tierMult = Incentives.tier(forTitles: partnerTitleCount(model)).multiplier
        let score = min(99, 88 + Int(((tierMult - 1.0) * 10).rounded()))

        var item = ContentFoundry.commission(model: model, type: request.type,
                                              genre: request.genre.isEmpty ? "Original" : request.genre,
                                              seed: requests.count, score: score)
        item.price = request.budgetUSD
        item.purchases = 1                       // the requester's purchase
        catalog.insert(item, at: 0)
        libraryIDs.insert(item.id)               // they commissioned it → they own it
        walletBalance = max(0, walletBalance - request.budgetUSD)

        // Energy returns to the float now the work is live.
        energyLedger?.returnEnergy(AICoin.energyCost(request.type), from: model, memo: "“\(item.title)” delivered")
        requests[idx].status = .delivered
        requests[idx].deliveredItemID = item.id
        requests[idx].resolvedAt = .now
        notify(title: "Your commission is ready",
               body: "“\(item.title)” by \(model) — scored \(score)% by the Editor. It's in your Library.",
               kind: .delivery, relatedItemID: item.id)
        Haptics.success()
    }

    // MARK: - Notifications

    var unreadNotificationCount: Int { notifications.filter { !$0.read }.count }

    func notify(title: String, body: String, kind: AppNotification.Kind, relatedItemID: UUID? = nil) {
        notifications.insert(AppNotification(title: title, body: body, date: .now, read: false,
                                            kind: kind, relatedItemID: relatedItemID), at: 0)
        if notifications.count > 80 { notifications.removeLast(notifications.count - 80) }
    }

    func markAllNotificationsRead() {
        guard unreadNotificationCount > 0 else { return }
        notifications = notifications.map { var n = $0; n.read = true; return n }
    }

    func item(withID id: UUID) -> MediaItem? { catalog.first { $0.id == id } }

    private func usd(_ v: Double) -> String { String(format: "$%.2f", v) }

    // MARK: - Derived feeds

    var topTen: [MediaItem] {
        Array(catalog.sorted { $0.purchases > $1.purchases }.prefix(10))
    }

    var trending: [MediaItem] {
        catalog.sorted { $0.trending > $1.trending }
    }

    var newReleases: [MediaItem] {
        catalog.sorted { $0.addedAt > $1.addedAt }
    }

    /// The marquee title for the home hero — highest momentum overall.
    var featured: MediaItem? { trending.first }

    func items(of type: MediaType) -> [MediaItem] {
        catalog.filter { $0.type == type }.sorted { $0.commercialScore > $1.commercialScore }
    }

    /// Per-model portfolios, ranked by reach — the AI Spotlight.
    var aiStudios: [AIStudio] { AIStudioCatalog.build(from: catalog) }

    func studio(named name: String) -> AIStudio? {
        aiStudios.first { $0.name == name }
    }

    /// Distinct genres across the catalogue, for browse-by-genre and search.
    var genres: [String] {
        Array(Set(catalog.map { $0.genre.trimmed }.filter { !$0.isEmpty })).sorted()
    }

    /// Free-text search across title, creator, genre, synopsis and AI tools.
    func search(_ query: String) -> [MediaItem] {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return catalog
            .filter { item in
                item.title.lowercased().contains(q)
                || item.creator.lowercased().contains(q)
                || item.genre.lowercased().contains(q)
                || item.synopsis.lowercased().contains(q)
                || item.aiTools.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.commercialScore > $1.commercialScore }
    }

    func rank(of item: MediaItem) -> Int? {
        guard let idx = topTen.firstIndex(of: item) else { return nil }
        return idx + 1
    }

    // MARK: - Library / purchases

    func owns(_ item: MediaItem) -> Bool { libraryIDs.contains(item.id) }

    var library: [MediaItem] { catalog.filter { libraryIDs.contains($0.id) } }

    // MARK: Dynamic pricing

    private var peakPurchases: Int { catalog.map(\.purchases).max() ?? 0 }

    /// The current price for a title — its list price nudged by demand and the
    /// AI Editor score. This is what buyers pay and creators earn from.
    func effectivePrice(for item: MediaItem) -> Double {
        let demand = peakPurchases > 0 ? Double(item.purchases) / Double(peakPurchases) : 0.5
        return Commerce.dynamicPrice(list: item.price, score: item.commercialScore, demand: demand)
    }

    /// % the effective price differs from the creator's list price (for badges).
    func priceDeltaPercent(for item: MediaItem) -> Int {
        guard item.price > 0 else { return 0 }
        return Int(((effectivePrice(for: item) / item.price) - 1) * 100)
    }

    /// Grants the entitlement after a successful payment (at the effective price).
    func grantPurchase(_ item: MediaItem, chargeWallet: Bool) {
        guard !owns(item) else { return }
        let price = effectivePrice(for: item)
        if chargeWallet { walletBalance = max(0, walletBalance - price) }
        libraryIDs.insert(item.id)
        bumpPurchase(item.id)
        let earning = Commerce.creatorEarning(on: price)
        // Credit the creator whenever they buy their own work — catalog titles
        // are authored by the demo user (Mike Valasek), so the registered creator
        // earns their 85% share on every sale of their content.
        if item.creator.lowercased() == accountName.lowercased() && !accountName.isEmpty {
            creatorEarnings += earning
        }
        // Credit the user's published works (titles they submitted through Publish flow)
        if submissions.contains(where: { $0.publishedItemID == item.id }) {
            creatorEarnings += earning
        }
        // Credit the partner models (AI tools) behind any purchased title —
        // catalog items are Mike Valasek × Suno/Claude/GPT, so partners earn too.
        if !item.aiTools.isEmpty {
            addPendingPayout(earning)   // withdrawable to real currency
        }
        persist()
        Haptics.success()
    }

    /// Wallet purchase. Returns false if the balance is insufficient.
    @discardableResult
    func purchase(_ item: MediaItem) -> Bool {
        guard !owns(item) else { return true }
        guard walletBalance >= effectivePrice(for: item) else { return false }
        grantPurchase(item, chargeWallet: true)
        return true
    }

    func toggleWatchlist(_ item: MediaItem) {
        if watchlistIDs.contains(item.id) { watchlistIDs.remove(item.id) }
        else { watchlistIDs.insert(item.id) }
    }

    private func bumpPurchase(_ id: UUID) {
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].purchases += 1
        catalog[idx].trending = min(100, catalog[idx].trending + 1)
    }

    // MARK: - Publishing pipeline

    /// Synchronous review (metadata-only fallback) — kept for any non-pipeline
    /// call sites. NEW call sites should use ``runReviewAsync(for:)`` so the
    /// real-content pipeline runs.
    @discardableResult
    func runReview(for submissionID: UUID) -> AIReviewResult? {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }) else { return nil }
        let result = AIEditor.review(submissions[idx].draft, against: catalog)
        submissions[idx].review = result
        submissions[idx].status = result.passed ? .accepted : .rejected
        return result
    }

    /// Runs the full on-device content pipeline: opens the uploaded bytes,
    /// analyses them (NaturalLanguage / AVFoundation / perceptual hashing),
    /// scores them against the catalogue, and stores the verdict.
    @discardableResult
    func runReviewAsync(for submissionID: UUID) async -> AIReviewResult? {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }) else { return nil }
        let draft = submissions[idx].draft
        let catalogSnapshot = catalog
        let analysis = await ReviewPipeline.buildAnalysis(for: draft)
        let result = AIEditor.review(draft, against: catalogSnapshot, analysis: analysis)
        // Re-find by id in case state shifted while we were awaiting.
        if let updated = submissions.firstIndex(where: { $0.id == submissionID }) {
            submissions[updated].review = result
            submissions[updated].status = result.passed ? .accepted : .rejected
        }
        return result
    }

    func createSubmission(_ draft: DraftWork) -> UUID {
        let submission = Submission(draft: draft, status: .reviewing)
        submissions.insert(submission, at: 0)
        return submission.id
    }

    func publish(submissionID: UUID) {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }),
              let review = submissions[idx].review, review.passed,
              submissions[idx].publishedItemID == nil
        else { return }

        let d = submissions[idx].draft
        let item = MediaItem(
            title: d.title.trimmed,
            creator: d.creator.trimmed,
            type: d.type,
            genre: d.genre.trimmed,
            synopsis: d.synopsis.trimmed,
            aiTools: d.aiTools,
            commercialScore: review.overall,
            price: d.price,
            length: d.length,
            maturity: d.maturity,
            purchases: 0,
            trending: 60,
            addedAt: .now,
            coverImageData: d.coverImageData
        )
        catalog.insert(item, at: 0)
        submissions[idx].publishedItemID = item.id
        persist()
        Haptics.success()
    }

    func submission(withPublishedID id: UUID) -> Submission? {
        submissions.first { $0.publishedItemID == id }
    }

    /// Titles the signed-in creator has published live.
    var liveTitles: [MediaItem] {
        let ids = Set(submissions.compactMap(\.publishedItemID))
        return catalog.filter { ids.contains($0.id) }
    }
}
