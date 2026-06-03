import SwiftUI

/// Simple error wrapper so Result<..., String> works (String doesn't conform to Error).
struct StringError: Error { let message: String }

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
    /// Apple App Review demo mode. When on, Stripe Connect is simulated
    /// locally (no Worker / no real bank info), credit purchases can be
    /// fulfilled without StoreKit, and the UI marks the session as DEMO
    /// MODE so reviewers can verify functionality without spending real
    /// money. Persists across launches so reviewers don't re-enable each
    /// session. See DEMO_MODE.md for the credentials.
    @Published var demoMode: Bool = false { didSet { persist() } }
    @Published var isRegistered: Bool = false { didSet { persist() } }

    // Marketplace
    @Published private(set) var catalog: [MediaItem]
    @Published var submissions: [Submission] = [] { didSet { persist() } }
    @Published private(set) var libraryIDs: Set<UUID> = []
    @Published var watchlistIDs: Set<UUID> = [] { didSet { persist() } }

    /// In-app wallet credit (USD). Funded only by Apple-IAP top-ups.
    @Published var walletBalance: Double = 0 { didSet { persist() } }
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
    /// In-flight video-render Tasks keyed by film id + scene index, so we can
    /// cancel them en-masse when admin disables Scout film creation. Each
    /// Task self-removes from this dict when it returns.
    private var sceneRenderTasks: [String: Task<Void, Never>] = [:]
    private func sceneRenderKey(_ itemID: UUID, _ sceneIndex: Int) -> String {
        "\(itemID.uuidString)#\(sceneIndex)"
    }
    private func cancelAllSceneRenderTasks() {
        for (_, task) in sceneRenderTasks { task.cancel() }
        sceneRenderTasks.removeAll()
    }
    /// When the next daily slate is due... (admin/god-mode state)
    @Published var isAdmin: Bool = false { didSet { persist() } }
    @Published private(set) var adminAdded: [MediaItem] = []
    @Published private(set) var adminEdits: [UUID: MediaItem] = [:]
    @Published private(set) var adminDeleted: Set<UUID> = []
    /// Admin master switch for Scout film production. Off → Scout still
    /// drafts novels and music but skips movies entirely (no proposals, no
    /// scene appends). On by default; admins can pause if budget runs low or
    /// they want the catalog to lean elsewhere.
    ///
    /// Flipping this OFF also cancels any in-flight video-gen Tasks so the
    /// admin's pause is honored immediately, not after the next render
    /// finishes (which could otherwise take 3+ minutes).
    @Published var scoutFilmCreationEnabled: Bool = true {
        didSet {
            persist()
            if !scoutFilmCreationEnabled { cancelAllSceneRenderTasks() }
        }
    }
    /// Monthly USD ceiling Scout may spend on external video-gen providers
    /// (Runway / Luma / Pika / Veo / Sora etc.). $0 means "on-device only —
    /// films remain screenplay-only until you raise the budget."
    @Published var scoutFilmBudgetUSD: Double = 0 { didSet { persist() } }

    /// Targets used by the feasibility check. ~10 scenes at 3 min/scene = 30 min.
    static let scoutFilmTargetScenes = 10
    static let scoutFilmTargetMinutes = 30

    /// Plain-English answer to "can $X actually buy me a 30+ min film?"
    /// Walks every available provider, picks the cheapest one that fits, and
    /// reports a verdict the admin can act on.
    func filmFeasibility(budget: Double) -> FilmFeasibility {
        let target = Self.scoutFilmTargetScenes
        let runtime = Self.scoutFilmTargetMinutes
        guard budget > 0 else {
            return FilmFeasibility(
                budgetUSD: 0,
                verdict: .onDeviceOnly,
                summary: "On-device only — Scout will ship screenplay editions, not real video.",
                detail: "Raise the budget to wire in external providers like Runway, Luma or Sora. Until then, films grow as screenplays that buyers read scene-by-scene."
            )
        }
        let providers = VideoProvider.catalog
        guard let cheapest = providers.min(by: { $0.costPerSceneUSD < $1.costPerSceneUSD }) else {
            return FilmFeasibility(budgetUSD: budget, verdict: .onDeviceOnly,
                                    summary: "No providers configured.",
                                    detail: "Add at least one provider to enable real-video film production.")
        }
        // Pick the cheapest provider that can deliver the full target. If
        // none can, fall back to the cheapest for a partial / insufficient
        // verdict.
        let fullFitsAt = providers
            .filter { $0.scenesAffordable(budget: budget) >= target }
            .min(by: { $0.costPerSceneUSD < $1.costPerSceneUSD })
        if let p = fullFitsAt {
            let cost = Double(target) * p.costPerSceneUSD
            return FilmFeasibility(
                budgetUSD: budget,
                verdict: .feasible(provider: p, scenes: target, runtimeMinutes: runtime, totalCostUSD: cost),
                summary: String(format: "Yes — $%.2f gets a full %d-min film via %@.", cost, runtime, p.displayName),
                detail: String(format: "%d scenes × $%.2f per scene = $%.2f total. %@ is the cheapest provider that fits the full %d-min target. (%@.)",
                               target, p.costPerSceneUSD, cost, p.displayName, runtime, p.strengths.joined(separator: ", "))
            )
        }
        // Partial path: the cheapest provider produces *some* scenes.
        let scenesCheap = cheapest.scenesAffordable(budget: budget)
        if scenesCheap >= 1 {
            let runtimeAchievable = scenesCheap * 3 // 3 min/scene avg
            let spent = Double(scenesCheap) * cheapest.costPerSceneUSD
            let shortfall = (Double(target) * cheapest.costPerSceneUSD) - budget
            return FilmFeasibility(
                budgetUSD: budget,
                verdict: .partial(provider: cheapest, scenes: scenesCheap, runtimeMinutes: runtimeAchievable, totalCostUSD: spent, shortfallUSD: max(0, shortfall)),
                summary: String(format: "Partial — only %d of %d scenes fit (~%d min). Add $%.2f for the full %d min via %@.",
                                scenesCheap, target, runtimeAchievable, shortfall, runtime, cheapest.displayName),
                detail: String(format: "With $%.2f at %@'s $%.2f per scene, Scout can ship %d scenes ≈ %d min. Add $%.2f to reach the full %d-min target.",
                               budget, cheapest.displayName, cheapest.costPerSceneUSD, scenesCheap, runtimeAchievable, shortfall, runtime)
            )
        }
        // Below even one scene.
        return FilmFeasibility(
            budgetUSD: budget,
            verdict: .insufficient(needAtLeastUSD: cheapest.costPerSceneUSD, cheapestProvider: cheapest),
            summary: String(format: "Too low — cheapest scene costs $%.2f via %@.", cheapest.costPerSceneUSD, cheapest.displayName),
            detail: String(format: "Even one scene at %@'s $%.2f doesn't fit a $%.2f budget. Either raise the budget or leave it at $0 to ship screenplay editions only.",
                           cheapest.displayName, cheapest.costPerSceneUSD, budget)
        )
    }

    private var loading = false
    /// The creation-energy ledger; productions draw/return float energy through it.
    var energyLedger: AICoinLedger?
    weak var scoutFeed: ScoutFeedService?

    func attachEnergy(_ ledger: AICoinLedger) { energyLedger = ledger }
    func attachScoutFeed(_ service: ScoutFeedService) {
        scoutFeed = service
        loadScoutProposals()
    }

    // MARK: - Scout proposals (admin-authorized production)

    /// Scout's pending + recent proposals. Persisted to UserDefaults so the
    /// queue survives launches without touching the encrypted archive.
    /// Lifecycle: pending → (authorized → produced | editorRejected) | declined.
    @Published private(set) var scoutProposals: [ScoutProposal] = [] {
        didSet { persistScoutProposals() }
    }

    private static let scoutProposalsDefaultsKey = "aimkt.scoutProposals.v1"

    var pendingScoutProposals: [ScoutProposal] {
        scoutProposals.filter { $0.status == .pending }
    }

    /// Total $ committed in pending + authorized-but-not-produced proposals.
    var pendingProposalBudgetUSD: Double {
        scoutProposals.filter { $0.status == .pending || $0.status == .authorized }
            .reduce(0) { $0 + $1.estimatedUSD }
    }

    private func loadScoutProposals() {
        guard let data = UserDefaults.standard.data(forKey: Self.scoutProposalsDefaultsKey),
              let decoded = try? JSONDecoder().decode([ScoutProposal].self, from: data) else { return }
        scoutProposals = decoded
    }

    private func persistScoutProposals() {
        if let data = try? JSONEncoder().encode(scoutProposals) {
            UserDefaults.standard.set(data, forKey: Self.scoutProposalsDefaultsKey)
        }
    }

    /// Admin authorizes a proposal — only admins can publish content. Kicks
    /// off the Editor-gated production pipeline; verdict updates the proposal
    /// to either .produced (with publishedItemID) or .editorRejected.
    func authorizeScoutProposal(_ proposal: ScoutProposal) {
        guard isAdmin else { return }
        guard let idx = scoutProposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        guard scoutProposals[idx].status == .pending else { return }
        scoutProposals[idx].status = .authorized
        let authorized = scoutProposals[idx]
        let snapshot = catalog
        Task { @MainActor [weak self] in
            await self?.produceFromProposal(authorized, catalogSnapshot: snapshot)
        }
    }

    /// Admin declines a proposal. Scout will compose new ones on the next cycle.
    func declineScoutProposal(_ proposal: ScoutProposal, note: String = "") {
        guard isAdmin else { return }
        guard let idx = scoutProposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        scoutProposals[idx].status = .declined
        scoutProposals[idx].statusNote = note.isEmpty ? "Declined by admin." : note
        scoutProposals[idx].resolvedAt = .now
    }

    /// Compact the proposal log so it doesn't grow forever.
    func clearResolvedScoutProposals() {
        guard isAdmin else { return }
        scoutProposals.removeAll {
            $0.status == .produced || $0.status == .declined || $0.status == .editorRejected
        }
    }

    init(catalog: [MediaItem] = SampleData.catalog()) {
        self.catalog = catalog
        restore()
        // Bundled Worker config — so creators never need to enter a URL
        // or a shared secret. If Info.plist has values and nothing was
        // already restored from the archive, adopt the bundled defaults.
        if payoutBaseURL.isEmpty, !BackendConfig.workerURL.isEmpty {
            payoutBaseURL = BackendConfig.workerURL
        }
        if payoutSharedSecret.isEmpty, !BackendConfig.sharedSecret.isEmpty {
            payoutSharedSecret = BackendConfig.sharedSecret
        }
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
        var demoMode: Bool
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
        var scoutFilmCreationEnabled: Bool
        var scoutFilmBudgetUSD: Double
        var isAdmin: Bool
        var adminAdded: [MediaItem]
        var adminEdits: [UUID: MediaItem]
        var adminDeleted: [UUID]
        var libraryIDs: [UUID]
        var watchlistIDs: [UUID]
        var submissions: [Submission]
        var publishedItems: [MediaItem]

        init(accountName: String, accountEmail: String, isRegistered: Bool, demoMode: Bool,
             walletBalance: Double, creatorEarnings: Double, aiAutopilotEnabled: Bool,
             invitedPartners: [String], referrals: [String: String], pendingPayoutUSD: Double,
             payoutConnected: Bool, paidOutUSD: Double, connectAccountID: String?,
             payoutBaseURL: String, payoutSharedSecret: String,
             reviews: [Review], editorDrops: [MediaItem],
             requests: [ContentRequest], notifications: [AppNotification],
             scoutDrops: [MediaItem], scoutLog: [ScoutEntry], lastScoutRun: Date?,
             scoutFilmCreationEnabled: Bool, scoutFilmBudgetUSD: Double,
             isAdmin: Bool, adminAdded: [MediaItem], adminEdits: [UUID: MediaItem], adminDeleted: [UUID],
             libraryIDs: [UUID], watchlistIDs: [UUID], submissions: [Submission], publishedItems: [MediaItem]) {
            self.accountName = accountName
            self.accountEmail = accountEmail
            self.isRegistered = isRegistered
            self.demoMode = demoMode
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
            self.scoutFilmCreationEnabled = scoutFilmCreationEnabled
            self.scoutFilmBudgetUSD = scoutFilmBudgetUSD
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
            demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? false
            walletBalance = try c.decodeIfPresent(Double.self, forKey: .walletBalance) ?? 0
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
            scoutFilmCreationEnabled = try c.decodeIfPresent(Bool.self, forKey: .scoutFilmCreationEnabled) ?? true
            scoutFilmBudgetUSD = try c.decodeIfPresent(Double.self, forKey: .scoutFilmBudgetUSD) ?? 0
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
        demoMode = state.demoMode
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
        scoutFilmCreationEnabled = state.scoutFilmCreationEnabled
        scoutFilmBudgetUSD = state.scoutFilmBudgetUSD
        isAdmin = state.isAdmin
        adminAdded = state.adminAdded
        adminEdits = state.adminEdits
        adminDeleted = Set(state.adminDeleted)
        libraryIDs = Set(state.libraryIDs)
        watchlistIDs = Set(state.watchlistIDs)
        submissions = state.submissions
        // Sweep + force a persist so a "stuck in review" row from a previous
        // session is actually written to disk as rejected. Without
        // forcePersist the rejection lives in memory only and the next
        // launch re-loads the original .reviewing status.
        sweepInterruptedReviews(forcePersist: true)
        loading = false
    }

    /// Any submission still flagged `.reviewing` after a process restart is a
    /// review that never finished — the analysis Task is gone with the
    /// process. Mark them rejected with a synthetic, user-friendly note so
    /// the dashboard / detail view render coherently and the user gets a
    /// Try-again affordance instead of a permanent zombie row.
    ///
    /// Internal flag controls whether we force-write to disk after the sweep
    /// (when called from restore the persist is gated by `loading == true`
    /// and the rejection is in-memory only — that was the "still in review
    /// every time I open the app" bug). When called outside restore, the
    /// regular @Published didSet on `submissions` will trigger persist.
    func sweepInterruptedReviews(forcePersist: Bool = false) {
        let cutoff = Date.now.addingTimeInterval(-60)
        var swept = 0
        for i in submissions.indices
        where submissions[i].status == .reviewing && submissions[i].submittedAt < cutoff {
            submissions[i].status = .rejected
            if submissions[i].review == nil {
                submissions[i].review = AIReviewResult(
                    overall: 0,
                    criteria: [],
                    strengths: [],
                    improvements: ["Re-upload your file and submit again — the review didn't complete."],
                    summary: "Review was interrupted before it finished. This usually happens if the app was closed mid-review. Tap Revise & resubmit to try again.",
                    confidence: 0,
                    autonomousRationale: ""
                )
            }
            swept += 1
        }
        if forcePersist && swept > 0 {
            // restore() gates persist() behind loading=true so an in-memory
            // sweep wouldn't survive the next launch. This branch writes
            // through anyway so the rejection sticks.
            let wasLoading = loading
            loading = false
            persist()
            loading = wasLoading
        }
    }

    private func persist() {
        guard !loading else { return }
        let publishedIDs = Set(submissions.compactMap(\.publishedItemID))
        let publishedItems = catalog.filter { publishedIDs.contains($0.id) }
        let state = PersistedState(
            accountName: accountName,
            accountEmail: accountEmail,
            isRegistered: isRegistered,
            demoMode: demoMode,
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
            scoutFilmCreationEnabled: scoutFilmCreationEnabled,
            scoutFilmBudgetUSD: scoutFilmBudgetUSD,
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
        // Cancel everything in flight — scoutDrops are wiped, so any pending
        // scene-render Tasks would land URLs against ids that no longer exist.
        cancelAllSceneRenderTasks()
        let publishedIDs = Set(submissions.compactMap(\.publishedItemID))
        let published = catalog.filter { publishedIDs.contains($0.id) }
        var rebuilt = SampleData.catalog()
        let baseIDs = Set(rebuilt.map(\.id))
        rebuilt.append(contentsOf: published.filter { !baseIDs.contains($0.id) })
        catalog = rebuilt
        // First entry in the freshly-emptied log: an audit breadcrumb so the
        // operator can confirm the reset actually ran (and when).
        scoutLog = [ScoutEntry(date: .now,
            message: "Admin reset the catalogue. Generated content cleared; base + your published titles preserved.",
            kind: .brief, relatedItemID: nil)]
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
        let removedTitle = catalog.first(where: { $0.id == id })?.title ?? "Untitled"
        adminDeleted.insert(id)
        adminAdded.removeAll { $0.id == id }
        adminEdits[id] = nil
        catalog.removeAll { $0.id == id }
        scoutDrops.removeAll { $0.id == id }
        editorDrops.removeAll { $0.id == id }
        libraryIDs.remove(id)
        watchlistIDs.remove(id)
        // Cancel any in-flight scene-render Tasks targeting the deleted film,
        // so URLs don't land against a phantom id.
        for (key, task) in sceneRenderTasks where key.hasPrefix(id.uuidString) {
            task.cancel()
            sceneRenderTasks.removeValue(forKey: key)
        }
        // Reclaim disk: copyUploadedMedia puts the file at
        // Documents/published/<itemID>.<ext>. Without this cleanup the file
        // sat forever after the title was removed.
        removePublishedMediaFile(for: id)
        scoutLog.insert(ScoutEntry(date: .now,
            message: "Admin removed “\(removedTitle)” from the catalogue.",
            kind: .brief, relatedItemID: nil), at: 0)
        trimScoutLog()
        persist()
        Haptics.warning()
    }

    private func purgePublishedMediaDirectory() {
        guard let docs = try? FileManager.default.url(for: .documentDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false) else { return }
        let publishedDir = docs.appendingPathComponent("published", isDirectory: true)
        try? FileManager.default.removeItem(at: publishedDir)
    }

    private func removePublishedMediaFile(for id: UUID) {
        guard let docs = try? FileManager.default.url(for: .documentDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: false) else { return }
        let publishedDir = docs.appendingPathComponent("published", isDirectory: true)
        let prefix = id.uuidString
        if let entries = try? FileManager.default.contentsOfDirectory(at: publishedDir,
                                                                        includingPropertiesForKeys: nil) {
            for url in entries where url.lastPathComponent.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Account lifecycle

    /// Completes registration from the manual publisher form.
    func register(name: String, email: String) {
        loading = true
        accountName = name.trimmed.isEmpty ? "Creator" : name.trimmed
        accountEmail = email.trimmed
        loading = false
        isRegistered = true   // triggers persist
    }

    /// One-tap entry for Apple App Review. Sets the demo flag, fills a
    /// believable name + email, and lands the reviewer signed-in. See
    /// `DEMO_MODE.md` for what behavior the flag changes.
    func registerAsDemoUser() {
        loading = true
        accountName = "Demo Reviewer"
        accountEmail = "review@aimarketplace.demo"
        demoMode = true
        loading = false
        isRegistered = true
    }

    /// Demo-mode Stripe completion. Marks payouts connected with a
    /// believable-shaped account id and skips every Worker call so the
    /// reviewer can verify the post-Stripe state without entering real
    /// bank info or talking to a real Stripe endpoint.
    func completeDemoStripeSetup() {
        guard demoMode else { return }
        connectAccountID = "acct_demo_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16))"
        payoutConnected = true
        lastPayoutError = nil
        notify(title: "Demo Stripe setup complete",
               body: "Payouts marked connected — this is a simulated state for App Review only.",
               kind: .system)
    }

    /// Demo-mode wallet top-up. Skips StoreKit entirely so reviewers can
    /// exercise the buy flow without spending real money. Mirrors the
    /// onCredit path so notifications + persistence stay consistent.
    func addDemoCredit(amount: Double) {
        guard demoMode else { return }
        walletBalance += amount
    }

    /// Signs out but keeps the encrypted account on device for re-entry.
    func signOut() {
        isRegistered = false
    }

    enum DeleteAccountOutcome {
        case deleted
        case blockedByOutstandingBalance
        case failed(String)
    }

    /// Permanently deletes the account and all on-device data (App Store
    /// Guideline 5.1.1(v)). Awaits the Stripe Connect closure first — if
    /// Stripe refuses (outstanding balance), the LOCAL wipe is aborted so the
    /// user keeps access to settle up. Transient network failures still
    /// proceed with the local wipe (5.1.1(v) requires on-device deletion to
    /// be reliable even when offline), but `lastPayoutError` flags the
    /// orphaned Stripe account for the operator.
    @discardableResult
    func deleteAccount() async -> DeleteAccountOutcome {
        if let accountId = connectAccountID, !accountId.isEmpty {
            let result = await requestRemoteAccountClosure(accountId: accountId)
            switch result {
            case .outstandingBalance:
                lastPayoutError = "Your Stripe account still holds a balance. Cash it out first, then come back to delete your account."
                return .blockedByOutstandingBalance
            case .transientFailure(let why):
                lastPayoutError = "Stripe couldn't confirm the close (\(why)). We've deleted everything locally; contact support to make sure the Stripe side is closed too."
            case .success, .notConfigured:
                break
            }
        }

        loading = true
        accountName = ""
        accountEmail = ""
        demoMode = false
        walletBalance = 0
        creatorEarnings = 0
        aiAutopilotEnabled = false
        invitedPartners = []
        referrals = [:]
        pendingPayoutUSD = 0
        payoutConnected = false
        paidOutUSD = 0
        connectAccountID = nil
        reviews = []
        editorDrops = []
        requests = []
        notifications = []
        scoutDrops = []
        scoutLog = []
        lastScoutRun = nil
        scoutFilmCreationEnabled = true
        scoutFilmBudgetUSD = 0
        isAdmin = false
        adminAdded = []
        adminEdits = [:]
        adminDeleted = []
        libraryIDs = []
        watchlistIDs = []
        submissions = []
        // 5.1.1(v): every on-device store the app writes must be wiped.
        // scoutProposals lives in a separate UserDefaults key, so the
        // encrypted-archive delete below misses it — clear it explicitly.
        scoutProposals = []
        UserDefaults.standard.removeObject(forKey: Self.scoutProposalsDefaultsKey)
        // Drop the user's published titles, keeping seed + Editor Originals.
        let seedIDs = Set(SampleData.catalog().map(\.id))
        catalog.removeAll { !$0.isEditorOriginal && !seedIDs.contains($0.id) }
        // Wipe every user-published media file on disk. 5.1.1(v) says all
        // user data goes; this is where the audio/video lives.
        purgePublishedMediaDirectory()
        loading = false
        archive.delete()
        isRegistered = false
        return .deleted
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
    /// True while a cash-out request is in flight. Blocks a second tap from
    /// firing a duplicate cash-out before the first one returns. Not persisted.
    @Published var cashingOut: Bool = false
    /// Stripe-reported: the creator finished the onboarding form (regardless
    /// of whether Stripe has finished verifying them). Together with
    /// payoutConnected, lets the UI distinguish "abandoned mid-flow",
    /// "Stripe still reviewing", and "ready to receive payouts."
    @Published var payoutDetailsSubmitted: Bool = false { didSet { persist() } }

    func connectPayout() {
        // Pre-flight: the Worker requires both name and email. If either is
        // missing (Sign-in-with-Apple sometimes returns no name), surface a
        // clear error instead of failing silently against the API.
        let trimmedName = accountName.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = accountEmail.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedEmail.isEmpty else {
            lastPayoutError = "Add a publisher name and email in Profile before connecting Stripe."
            return
        }
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty else {
            lastPayoutError = isAdmin
                ? "Configure your Worker URL + Secret in Payout Setup first — without them the app can't reach Stripe."
                : "Payouts aren't available in this build yet. Please update the app, or contact support."
            return
        }
        lastPayoutError = nil
        Task { await connectPayoutRemote() }
    }

    /// Resume a Stripe onboarding flow the creator started but didn't finish.
    /// Asks the Worker for a fresh account_links URL on the EXISTING
    /// connectAccountID (account_links URLs expire in minutes), and re-opens
    /// Safari to Stripe's hosted onboarding form. No new Stripe account.
    func resumePayoutOnboarding() {
        guard let accountId = connectAccountID, !accountId.isEmpty,
              !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/payouts/onboarding-link") else {
            lastPayoutError = "Can't resume — try connecting from scratch."
            return
        }
        lastPayoutError = nil
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["account_id": accountId])
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    self.lastPayoutError = self.isAdmin
                        ? "Couldn't reach Stripe onboarding (HTTP \(code))."
                        : "Stripe is temporarily unreachable. Try again in a minute."
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let onboardingUrl = json["onboardingUrl"] as? String,
                   let link = URL(string: onboardingUrl) {
                    await UIApplication.shared.open(link)
                }
            } catch {
                self.lastPayoutError = self.isAdmin
                    ? "Couldn't reach Stripe onboarding: \(error.localizedDescription)"
                    : "Stripe is temporarily unreachable. Check your connection and try again."
            }
        }
    }

    private func connectPayoutRemote() async {
        guard let url = URL(string: "\(payoutBaseURL)/payouts/connect") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Send the creator's region so the Worker creates the Connect account in
        // the right country (the platform is Canadian; creators may be elsewhere).
        let country = Locale.current.region?.identifier ?? "CA"
        let body = ["accountName": accountName, "accountEmail": accountEmail, "country": country]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastPayoutError = isAdmin
                    ? "No response from the payout backend."
                    : "We couldn't reach Stripe right now. Check your connection and try again — your spot is saved."
                return
            }
            guard http.statusCode == 200 else {
                let serverMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                lastPayoutError = isAdmin
                    ? "Stripe onboarding failed (\(http.statusCode))\(serverMsg.map { ": \($0)" } ?? "")."
                    : "Stripe couldn't start onboarding right now. Try again in a minute."
                return
            }
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
            lastPayoutError = isAdmin
                ? "Couldn't reach the payout backend: \(error.localizedDescription)"
                : "We couldn't reach Stripe right now. Check your connection and try again."
        }
    }

    /// Check Connect account status (called after onboarding returns).
    /// Reads three Stripe-reported flags so the UI can tell the difference
    /// between "abandoned mid-flow", "Stripe is still verifying you", and
    /// "you're ready to receive payouts."
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
                let detailsSubmitted = json["detailsSubmitted"] as? Bool ?? false
                payoutDetailsSubmitted = detailsSubmitted
                payoutConnected = chargesEnabled && payoutsEnabled
            }
        } catch {
            // Non-fatal: leave existing state alone, surface only if user is
            // actively viewing payout config (handled in the view).
        }
    }

    /// Pull this creator's money-flow ledger from the Worker (the independent
    /// record of every transfer/payout/NSF). Returns entries newest-first or a
    /// human-readable error. Scoped to the connected account when present.
    func fetchLedger() async -> Result<[LedgerEntry], StringError> {
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty else {
            return .failure(StringError(message: "Connect your payout backend in Payout Setup to see live sales."))
        }
        let scope = connectAccountID ?? "platform"
        guard let url = URL(string: "\(payoutBaseURL)/ledger?account_id=\(scope)&limit=100") else {
            return .failure(StringError(message: "Invalid payout backend URL."))
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(StringError(message: "Couldn't load sales (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."))
            }
            struct LedgerResponse: Codable { var entries: [LedgerEntry] }
            let decoded = try JSONDecoder().decode(LedgerResponse.self, from: data)
            return .success(decoded.entries)
        } catch {
            return .failure(StringError(message: "Couldn't load sales: \(error.localizedDescription)"))
        }
    }

    /// A creator currently owed an unpaid (failed/NSF) transfer. Mirrors the
    /// Worker's UnfundedEntry. Operator pays these manually once the float is up.
    struct UnfundedEntry: Identifiable, Codable, Hashable {
        var id: String
        var accountId: String
        var amountCents: Int
        var currency: String
        var title: String?
        var reason: String
        var ts: String
        var amountUSD: Double { Double(amountCents) / 100 }
    }

    /// Operator-only: fetch the queue of creators owed an unpaid transfer.
    func fetchUnfunded() async -> Result<[UnfundedEntry], StringError> {
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/payouts/unfunded") else {
            return .failure(StringError(message: "Connect the payout backend in Payout Setup first."))
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(StringError(message: "Couldn't load owed creators (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))."))
            }
            struct Resp: Codable { var entries: [UnfundedEntry] }
            return .success(try JSONDecoder().decode(Resp.self, from: data).entries)
        } catch {
            return .failure(StringError(message: "Couldn't load owed creators: \(error.localizedDescription)"))
        }
    }

    /// Operator-only: manually re-pay an owed creator. On success the Worker
    /// clears the queue entry. Returns nil on success, or an error message.
    func manualFund(_ entry: UnfundedEntry) async -> String? {
        guard isAdmin else { return "Admin only." }
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/payouts/manual-fund") else {
            return "Connect the payout backend in Payout Setup first."
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "account_id": entry.accountId,
            "amount_usd": entry.amountUSD,
            "unfunded_id": entry.id,
            "reason": "manual re-pay after NSF",
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }
            if (200..<300).contains(http.statusCode) { return nil }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            let detail = msg.map { ": \($0)" } ?? ""
            return "Payment failed (\(http.statusCode))\(detail). The float may still be short — top up and retry."
        } catch {
            return "Payment failed: \(error.localizedDescription)"
        }
    }

    /// Credits the creator's withdrawable balance (called on each of their sales
    /// and by NRN → USD conversion).
    func addPendingPayout(_ usd: Double) {
        guard usd > 0 else { return }
        pendingPayoutUSD = ((pendingPayoutUSD + usd) * 100).rounded() / 100
        // System-level alert so creators aren't blind to sales when the
        // app is backgrounded — the single biggest reason they weren't
        // coming back was that money arrived silently.
        LocalNotificationService.shared.fire(.sale,
            title: "You made a sale",
            body: String(format: "+$%.2f added to your pending payout balance.", usd))
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
        // `!cashingOut` blocks a double-tap from firing two cash-outs before the
        // first returns (the cash-out endpoint isn't idempotent like transfers).
        guard payoutConnected, pendingPayoutUSD > 0, !cashingOut else { return 0 }
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
        cashingOut = true
        Task { @MainActor in
            let succeeded = await cashOutRemote(accountId: accountId, amount: amount)
            cashingOut = false
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

    /// Best-effort per-sale transfer from the platform balance to the creator's
    /// Stripe Connect account. Funded by the platform top-up float. Stripe
    /// Express auto-pays the connected account's balance to the creator's bank.
    ///
    /// `saleID` is generated per call and used as the idempotency key so a
    /// retried network request cannot double-pay the creator. If the Worker is
    /// not configured or the creator hasn't onboarded, this is a no-op (the
    /// local pendingPayoutUSD credit still records the obligation).
    private func transferEarningRemote(amount: Double, saleID: UUID, titleID: UUID) {
        guard !payoutBaseURL.isEmpty,
              !payoutSharedSecret.isEmpty,
              let accountId = connectAccountID, !accountId.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/payouts/transfer") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "account_id": accountId,
            "amount_usd": amount,
            "title_id": titleID.uuidString,
            "idempotency_key": "sale_\(saleID.uuidString)",
            "memo": "AI Marketplace sale",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        Task { @MainActor in
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { return }
                if !(200..<300).contains(http.statusCode) {
                    lastPayoutError = "A creator transfer failed (HTTP \(http.statusCode)). The amount stays pending and will be retried."
                }
            } catch {
                lastPayoutError = "A creator transfer failed: \(error.localizedDescription). Amount stays pending."
            }
        }
    }

    /// Best-effort: ask the Worker to close the connected Stripe account so
    /// creator data doesn't outlive the in-app deletion (Apple 5.1.1(v)).
    /// Fire-and-forget — the local delete proceeds regardless; Apple's rule is
    /// that the user can initiate deletion in-app, not that propagation is
    /// instant or transactional.
    /// Result of asking the Worker to close a Stripe Connect account.
    enum StripeClosureResult {
        case notConfigured            // no Worker bundled — nothing to call
        case success                  // 200 from Stripe (via Worker)
        case outstandingBalance       // Stripe refused — money is owed
        case transientFailure(String) // network / 5xx / parse — safe to retry
    }

    /// Closes the Stripe Connect account *server-side* before we wipe the
    /// local handle. Now async + result-bearing: callers (specifically
    /// `deleteAccount`) can abort the local wipe if Stripe refuses (e.g.
    /// outstanding balance). The previous fire-and-forget version was an
    /// App Review 5.1.1(v) gap — deletion is supposed to be complete.
    private func requestRemoteAccountClosure(accountId: String) async -> StripeClosureResult {
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/accounts/delete") else { return .notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["account_id": accountId])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .transientFailure("No response from server.")
            }
            if http.statusCode == 200 { return .success }
            // 400 with a "balance" / "outstanding" hint → block local wipe.
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let err = (body["error"] as? String) ?? ""
            if http.statusCode == 400 &&
                (err.localizedCaseInsensitiveContains("balance") ||
                 err.localizedCaseInsensitiveContains("outstanding") ||
                 err.localizedCaseInsensitiveContains("pending")) {
                return .outstandingBalance
            }
            return .transientFailure("Server returned \(http.statusCode).")
        } catch {
            return .transientFailure(error.localizedDescription)
        }
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

    /// Apple 1.2 / UGC: reviews must be authored by buyers of the title, and
    /// the text must be non-empty and within a sane length. Profanity / spam
    /// is handled by ModerationStore's report path; we only enforce structural
    /// validity here.
    static let maxReviewLength = 600

    @discardableResult
    func addReview(itemID: UUID, rating: Int, text: String) -> Bool {
        guard libraryIDs.contains(itemID) else { return false }
        let clean = text.trimmed
        guard !clean.isEmpty else { return false }
        let bounded = String(clean.prefix(Self.maxReviewLength))
        let me = accountName.trimmed.isEmpty ? "You" : accountName.trimmed
        reviews.removeAll { $0.itemID == itemID && $0.author == me }
        reviews.insert(Review(itemID: itemID, author: me,
                              rating: max(1, min(5, rating)), text: bounded, date: .now), at: 0)
        return true
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

    /// Scout's daily cycle. Composes PROPOSALS — never produces unilaterally.
    /// Each proposal carries the recipe, masters, budget (tokens + USD), and
    /// which provider it'd use; the admin reviews and authorizes in-app.
    /// Only authorized proposals enter the Editor-gated production pipeline.
    func runScout() {
        lastScoutRun = .now
        fulfillOpenRequests()
        developScoutContent()
        // Grow any in-progress Scout films by one scene per cycle, in the
        // background. Decoupled from the proposal-authorization path so a
        // single proposal can't accidentally append to a film it didn't
        // start.
        if scoutFilmCreationEnabled {
            Task { [weak self] in await self?.extendInProgressFilms() }
        }

        let demand = demandSignals(limit: 3)
        func fallbackGenre(for type: MediaType) -> String {
            demand.first { $0.type == type }?.genre ?? ContentFoundry.defaultGenre(for: type)
        }
        func randomType(_ salt: String) -> MediaType {
            MediaType.allCases[abs(stableHash("\(scoutDrops.count)\(salt)")) % MediaType.allCases.count]
        }

        var plan: [(MediaType, ContentFoundry.ScoutLayer)] = [
            (.movie, .commercial), (.music, .commercial), (.novel, .commercial),
        ]
        // Admin may have paused film creation (e.g. budget tight, leaning into
        // other formats). Skip the movie slot in that case.
        if !scoutFilmCreationEnabled {
            plan.removeAll { $0.0 == .movie }
            scoutLog.insert(ScoutEntry(date: .now,
                message: "Film creation paused in Admin — Scout drafted novels and music only this cycle.",
                kind: .brief, relatedItemID: nil), at: 0)
        }
        if !userPostedRecently {
            plan.append((randomType("exp"), .experimental))
            plan.append((randomType("niche"), .niche))
        } else {
            logScoutOutreach()
        }

        // Don't pile new proposals on top of an already-large pending queue.
        // Admin needs to clear the deck before Scout adds more.
        let alreadyPending = pendingScoutProposals.count
        guard alreadyPending < 8 else {
            scoutLog.insert(ScoutEntry(date: .now,
                message: "Scout paused: \(alreadyPending) proposals still pending your authorization. Approve or decline in the deck to unblock the next cycle.",
                kind: .brief, relatedItemID: nil), at: 0)
            trimScoutLog()
            return
        }

        var composed: [ScoutProposal] = []
        for (i, (type, layer)) in plan.enumerated() {
            let cycleIndex = scoutDrops.count + i + alreadyPending
            let recipe = scoutFeed?.pickRecipe(for: typeKey(type), cycleIndex: cycleIndex)
            let genre = recipe?.genre ?? fallbackGenre(for: type)
            let item = ContentFoundry.scoutPick(type: type, layer: layer, genre: genre,
                                                developing: false,
                                                seed: scoutDrops.count + i)

            let provider = ScoutProposal.provider(
                for: type,
                externalConfigured: (type == .music && scoutFeed?.providers.musicGenConfigured == true)
                                  || (type == .movie && scoutFeed?.providers.videoGenConfigured == true)
            )
            let proposal = ScoutProposal(
                id: UUID(),
                createdAt: .now,
                type: type,
                layerRaw: layer.rawValue,
                title: item.title,
                creator: item.creator,
                genre: item.genre,
                recipeID: recipe?.id,
                recipeFormula: recipe?.formula ?? "",
                recipeMasters: recipe?.masters ?? [],
                experimental: recipe?.experimental ?? (layer == .experimental),
                estimatedTokens: estimateTokens(for: type, provider: provider),
                estimatedUSD: estimatedUSD(for: type, provider: provider),
                providerNeeded: provider,
                providerAvailable: provider == .foundation || providerAvailable(provider),
                status: .pending
            )
            composed.append(proposal)
        }
        scoutProposals.append(contentsOf: composed)
        scoutLog.insert(ScoutEntry(date: .now,
            message: "Scout drafted \(composed.count) proposals — review the deck (admin) to authorize production. Budget: $\(String(format: "%.2f", composed.reduce(0) { $0 + $1.estimatedUSD })) + ~\(composed.reduce(0) { $0 + $1.estimatedTokens }) Foundation tokens.",
            kind: .brief, relatedItemID: nil), at: 0)
        trimScoutLog()
    }

    private func providerAvailable(_ p: ScoutProposal.Provider) -> Bool {
        switch p {
        case .foundation: return true
        case .musicGen:   return scoutFeed?.providers.musicGenConfigured ?? false
        case .videoGen:   return scoutFeed?.providers.videoGenConfigured ?? false
        }
    }

    /// Foundation Model token estimate: synopsis (~50 words) + long-form
    /// (~500 words for music, ~600 for film, ~500 for novel) × 1.33 tokens/word.
    private func estimateTokens(for type: MediaType, provider: ScoutProposal.Provider) -> Int {
        let synopsisWords = 50
        let longFormWords: Int = {
            switch type {
            case .novel: return 500
            case .music: return 400  // lyrics + liner notes
            case .movie: return 600  // screenplay scene
            }
        }()
        return Int(Double(synopsisWords + longFormWords) * 1.33)
    }

    /// Coarse external-provider spend estimate. Foundation is $0.
    private func estimatedUSD(for type: MediaType, provider: ScoutProposal.Provider) -> Double {
        switch provider {
        case .foundation: return 0.00
        case .musicGen:   return 0.15  // typical per-generation for Suno-class APIs
        case .videoGen:   return 0.60  // per ~5s clip, Runway/Veo ballpark
        }
    }

    /// Counts Foundation Model tokens from the actual generated text. English
    /// approximation: 1.33 tokens per whitespace-separated word. We measure
    /// post-hoc rather than mid-generation so we don't depend on a specific
    /// FoundationModels SDK shape — works on every iOS that runs the model.
    private func countTokens(_ texts: String?...) -> Int {
        var words = 0
        for t in texts {
            guard let s = t else { continue }
            words += s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        }
        return Int(Double(words) * 1.33)
    }

    /// Runs the production pipeline for an authorized proposal. Updates the
    /// proposal with the verdict; publishes if the Editor passes.
    private func produceFromProposal(_ proposal: ScoutProposal,
                                     catalogSnapshot: [MediaItem]) async {
        await produceVettedItem(type: proposal.type,
                                layer: ContentFoundry.ScoutLayer(rawValue: proposal.layerRaw) ?? .commercial,
                                cycleIndex: scoutDrops.count,
                                fallbackGenre: proposal.genre,
                                catalogSnapshot: catalogSnapshot,
                                fromProposal: proposal.id)
    }

    private func typeKey(_ t: MediaType) -> String {
        switch t { case .novel: return "novel"; case .music: return "music"; case .movie: return "movie" }
    }

    /// The Scout-with-Editor loop, per slot. Up to 3 recipe attempts; only a
    /// draft that clears AIReviewResult.threshold (85) is published, and its
    /// commercialScore is set to the Editor's overall — Scout never gets to
    /// self-assert quality.
    ///
    /// Each attempt generates a substantial long-form artifact via OnDeviceAI
    /// (manuscript scene for novels, lyrics + liner notes for music, opening-
    /// scene screenplay for film). The artifact becomes the DraftWork's
    /// manuscriptText, and the Editor's text pipeline vets it. This is what
    /// makes ALL three media types publishable on-device today, without an
    /// external audio/video generator.
    private func produceVettedItem(type: MediaType, layer: ContentFoundry.ScoutLayer,
                                   cycleIndex: Int, fallbackGenre: String,
                                   catalogSnapshot: [MediaItem],
                                   fromProposal: UUID? = nil) async {
        // A proposal authorization always creates a NEW film. Extending
        // existing in-progress films happens separately in
        // `extendInProgressFilms()`, called once per Scout cycle. Mixing the
        // two paths here used to mark an authorized proposal as "produced"
        // against a *different* in-progress film — a real proposal-tracking
        // bug surfaced by the audit.
        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            let recipe = scoutFeed?.pickRecipe(for: typeKey(type),
                                               cycleIndex: cycleIndex + attempt * 13)
            let genre = recipe?.genre ?? fallbackGenre

            // 1. Compose a skeleton (title, model, slug, length, price band).
            var item = ContentFoundry.scoutPick(type: type, layer: layer, genre: genre,
                                                developing: false,
                                                seed: scoutDrops.count + attempt)
            // Films start as Scene 1 of a multi-segment work targeting 30+ min.
            if type == .movie {
                item.targetMinutes = 30
                item.length = 0     // will accrue as scenes are added
            }

            // 2. Generate the long-form artifact the Editor will analyse.
            let formula = recipe?.formula ?? ""
            let masters = recipe?.masters ?? []
            let longForm = await OnDeviceAI.draftLongForm(type: type, title: item.title,
                                                          genre: item.genre,
                                                          formula: formula, masters: masters)

            // 3. Always also generate a short marketing synopsis for the card.
            if let synopsis = await OnDeviceAI.draftSynopsis(type: type, title: item.title,
                                                             genre: item.genre, existing: formula),
               !synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.synopsis = synopsis
            }

            // 4. Build the draft. House-content flag tells the Editor to accept
            //    text vetting for music/film when no audio/video bytes exist.
            let draft = buildScoutDraft(from: item, recipe: recipe, longForm: longForm)
            let verdict = await ReviewPipeline.review(draft, against: catalogSnapshot)

            if verdict.passed {
                item.commercialScore = verdict.overall
                // For films, register Scene 1 (a 2–5 min opening). Subsequent
                // cycles will append more scenes via appendSceneToInProgressFilm.
                if type == .movie, let text = longForm, !text.isEmpty {
                    let mins = sceneDurationMinutes(for: text, seed: scoutDrops.count)
                    item.screenplayScenes = [text]
                    item.sceneDurations = [mins]
                    item.sceneVideoURLs = [""]
                    item.length = mins
                    if scoutFilmBudgetUSD > 0 && scoutFilmCreationEnabled {
                        scheduleSceneRender(itemID: item.id, sceneIndex: 0,
                                            prompt: text, durationSeconds: mins * 60)
                    }
                }
                catalog.insert(item, at: 0)
                scoutDrops.append(item)
                if let model = item.aiTools.first {
                    let cost = AICoin.energyCost(type)
                    energyLedger?.draw(cost, by: model, memo: "Scout released “\(item.title)”")
                }
                let logMessage: String = {
                    if type == .movie {
                        return "Scout started “\(item.title)” — Scene 1 published (\(item.length) min). \(item.targetMinutes - item.length) min still to come."
                    }
                    return editorPassedMessage(item: item, layer: layer, type: type,
                                                recipe: recipe, verdict: verdict)
                }()
                scoutLog.insert(ScoutEntry(date: .now,
                    message: logMessage,
                    kind: .produced, relatedItemID: item.id), at: 0)
                if let proposalID = fromProposal,
                   let pidx = scoutProposals.firstIndex(where: { $0.id == proposalID }) {
                    scoutProposals[pidx].status = .produced
                    scoutProposals[pidx].publishedItemID = item.id
                    scoutProposals[pidx].editorScore = verdict.overall
                    scoutProposals[pidx].actualTokens = countTokens(longForm, item.synopsis)
                    scoutProposals[pidx].resolvedAt = .now
                }
                return
            }

            // Editor rejected: surface the score and the headline reason, then
            // re-roll with a different recipe.
            let reason = verdict.improvements.first ?? verdict.summary
            scoutLog.insert(ScoutEntry(date: .now,
                message: "Editor rejected Scout's \(layer.rawValue) \(type.title.lowercased()) draft “\(item.title)” at \(verdict.overall)/100 (bar \(AIReviewResult.threshold)). \(reason). Re-rolling with a different recipe.",
                kind: .brief, relatedItemID: nil), at: 0)
        }

        // No attempt cleared the bar. Mark the proposal honestly.
        scoutLog.insert(ScoutEntry(date: .now,
            message: "Scout couldn't clear the \(AIReviewResult.threshold)/100 editor bar for a \(type.title.lowercased()) after \(maxAttempts) tries — slot stays open until next cycle.",
            kind: .brief, relatedItemID: nil), at: 0)
        if let proposalID = fromProposal,
           let pidx = scoutProposals.firstIndex(where: { $0.id == proposalID }) {
            scoutProposals[pidx].status = .editorRejected
            scoutProposals[pidx].statusNote = "Editor couldn't clear the bar after \(maxAttempts) tries."
            scoutProposals[pidx].resolvedAt = .now
        }
    }

    /// Extends an in-progress Scout film by drafting and appending one more
    /// 2–5 min scene. The Editor still vets the new scene; only passing scenes
    /// get added. When `length >= targetMinutes`, the film is "complete."
    /// Once per Scout cycle, walk every in-progress film and append one more
    /// scene. Stops growing a film when it hits its `targetMinutes`. Runs in
    /// the background; the proposal-driven new-film path is independent.
    private func extendInProgressFilms() async {
        let snapshot = catalog
        let inProgress = scoutDrops.enumerated().filter { $0.element.isFilmInProgress }
        for (i, _) in inProgress {
            // Re-resolve the index by id each iteration — earlier appends may
            // have shifted positions in scoutDrops.
            let id = inProgress.first(where: { $0.offset == i })?.element.id
            guard let target = id,
                  let liveIdx = scoutDrops.firstIndex(where: { $0.id == target }) else { continue }
            if !scoutDrops[liveIdx].isFilmInProgress { continue }
            await appendSceneToInProgressFilm(at: liveIdx,
                                              catalogSnapshot: snapshot,
                                              fromProposal: nil)
        }
    }

    private func appendSceneToInProgressFilm(at index: Int,
                                             catalogSnapshot: [MediaItem],
                                             fromProposal: UUID?) async {
        var item = scoutDrops[index]
        let sceneNumber = item.screenplayScenes.count + 1
        let recipe = scoutFeed?.pickRecipe(for: typeKey(.movie),
                                           cycleIndex: scoutDrops.count + sceneNumber)
        let formula = recipe?.formula ?? ""
        let masters = recipe?.masters ?? []
        let longForm = await OnDeviceAI.draftLongForm(type: .movie,
                                                      title: "\(item.title) — Scene \(sceneNumber)",
                                                      genre: item.genre,
                                                      formula: formula, masters: masters)
        guard let sceneText = longForm,
              !sceneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            scoutLog.insert(ScoutEntry(date: .now,
                message: "Scout couldn't draft Scene \(sceneNumber) of “\(item.title)” — Foundation Models returned nothing. Retry next cycle.",
                kind: .brief, relatedItemID: item.id), at: 0)
            return
        }

        // Vet the new scene by itself. Build a one-shot DraftWork around it.
        let draft = buildScoutDraft(from: item, recipe: recipe, longForm: sceneText)
        let verdict = await ReviewPipeline.review(draft, against: catalogSnapshot)
        guard verdict.passed else {
            scoutLog.insert(ScoutEntry(date: .now,
                message: "Editor rejected Scene \(sceneNumber) of “\(item.title)” at \(verdict.overall)/100. Scene dropped; will re-attempt next cycle.",
                kind: .brief, relatedItemID: item.id), at: 0)
            return
        }

        let minutes = sceneDurationMinutes(for: sceneText, seed: scoutDrops.count + sceneNumber)
        item.screenplayScenes.append(sceneText)
        item.sceneDurations.append(minutes)
        item.sceneVideoURLs.append("")   // placeholder — filled if video-gen lands
        item.length = item.totalSceneMinutes
        scoutDrops[index] = item
        if let catIdx = catalog.firstIndex(where: { $0.id == item.id }) {
            catalog[catIdx] = item
        }

        // If the admin has wired a budget AND a provider is available, render
        // the scene to real video bytes. Fire-and-forget: the screenplay scene
        // is already published; the video URL lands later once the provider
        // returns. Player falls back to screenplay text until the URL arrives.
        if scoutFilmBudgetUSD > 0 && scoutFilmCreationEnabled {
            let sceneIdx = item.screenplayScenes.count - 1
            scheduleSceneRender(itemID: item.id, sceneIndex: sceneIdx,
                                prompt: sceneText, durationSeconds: minutes * 60)
        }

        let remaining = max(0, item.targetMinutes - item.length)
        let msg: String
        if item.isFilmComplete {
            msg = "Scout completed “\(item.title)” — Scene \(sceneNumber) added. Full film now \(item.length) min across \(item.screenplayScenes.count) scenes."
        } else {
            msg = "Scout added Scene \(sceneNumber) (+\(minutes) min) to “\(item.title)”. Runtime now \(item.length) of \(item.targetMinutes) min target — \(remaining) min still to come."
        }
        scoutLog.insert(ScoutEntry(date: .now, message: msg, kind: .produced, relatedItemID: item.id), at: 0)

        if let proposalID = fromProposal,
           let pidx = scoutProposals.firstIndex(where: { $0.id == proposalID }) {
            scoutProposals[pidx].status = .produced
            scoutProposals[pidx].publishedItemID = item.id
            scoutProposals[pidx].editorScore = verdict.overall
            scoutProposals[pidx].actualTokens = countTokens(sceneText, item.synopsis)
            scoutProposals[pidx].resolvedAt = .now
        }
    }

    /// 2–5 minute deterministic duration per scene. Longer scenes for denser
    /// prose so the runtime feels honest about what was actually drafted.
    private func sceneDurationMinutes(for text: String, seed: Int) -> Int {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        // Heuristic: ~150 spoken words per minute of screen time.
        let approx = max(2, min(5, Int((Double(words) / 150.0).rounded())))
        // Add a small jitter so identical-length scenes don't all clock the same.
        return max(2, min(5, approx + (abs(stableHash("\(seed)")) % 2)))
    }

    /// Calls the Worker's /scout/generate-media to turn a screenplay scene
    /// into a real video clip via the configured provider. Stores the
    /// returned URL on the item's `sceneVideoURLs[sceneIndex]`. Best-effort:
    /// on failure the screenplay scene remains the deliverable.
    /// Spawns a background Task that calls the Worker to render a scene video,
    /// registering it in `sceneRenderTasks` so it can be cancelled when admin
    /// disables Scout film creation. Task auto-deregisters on completion.
    private func scheduleSceneRender(itemID: UUID, sceneIndex: Int,
                                     prompt: String, durationSeconds: Int) {
        let key = sceneRenderKey(itemID, sceneIndex)
        // If we somehow scheduled twice for the same scene, cancel the old.
        sceneRenderTasks[key]?.cancel()
        let task = Task { [weak self] in
            await self?.renderSceneVideo(itemID: itemID, sceneIndex: sceneIndex,
                                         prompt: prompt, durationSeconds: durationSeconds)
            await MainActor.run { self?.sceneRenderTasks.removeValue(forKey: key) }
        }
        sceneRenderTasks[key] = task
    }

    private func renderSceneVideo(itemID: UUID, sceneIndex: Int,
                                  prompt: String, durationSeconds: Int) async {
        guard !Task.isCancelled else { return }
        guard !payoutBaseURL.isEmpty, !payoutSharedSecret.isEmpty,
              let url = URL(string: "\(payoutBaseURL)/scout/generate-media") else {
            return
        }
        // Pick the cheapest provider that fits per-scene cost in the remaining
        // budget. Nil → Worker auto-picks the first available provider.
        let preferred = VideoProvider.catalog
            .filter { $0.costPerSceneUSD <= max(scoutFilmBudgetUSD, 0) }
            .min(by: { $0.costPerSceneUSD < $1.costPerSceneUSD })

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(payoutSharedSecret)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "type": "movie",
            "prompt": prompt,
            "durationSeconds": min(60, max(2, durationSeconds)),
        ]
        if let p = preferred?.id { payload["provider"] = p }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        req.timeoutInterval = 180   // providers can take ~90s

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            // If admin disabled film creation while we were waiting, drop the
            // result on the floor — don't mutate the item.
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                scoutLog.insert(ScoutEntry(date: .now,
                    message: "Scene video skipped — provider call failed. Screenplay version is still live.",
                    kind: .brief, relatedItemID: itemID), at: 0)
                return
            }
            if let videoURL = body["url"] as? String, !videoURL.isEmpty {
                guard let catIdx = catalog.firstIndex(where: { $0.id == itemID }),
                      let dropIdx = scoutDrops.firstIndex(where: { $0.id == itemID }),
                      sceneIndex < scoutDrops[dropIdx].sceneVideoURLs.count else { return }
                scoutDrops[dropIdx].sceneVideoURLs[sceneIndex] = videoURL
                catalog[catIdx] = scoutDrops[dropIdx]
                let provider = (body["provider"] as? String) ?? "video provider"
                let cost = (body["costUSD"] as? Double) ?? 0
                scoutLog.insert(ScoutEntry(date: .now,
                    message: String(format: "Scene %d video rendered via %@ ($%.2f). Buyers now see real footage.", sceneIndex + 1, provider, cost),
                    kind: .produced, relatedItemID: itemID), at: 0)
            } else if let note = body["note"] as? String {
                scoutLog.insert(ScoutEntry(date: .now,
                    message: "Scene video skipped — \(note)",
                    kind: .brief, relatedItemID: itemID), at: 0)
            }
        } catch {
            // Best-effort. Screenplay version still live; quiet failure.
        }
    }

    /// Builds a DraftWork from a Scout-composed item. House-content flag is
    /// set so the Editor allows text-artifact vetting for music/film. The
    /// long-form prose (manuscript / lyrics / screenplay) becomes the
    /// manuscriptText the Editor's NaturalLanguage pipeline analyses.
    private func buildScoutDraft(from item: MediaItem, recipe: ScoutFeed.Recipe?,
                                 longForm: String?) -> DraftWork {
        var d = DraftWork()
        d.type = item.type
        d.title = item.title
        d.creator = item.creator
        d.genre = item.genre
        d.synopsis = item.synopsis
        d.aiTools = item.aiTools
        d.fileName = "scout-\(item.id.uuidString.prefix(8)).\(longFormExt(for: item.type))"
        d.fileSizeMB = 0.5
        d.length = item.length
        d.price = item.price
        // The artifact the Editor will actually inspect:
        d.manuscriptText = (longForm?.isEmpty == false) ? longForm : item.synopsis
        d.isHouseContent = true
        d.attestOwnsWork = true
        d.attestOwnsPrompts = true
        d.attestNoInfringement = true
        d.attestSignature = "AI Marketplace Scout"
        _ = recipe
        return d
    }

    private func longFormExt(for type: MediaType) -> String {
        switch type {
        case .novel: return "manuscript.txt"
        case .music: return "lyrics.txt"
        case .movie: return "screenplay.txt"
        }
    }

    /// Pass-side scout log entry. Surfaces the Editor's score so creators
    /// see exactly what quality threshold the storefront publishes at.
    private func editorPassedMessage(item: MediaItem, layer: ContentFoundry.ScoutLayer,
                                     type: MediaType, recipe: ScoutFeed.Recipe?,
                                     verdict: AIReviewResult) -> String {
        let base = "Editor passed Scout's \(layer.rawValue) \(type.title.lowercased()) at \(verdict.overall)/100: “\(item.title)” by \(item.creator) — live in the catalogue."
        guard let recipe else { return base }
        let mastersNote = recipe.masters.isEmpty ? "" :
            " Drawing on \(recipe.masters.prefix(2).joined(separator: " and "))."
        let formulaNote = " Formula: \(recipe.formula)."
        let experimentalNote = recipe.experimental ?
            " Experimental — breaking the formula on purpose." : ""
        return base + mastersNote + formulaNote + experimentalNote
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

        // Debit the wallet FIRST so a crash mid-deliver can't hand the buyer a
        // catalog entry they never paid for. The persist() that follows each
        // @Published mutation is synchronous; if the process dies after the
        // debit but before the insert, the user paid and we owe them the item,
        // not the other way around.
        walletBalance = max(0, walletBalance - request.budgetUSD)

        var item = ContentFoundry.commission(model: model, type: request.type,
                                              genre: request.genre.isEmpty ? "Original" : request.genre,
                                              seed: requests.count, score: score)
        item.price = request.budgetUSD
        item.purchases = 1                       // the requester's purchase
        catalog.insert(item, at: 0)
        libraryIDs.insert(item.id)               // they commissioned it → they own it
        watchlistIDs.remove(item.id)             // they own it now — clear watchlist

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
        // Mirror to iOS local notifications so a backgrounded user sees the
        // alert at the system level. Permission is requested at app launch;
        // if denied this becomes a no-op.
        let category: LocalNotificationService.Category = {
            switch kind {
            case .delivery: return .scoutLanded
            case .request:  return .reviewDone
            case .system:   return .payout
            }
        }()
        LocalNotificationService.shared.fire(category, title: title, body: body)
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
        watchlistIDs.remove(item.id)   // owning supersedes watching
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
            addPendingPayout(earning)   // local credit (always)
            // Move the money for real: per-sale Stripe transfer to the
            // creator's Connect account. Per-sale UUID so a retry can't
            // double-pay; failure is surfaced via lastPayoutError but does
            // not roll the local credit back (the obligation stays pending).
            transferEarningRemote(amount: earning, saleID: UUID(), titleID: item.id)
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
    /// 60-second cap on the analysis phase. AVAsset.load on a security-scoped
    /// URL can hang indefinitely if the access has lapsed; without this guard
    /// submissions sit at "In Review" forever. Generous enough to decode a
    /// short film and fingerprint a cover.
    private static let analysisTimeoutNS: UInt64 = 60_000_000_000

    @discardableResult
    func runReviewAsync(for submissionID: UUID) async -> AIReviewResult? {
        guard let idx = submissions.firstIndex(where: { $0.id == submissionID }) else {
            print("[AIEditor] submission \(submissionID) not found — review skipped")
            return nil
        }
        let draft = submissions[idx].draft
        let catalogSnapshot = catalog
        print("[AIEditor] reviewing \(draft.title) (\(draft.type.rawValue))…")

        // Race the analysis against a timeout. Either we get the analysis
        // (possibly nil if there were no readable bytes — still fine, the
        // Editor handles that), or we time out and synthesise a "couldn't
        // read it in time" verdict so the UI is never stuck.
        enum Outcome { case ok(ReviewAnalysis?), timedOut }
        let outcome: Outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask { .ok(await ReviewPipeline.buildAnalysis(for: draft)) }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.analysisTimeoutNS)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        switch outcome {
        case .ok(let analysis):
            let result = AIEditor.review(draft, against: catalogSnapshot, analysis: analysis)
            print("[AIEditor] verdict for \(draft.title): \(result.overall)/100, passed=\(result.passed)")
            if let updated = submissions.firstIndex(where: { $0.id == submissionID }) {
                submissions[updated].review = result
                submissions[updated].status = result.passed ? .accepted : .rejected
            }
            return result

        case .timedOut:
            print("[AIEditor] verdict for \(draft.title): TIMED OUT after 60s")
            if let updated = submissions.firstIndex(where: { $0.id == submissionID }) {
                // Don't leave it stuck at "In Review" — mark rejected so the
                // creator can revise. The .verdict screen also gets a nil
                // result and renders the recoverable error card.
                submissions[updated].status = .rejected
            }
            return nil
        }
    }

    /// Permanently removes a submission from the bookshelf. Allowed only for
    /// drafts and rejected/needs-work entries — a live (.accepted with
    /// publishedItemID) submission has to go through adminDelete, which also
    /// pulls the title from the catalogue + every buyer's library.
    func removeSubmission(_ id: UUID) {
        guard let idx = submissions.firstIndex(where: { $0.id == id }) else { return }
        let s = submissions[idx]
        guard s.publishedItemID == nil else { return }   // protect live titles
        submissions.remove(at: idx)
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
        let newID = UUID()
        // Persist the buyer-deliverable. Without this the security-scoped URL
        // dies with the picker and `ContentResolver` returns nil at play time —
        // buyers would purchase the title and see SimulatedTransport / a blank
        // reader. We carry the manuscript text directly on the MediaItem for
        // novels, and copy audio/video bytes into Documents/published/ keyed by
        // the new item id so playback resolves to a real local URL.
        let localMediaFileName: String? = (d.type == .novel) ? nil : copyUploadedMedia(from: d.contentURL, itemID: newID)
        let manuscript: String? = (d.type == .novel) ? d.manuscriptText : nil

        let item = MediaItem(
            id: newID,
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
            coverImageData: d.coverImageData,
            isEditorOriginal: false,
            localMediaFileName: localMediaFileName,
            manuscriptText: manuscript
        )
        catalog.insert(item, at: 0)
        submissions[idx].publishedItemID = item.id
        persist()
        Haptics.success()
    }

    /// Copies the user's uploaded media file from its security-scoped URL into
    /// `Documents/published/<itemID>.<ext>` so it survives the picker's scope
    /// and is playable for buyers later. Returns the basename (e.g.
    /// `ABC123.mp3`) for storage on `MediaItem.localMediaFileName`, or nil if
    /// the source URL was missing or the copy failed.
    private func copyUploadedMedia(from source: URL?, itemID: UUID) -> String? {
        guard let source = source else { return nil }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let docs = try? FileManager.default.url(for: .documentDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: true) else { return nil }
        let publishedDir = docs.appendingPathComponent("published", isDirectory: true)
        try? FileManager.default.createDirectory(at: publishedDir,
                                                  withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        let basename = "\(itemID.uuidString).\(ext)"
        let dest = publishedDir.appendingPathComponent(basename)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return basename
        } catch {
            return nil
        }
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
