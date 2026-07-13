import SwiftUI
import Combine

/// The single source of truth for Auction Baby. Owns the logged-in user, the
/// floor, bids, matches and the lightweight simulation that makes both sides of
/// the auction explorable on one device.
///
/// Everything is play-money and local: no network, no real payments, no real
/// people. The simulation stands in for the "other side" so a solo demo still
/// feels like a live floor.
@MainActor
final class AuctionStore: ObservableObject {

    // MARK: Published state
    @Published var role: Role?
    @Published var me: Profile = AuctionStore.blankProfile(.man)
    @Published var wallet: Int = 750           // Gavels (in-app currency, real money via IAP)
    @Published var earnings: Int = 0            // woman side: bids actually paid out (real-world $)
    @Published var boostUntil: Date?           // active Spotlight Boost expiry, if any
    @Published var dailyStreak: Int = 0        // consecutive days claimed
    @Published var lastDailyClaim: Date?
    @Published var lastWeeklyBoostClaim: Date? // Pass perk: one free Boost / week

    /// Per-user UUID attached to every IAP purchase so Apple server notifications
    /// can route refunds to the correct wallet. Generated once, persisted forever.
    @Published private(set) var appAccountToken: UUID = UUID()

    /// Demo Mode for Apple App Review. Activated by registering with the name
    /// "demo" (case-insensitive) — see DEMO_MODE.md. Free demo top-ups and a
    /// free demo Pass appear in the store surfaces; everything else (bidding,
    /// matches, copycat reveals, reviews) is identical to production. Persists
    /// across launches; cleared by Reset account.
    @Published private(set) var demoMode = false

    @Published var floor: [Profile] = []        // women a bidder browses
    @Published var bidders: [Profile] = []      // the pool of men (suitors) — seeds the inbox
    @Published var incomingBids: [Bid] = []     // woman's inbox
    @Published var outgoingBids: [Bid] = []     // man's placed bids
    @Published var matches: [Match] = []

    @Published var toast: String?
    @Published var filters = FilterPreferences()
    @Published var blockedIDs: Set<UUID> = []
    @Published var activity: [ActivityEvent] = []
    var hasActivity: Bool { !activity.isEmpty }

    /// Append an Activity-feed entry (capped, newest first).
    private func log(_ kind: ActivityKind, _ text: String) {
        activity.insert(ActivityEvent(kind: kind, text: text), at: 0)
        if activity.count > 60 { activity.removeLast(activity.count - 60) }
    }
    /// Drives the full-screen "SOLD!" match celebration. Set when a bid is
    /// accepted; cleared when the overlay is dismissed.
    @Published var celebration: MatchCelebration?
    /// Which match currently shows the "…typing" bubble, if any.
    @Published var typingMatchID: UUID?

    /// Set by the app root when the user has Reserve+ or higher.
    var autoRebidEnabled = false
    /// Set by the app root when the user has Black Card.
    var priorityPlacementEnabled = false

    var isRegistered: Bool { role != nil }

    /// Free bidders may keep this many *live* (pending) bids at once. A Pass
    /// lifts the cap — the "unlimited bids" perk.
    static let freeActiveBidLimit = 3
    /// Gavel cost of gilding a bid (the premium "Rose" move).
    static let gildedBidCost = 250
    var activePendingBidCount: Int { outgoingBids.filter { $0.status == .pending }.count }

    // MARK: Woman-side insights ("what you're worth")
    private var livePending: [Bid] { incomingBids.filter { $0.status == .pending } }
    var liveBidCount: Int { livePending.count }
    var highestLiveBid: Int { livePending.map(\.amount).max() ?? 0 }
    var totalOnTable: Int { livePending.map(\.amount).reduce(0, +) }
    var acceptedCount: Int { incomingBids.filter { $0.status == .accepted }.count }

    /// The floor after blocks + filters are applied — what the bidder actually sees.
    var filteredFloor: [Profile] {
        floor.filter { !blockedIDs.contains($0.id) && filters.matches($0) }
    }

    /// Curated "Headliner of the Day" — a real (non-copycat) lot, rotating daily
    /// and favouring verified, high-Showcase profiles.
    var headliner: Profile? {
        let pool = filteredFloor.filter { !$0.isCopycat }
            .sorted { ($0.verified ? 1 : 0, $0.showcaseScore) > ($1.verified ? 1 : 0, $1.showcaseScore) }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return pool[day % pool.count]
    }

    /// Block and report a profile: removes them from the floor, the bid inbox,
    /// outgoing bids and matches. Local + irreversible in this demo.
    func blockAndReport(_ profile: Profile, reason: String) {
        blockedIDs.insert(profile.id)
        floor.removeAll { $0.id == profile.id }
        incomingBids.removeAll { $0.man.id == profile.id }
        outgoingBids.removeAll { $0.woman.id == profile.id }
        matches.removeAll { $0.bid.man.id == profile.id || $0.bid.woman.id == profile.id }
        Haptics.warning()
        toastFlash("Reported \(profile.name) (\(reason)) and removed them.")
        save()
    }

    // MARK: - Admin (roster management)

    /// Whether the admin console *row* is visible. Founder name only — and
    /// visibility is all this grants; entry requires the credential gate
    /// (`AdminGateView` → `Admin.validate`).
    var isAdmin: Bool { me.name == "Mike Valasek" }

    /// The lots (women) the admin console manages.
    var adminRoster: [Profile] { floor }

    /// The bidders (men) the admin console manages — the pool that seeds the
    /// inbox and summons.
    var adminBidders: [Profile] { bidders }

    /// Add a new lot to the floor from the admin console. Newest first so it's
    /// visible immediately.
    func adminAddUser(name: String, age: Int, location: String, bio: String,
                      startingBid: Int?, verified: Bool, isCopycat: Bool,
                      copycatStyle: CopycatStyle) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var profile = Profile(name: trimmed, age: max(18, age), role: .woman,
                              location: location, bio: bio,
                              hue: Double.random(in: 0...1))
        profile.startingBid = startingBid
        profile.verified = verified && !isCopycat   // copycats can never verify
        profile.isCopycat = isCopycat
        profile.copycatStyle = copycatStyle
        floor.insert(profile, at: 0)
        Haptics.success()
        toastFlash("Added \(trimmed) to the floor.")
        log(.admin, "Admin added \(trimmed) to the floor.")
        save()
    }

    /// Add a new bidder (man) to the pool from the admin console.
    func adminAddBidder(name: String, age: Int, location: String, bio: String,
                        archetype: Archetype, verified: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var profile = Profile(name: trimmed, age: max(18, age), role: .man,
                              location: location, bio: bio,
                              hue: Double.random(in: 0...1))
        profile.verified = verified
        profile.archetype = archetype
        // A verified Trillionaire added by hand is treated as confirmed.
        profile.trillionaireVerified = verified && archetype == .trillionaire
        bidders.insert(profile, at: 0)
        Haptics.success()
        toastFlash("Added bidder \(trimmed).")
        log(.admin, "Admin added bidder \(trimmed).")
        save()
    }

    /// Remove a profile (lot or bidder) and scrub every bid, match and block
    /// that referenced them, so nothing dangles after deletion.
    func adminDeleteUser(_ id: UUID) {
        let victim = floor.first(where: { $0.id == id })
            ?? bidders.first(where: { $0.id == id })
        guard let victim else { return }
        floor.removeAll { $0.id == id }
        bidders.removeAll { $0.id == id }
        incomingBids.removeAll { $0.man.id == id || $0.woman.id == id }
        outgoingBids.removeAll { $0.woman.id == id || $0.man.id == id }
        matches.removeAll { $0.bid.man.id == id || $0.bid.woman.id == id }
        blockedIDs.remove(id)
        Haptics.warning()
        toastFlash("Removed \(victim.name).")
        log(.admin, "Admin removed \(victim.name).")
        save()
    }

    /// Save an edited profile back into whichever roster owns it (floor,
    /// bidders, or the logged-in user). Copycats can never carry a blue check.
    func adminUpdate(_ profile: Profile) {
        var edited = profile
        if edited.isCopycat { edited.verified = false }
        if let i = floor.firstIndex(where: { $0.id == edited.id }) { floor[i] = edited }
        else if let i = bidders.firstIndex(where: { $0.id == edited.id }) { bidders[i] = edited }
        if me.id == edited.id { me = edited }
        Haptics.success()
        toastFlash("Updated \(edited.name).")
        log(.admin, "Admin edited \(edited.name).")
        save()
    }

    private let store = UserDefaults.standard
    private static let key = "auctionbaby.state.v5"

    // MARK: - Lifecycle

    init() { load() }

    static func blankProfile(_ role: Role) -> Profile {
        Profile(name: "", age: 25, role: role, location: "", bio: "", hue: 0.6)
    }

    // MARK: - Onboarding

    func register(role: Role, name: String, age: Int, location: String, bio: String,
                  hue: Double, startingBid: Int?, prompts: [Prompt], interests: [String],
                  photoData: Data? = nil, photoGallery: [Data] = []) {
        // "demo" as the name is the App Review credential (see DEMO_MODE.md):
        // it enables Demo Mode and swaps in the demo identity, so a reviewer
        // needs no password, email, or real payment method.
        let isDemo = name.trimmingCharacters(in: .whitespaces).lowercased() == "demo"
        demoMode = isDemo
        let displayName = isDemo ? "Demo Reviewer" : (name.isEmpty ? "You" : name)
        var profile = Profile(name: displayName, age: age, role: role,
                              location: isDemo && location.isEmpty ? "Cupertino" : location,
                              bio: isDemo && bio.isEmpty ? "Here to see everything." : bio,
                              hue: hue, prompts: prompts, interests: interests)
        profile.photoData = photoData
        profile.photoGallery = photoGallery
        if role == .woman { profile.startingBid = startingBid.map { max(0, min($0, Self.maxStartingBid)) } }
        self.me = profile
        self.role = role
        self.floor = SampleData.floor()
        self.bidders = SampleData.suitors()
        if isDemo { wallet = 25_000 }   // enough to explore every archetype tier

        if role == .woman {
            // Seed a couple of incoming bids so the inbox isn't empty.
            seedIncomingBids()
        }
        Haptics.success()
        toastFlash(isDemo ? "Demo Mode active — everything is free in the store."
                          : (role == .woman ? "Your lot is live on the floor."
                                            : "You're on the floor. Start bidding."))
        save()
    }

    /// Wipe everything and return to onboarding (Settings → Reset).
    func resetAccount() {
        role = nil
        me = AuctionStore.blankProfile(.man)
        wallet = 750
        earnings = 0
        floor = []
        bidders = []
        incomingBids = []
        outgoingBids = []
        matches = []
        boostUntil = nil
        filters = FilterPreferences()
        blockedIDs = []
        activity = []
        dailyStreak = 0
        lastDailyClaim = nil
        lastWeeklyBoostClaim = nil
        demoMode = false
        store.removeObject(forKey: Self.key)
        encryptedArchive.delete()
    }

    // MARK: - Bidder (man) actions

    /// Place a bid on a woman. Bids are offers — nothing is charged until a date
    /// actually happens — but bidding on an AI copycat is logged against the
    /// bidder's reputation immediately.
    func placeBid(on woman: Profile, amount: Int, note: String, gilded: Bool = false,
                  promptRef: String? = nil) {
        guard role == .man, amount > 0 else { return }
        // Gilding spends Gavels up front; fall back to a normal bid if short.
        // Real currency never flows toward an AI lure — a gild attempt on a
        // copycat is silently uncharged (the reveal lands a second later).
        var gild = gilded
        if gild && woman.isCopycat {
            gild = false
        } else if gild {
            if wallet >= Self.gildedBidCost { wallet -= Self.gildedBidCost }
            else { gild = false; toastFlash("Not enough Gavels to gild — sent a standard bid.") }
        }
        var bid = Bid(man: me, woman: woman, amount: amount, note: note)
        bid.gilded = gild
        bid.promptRef = promptRef
        outgoingBids.insert(bid, at: 0)

        if woman.isCopycat {
            let before = me.auctionCredit
            me.copycatBids += 1
            Haptics.warning()
            celebrate(with: woman, amount: amount, copycat: true, masterpiece: woman.masterpiece)
            if woman.masterpiece {
                log(.bidDeclined, "You bid \(Money.compact(amount)) on \(woman.name) — the Masterpiece was never real. Your credit took the hit.")
            } else {
                log(.bidDeclined, "You bid on \(woman.name) — she was AI. Your Auction Credit took the hit.")
            }
            creditPing(before: before)
        } else {
            Haptics.commit()
            toastFlash(gild ? "✦ Gilded bid sent to \(woman.name) — top of her inbox."
                            : "Bid placed: \(Money.compact(amount)) on \(woman.name).")
        }
        save()
        scheduleWomanDecision(bidID: bid.id)
    }

    /// Raise a live bid — the one-tap answer to "you've been outbid". The raised
    /// amount gets a fresh decision from the (simulated) woman.
    func raiseBid(_ bidID: UUID, to newAmount: Int) {
        guard let idx = outgoingBids.firstIndex(where: { $0.id == bidID }),
              outgoingBids[idx].status == .pending,
              newAmount > outgoingBids[idx].amount else { return }
        outgoingBids[idx].amount = newAmount
        Haptics.commit()
        toastFlash("Raised to \(Money.compact(newAmount)) on \(outgoingBids[idx].woman.name).")
        log(.rebid, "You raised your bid on \(outgoingBids[idx].woman.name) to \(Money.compact(newAmount)).")
        save()
        scheduleWomanDecision(bidID: bidID)
    }

    /// Buy (or upgrade to) a status archetype. The price is the point — it's how
    /// a man proves he has money.
    func buyArchetype(_ archetype: Archetype) {
        guard role == .man else { return }
        guard archetype != me.archetype else { return }
        guard wallet >= archetype.price else {
            Haptics.error()
            toastFlash("Need \(Tally.compact(archetype.price)) Gavels for \(archetype.title). Top up.")
            return
        }
        let before = me.auctionCredit
        wallet -= archetype.price
        me.archetype = archetype
        // Trillionaire is earned: buying only unlocks the *attempt*. Verification
        // resets and must be re-won on a confirmed $9,999 date.
        me.trillionaireVerified = false
        Haptics.success()
        if archetype == .trillionaire {
            toastFlash("Trillionaire pending — pay $9,999 on a date and get confirmed to verify.")
        } else {
            toastFlash(archetype == .none ? "Rating removed." : "You're now a \(archetype.title).")
        }
        creditPing(before: before)
        save()
    }

    /// Grant Gavels from a verified StoreKit consumable purchase. Wired to
    /// `StoreKitService.onCredit` at app root.
    func creditGavels(_ amount: Int) {
        wallet += amount
        Haptics.success()
        toastFlash("Topped up \(Tally.compact(amount)) Gavels.")
        save()
    }

    /// Claw Gavels back when Apple refunds a pack. Floors at zero.
    func revokeGavels(_ amount: Int) {
        wallet = max(0, wallet - amount)
        toastFlash("Refund processed — \(Tally.compact(amount)) Gavels removed.")
        save()
    }

    /// Poll for refunds that landed while the app was backgrounded. Called from
    /// the app root's `.onChange(of: scenePhase)` when returning to foreground.
    ///
    /// Two channels feed the wallet clawback:
    ///   1. `storeKit.drainPending()` — StoreKit's own `Transaction.all` sweep,
    ///      which sees refunds only when Apple has already flagged the
    ///      revocation in the receipt.
    ///   2. The Worker's `/refunds/pending` queue — Apple's ASSN V2 webhook
    ///      lands there in seconds, well before StoreKit surfaces it, and it
    ///      also catches refunds that the on-device path misses entirely.
    ///
    /// Both paths write into the SAME `rev-<txID>` dedup set so a refund seen
    /// twice can't double-debit the wallet.
    func refreshPendingRefunds(storeKit: StoreKitService, backend: BackendService) async {
        await storeKit.drainPending()
        await applyWorkerRefunds(backend: backend)
    }

    /// Shared dedup with `StoreKitService.checkRevocation` — both paths key on
    /// `"rev-<transaction id>"`, so we can't debit twice.
    private static let revokedKey = "auctionbaby.storekit.revoked.v1"
    /// Records how much each refund actually clawed, so a REFUND_REVERSED
    /// restores exactly that — not the full pack price when the wallet was
    /// already empty at claw time.
    private static let clawedKey = "auctionbaby.refunds.clawed.v1"

    private func applyWorkerRefunds(backend: BackendService) async {
        guard backend.isConfigured else { return }
        let entries: [BackendService.RefundEntry]
        switch await backend.fetchPendingRefunds(appAccountToken: appAccountToken) {
        case .success(let list) where !list.isEmpty: entries = list
        default: return
        }

        var revoked = Set(UserDefaults.standard.array(forKey: Self.revokedKey) as? [String] ?? [])
        var clawed = UserDefaults.standard.dictionary(forKey: Self.clawedKey) as? [String: Int] ?? [:]
        var ackedIDs: [String] = []

        for entry in entries {
            let txID = entry.transactionId
            guard !txID.isEmpty else { continue }
            let gavels = StoreKitService.gavels(for: entry.productId)
            guard gavels > 0 else {
                // Unknown/non-Gavel product (a Boost or Pass tier) — nothing
                // for us to claw, but ack it or the Worker re-serves forever.
                ackedIDs.append(txID)
                continue
            }
            let revTag = "rev-\(txID)"
            switch entry.kind {
            case "refunded":
                if !revoked.contains(revTag) {
                    let before = wallet
                    wallet = max(0, wallet - gavels)
                    let actuallyClawed = before - wallet
                    revoked.insert(revTag)
                    clawed[txID] = actuallyClawed
                    if actuallyClawed > 0 {
                        toastFlash("Refund processed — \(Tally.compact(actuallyClawed)) Gavels removed.")
                        ErrorMonitor.shared.record(category: "StoreKit",
                                                   message: "Worker-refund clawback: \(actuallyClawed) Gavels",
                                                   detail: "txn \(txID), product \(entry.productId)")
                    }
                }
            case "refund_reversed":
                let restore = clawed[txID] ?? (revoked.contains(revTag) ? gavels : 0)
                clawed.removeValue(forKey: txID)
                if restore > 0 {
                    wallet += restore
                    toastFlash("Refund reversed — \(Tally.compact(restore)) Gavels restored.")
                }
            default:
                break
            }
            ackedIDs.append(txID)
        }

        UserDefaults.standard.set(Array(revoked), forKey: Self.revokedKey)
        UserDefaults.standard.set(clawed, forKey: Self.clawedKey)
        await backend.ackRefunds(appAccountToken: appAccountToken, transactionIDs: ackedIDs)
        save()
    }

    /// Whether a Spotlight Boost is currently live.
    var isBoosted: Bool { (boostUntil ?? .distantPast) > .now }

    /// Activate a 30-minute Spotlight Boost (called from a verified purchase).
    func activateBoost() {
        let base = isBoosted ? (boostUntil ?? .now) : .now
        boostUntil = base.addingTimeInterval(Double(StoreKitService.boostMinutes) * 60)
        Haptics.success()
        toastFlash(role == .woman
                   ? "⚡️ Spotlight Boost live — bidders are flocking to your lot."
                   : "⚡️ Spotlight Boost live — top of the floor for \(StoreKitService.boostMinutes) min.")
        if role == .woman { startBoostSummons() }
        log(.boost, "Spotlight Boost activated.")
        save()
    }

    private var boostLoopActive = false

    /// While a woman is boosted, bidders keep arriving — the visible payoff of
    /// the Spotlight on the lot side.
    private func startBoostSummons() {
        guard !boostLoopActive else { return }
        boostLoopActive = true
        scheduleNextBoostSummon()
    }

    private func scheduleNextBoostSummon() {
        guard isBoosted, role == .woman else { boostLoopActive = false; return }
        after(Double.random(in: 7...13)) { [weak self] in
            guard let self else { return }
            guard self.isBoosted, self.role == .woman else { self.boostLoopActive = false; return }
            self.summonBidder()
            self.scheduleNextBoostSummon()
        }
    }

    // MARK: - Daily streak & Pass perks

    /// Base daily reward; multiplied by the streak (capped at 7×). The classic
    /// come-back-tomorrow loop, paid in Gavels.
    static let dailyGavelBase = 50

    func canClaimDaily(now: Date = .now) -> Bool {
        guard let last = lastDailyClaim else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: now)
    }

    /// Claim today's Gavels. Consecutive days grow the streak; a missed day
    /// resets it. `now` is injectable so the streak math is unit-testable.
    func claimDaily(now: Date = .now) {
        guard canClaimDaily(now: now) else { return }
        if let last = lastDailyClaim,
           let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: last),
           Calendar.current.isDate(nextDay, inSameDayAs: now) {
            dailyStreak += 1
        } else {
            dailyStreak = 1
        }
        lastDailyClaim = now
        let reward = Self.dailyGavelBase * min(dailyStreak, 7)
        wallet += reward
        Haptics.success()
        toastFlash("Day \(dailyStreak) streak — +\(Tally.compact(reward)) Gavels.")
        log(.daily, "Claimed your day-\(dailyStreak) streak: \(Tally.compact(reward)) Gavels.")
        save()
    }

    func canClaimWeeklyBoost(now: Date = .now) -> Bool {
        guard let last = lastWeeklyBoostClaim else { return true }
        return now.timeIntervalSince(last) >= 7 * 24 * 3600
    }

    /// The Paddle perk made real: any Pass includes one free Boost per week.
    /// The caller gates on subscription state (the store owns no StoreKit ref).
    func claimWeeklyBoost(now: Date = .now) {
        guard canClaimWeeklyBoost(now: now) else { return }
        lastWeeklyBoostClaim = now
        activateBoost()
    }

    /// Demo-only top-up so the higher tiers are explorable without a sandbox
    /// purchase. Clearly labelled as demo in the UI; never charges anything.
    func addDemoGavels(_ amount: Int = 10_000) {
        wallet += amount
        Haptics.tap()
        toastFlash("Demo: added \(Tally.compact(amount)) Gavels (no charge).")
        save()
    }

    // MARK: - Lot (woman) actions

    static let maxStartingBid = 10_000_000

    /// Save an edited photo set from `PhotoEditorSheet`. Empty primary + empty
    /// gallery is legal — the app falls back to the gradient monogram.
    func updateProfilePhotos(primary: Data?, gallery: [Data]) {
        me.photoData = primary
        me.photoGallery = gallery
        save()
        toastFlash(primary == nil ? "Photos cleared." : "Photos updated.")
    }

    func setStartingBid(_ value: Int?) {
        guard role == .woman else { return }
        me.startingBid = value.map { max(0, min($0, Self.maxStartingBid)) }
        save()
    }

    func accept(_ bid: Bid) {
        guard let idx = incomingBids.firstIndex(where: { $0.id == bid.id }),
              incomingBids[idx].status == .pending else { return }   // idempotent: no double-credit
        incomingBids[idx].status = .accepted
        let accepted = incomingBids[idx]
        earnings += accepted.amount

        // The woman always sends the first invite (per the brief).
        var match = Match(bid: accepted, phase: .chatting)
        match.messages = [
            ChatMessage(fromMe: true, text: "You're in. \(accepted.man.name) — let's set a date. 🍸", isSystem: false),
        ]
        match.expiresAt = Date().addingTimeInterval(24 * 3600)
        matches.insert(match, at: 0)
        Haptics.success()
        toastFlash(accepted.qualifiesForMasterpiece
                   ? "A Trillionaire's bid accepted — a Masterpiece is in reach."
                   : "Bid accepted. Invite sent to \(accepted.man.name).")
        celebrate(with: accepted.man, amount: accepted.amount,
                  copycat: accepted.onCopycat, masterpiece: accepted.qualifiesForMasterpiece)
        log(.bidAccepted, "You accepted \(accepted.man.name)'s \(Money.compact(accepted.amount)) bid.")
        save()
        scheduleSuitorReply(matchID: match.id)
    }

    /// Run the simulated selfie-match verification for the logged-in user.
    func verifyMe() {
        guard !me.verified else { return }
        let before = role == .woman ? me.showcaseCredit : me.auctionCredit
        me.verified = true
        Haptics.success()
        toastFlash("You're verified ✓ — bidders trust a real face.")
        log(.verified, "You're now identity verified.")
        creditPing(before: before)
        save()
    }

    func decline(_ bid: Bid) {
        guard let idx = incomingBids.firstIndex(where: { $0.id == bid.id }),
              incomingBids[idx].status == .pending else { return }   // can't decline an accepted bid
        incomingBids[idx].status = .declined
        Haptics.tap()
        save()
    }

    /// Demo helper — summon a fresh bidder to the inbox. `trillionaire: true`
    /// guarantees a $1M Masterpiece-eligible bid so that flow is reachable.
    func summonBidder(trillionaire: Bool = false) {
        guard role == .woman else { return }
        let raw = bidders.isEmpty ? SampleData.suitors() : bidders
        let pool = raw.filter { !blockedIDs.contains($0.id) }
        guard !pool.isEmpty else { return }
        var man = pool.randomElement() ?? pool[0]
        let amount: Int
        if trillionaire {
            // The first verified Trillionaire himself comes to bid.
            man = pool.first { $0.archetype == .trillionaire } ?? pool[0]
            amount = Bid.masterpieceBid   // $1,000,000 — the Masterpiece-minting bid
        } else {
            let floor = min(me.startingBid ?? 150, Self.maxStartingBid)
            amount = Int(Double(floor) * Double.random(in: 0.7...2.4))
        }
        let note = trillionaire
            ? "I read the rules — I wrote them. One million dollars for one evening. Confirm it and mint your Masterpiece."
            : ["Saw your profile. Worth every cent.", "Dinner, my treat — name the place.",
               "I don't usually bid this high.", "Let me take you somewhere ridiculous."].randomElement()!
        let bid = Bid(man: man, woman: me, amount: amount, note: note)
        incomingBids.insert(bid, at: 0)
        Haptics.commit()
        toastFlash(trillionaire ? "A Trillionaire just bid \(Money.compact(amount))."
                                : "\(man.name) bid \(Money.compact(amount)).")
        log(.bidReceived, "\(man.name) bid \(Money.compact(amount))\(trillionaire ? " — a Trillionaire!" : ".")")
        save()
    }

    // MARK: - Chat (shared)

    func send(_ text: String, in match: Match) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        matches[idx].messages.append(ChatMessage(fromMe: true, text: trimmed))
        matches[idx].seenByOther = false   // reset; they haven't read the new one yet
        matches[idx].expiresAt = nil       // she/he replied — the urgency clock stops
        save()
        scheduleSeen(matchID: match.id)
        scheduleCounterpartReply(matchID: match.id)
    }

    /// Double-tap a bubble to react (iMessage-style). Toggles off if it's
    /// already that emoji, otherwise sets/replaces the reaction.
    func toggleReaction(_ emoji: String, on messageID: UUID, in match: Match) {
        guard let mIdx = matches.firstIndex(where: { $0.id == match.id }),
              let msgIdx = matches[mIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let current = matches[mIdx].messages[msgIdx].reaction
        matches[mIdx].messages[msgIdx].reaction = (current == emoji) ? nil : emoji
        Haptics.selection()
        save()
    }

    /// Undo your most recent live bid — a Reserve+/Black Card Pass perk. Only
    /// the single latest pending bid can be recalled, and only before she's
    /// decided; her simulated decision task checks the array by id, so
    /// removing it here makes any in-flight decision a silent no-op.
    func canRewindLastBid() -> Bool {
        guard let latest = outgoingBids.first else { return false }
        return latest.status == .pending
    }

    func rewindLastBid() {
        guard canRewindLastBid(), let latest = outgoingBids.first else { return }
        if latest.gilded { wallet += Self.gildedBidCost }   // refund the Gavel spend
        outgoingBids.removeFirst()
        Haptics.tap()
        toastFlash("Bid on \(latest.woman.name) recalled — \(Money.compact(latest.amount)) rewound.")
        save()
    }

    /// The counterpart "reads" your message a beat before replying — drives the
    /// Black Card read-receipt indicator.
    private func scheduleSeen(matchID: UUID) {
        after(Double.random(in: 0.6...1.1)) { [weak self] in
            guard let self, let idx = self.matches.firstIndex(where: { $0.id == matchID }) else { return }
            guard self.matches[idx].phase == .chatting else { return }
            self.matches[idx].seenByOther = true
            self.save()
        }
    }

    func markDateDone(_ match: Match) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }) else { return }
        guard matches[idx].phase == .chatting else { return }
        matches[idx].phase = .dateDone
        matches[idx].messages.append(
            ChatMessage(fromMe: true, text: "Date completed — leave your review.", isSystem: true))
        Haptics.commit()
        save()
    }

    // MARK: - Reviews

    /// Bidder reviews the woman after the date (the man-user path). Captures what
    /// he *actually* spent — which becomes the woman's verdict on whether he's a
    /// deadbeat.
    func completeAsMan(_ match: Match, stars: Int, traits: [Trait: Int],
                       categories: [String], text: String, actuallySpent: Int) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }),
              !matches[idx].manReviewedWoman else { return }   // one review per date
        let bid = matches[idx].bid

        let creditBefore = me.auctionCredit
        // NOTE: no in-app debit here. A bid is a letter of intent — the date
        // money is settled in the real world, peer-to-peer. `actuallySpent` is
        // only what he reports paying in person, which she confirms or disputes;
        // it drives his deadbeat score and Trillionaire verification, nothing more.

        // His review of her — stored on the match and reflected on the floor.
        var traitDict: [String: Int] = [:]
        for (t, v) in traits { traitDict[t.rawValue] = v }
        let review = DateReview(authorName: me.name, authorHue: me.hue, stars: stars, text: text,
                                traits: traitDict, interestCategories: categories)
        // The woman's verdict on him → updates *his* deadbeat / credit score.
        let paid = actuallySpent >= bid.amount

        if let f = floor.firstIndex(where: { $0.id == bid.woman.id }) {
            floor[f].reviews.insert(review, at: 0)
            // She only mints a Masterpiece if he actually paid the full $1,000,000.
            if bid.qualifiesForMasterpiece && paid { floor[f].masterpiece = true }
        }
        matches[idx].manReviewedWoman = true
        // Her written verdict is chosen to match his credit, so the comment and
        // the number never contradict each other: paying short always reads bad,
        // and among men who paid, the praise scales with his standing.
        let verdict = ReviewCopy.manVerdict(paid: paid, credit: creditBefore,
                                            bidAmount: bid.amount, spentAmount: actuallySpent)
        me.reviews.insert(
            DateReview(authorName: bid.woman.name, authorHue: bid.woman.hue,
                       stars: verdict.stars, text: verdict.text,
                       paidBid: paid, bidAmount: bid.amount, spentAmount: actuallySpent),
            at: 0)

        // Trillionaire is earned here: he bought the badge, bid & paid the full
        // $9,999, and the woman (sim) confirmed it. That's the third gate.
        if me.archetype == .trillionaire && !me.trillionaireVerified
            && bid.amount >= Archetype.trillionaire.price
            && actuallySpent >= Archetype.trillionaire.price && paid {
            me.trillionaireVerified = true
            closeMatch(idx)
            Haptics.success()
            toastFlash("✦ TRILLIONAIRE VERIFIED — she confirmed your $9,999.")
            log(.trillionaire, "You're a verified Trillionaire — \(bid.woman.name) confirmed your $9,999.")
            save()
            return
        }

        closeMatch(idx)
        Haptics.success()
        toastFlash(paid ? "Review posted. Your credit just went up."
                        : "Review posted. Paying short dented your credit.")
        log(.reviewReceived, "\(bid.woman.name) reviewed your date.")
        creditPing(before: creditBefore)
        save()
    }

    /// Woman reviews the man after the date (the woman-user path). Records the
    /// deadbeat verdict; a paid Trillionaire mints her Masterpiece.
    func completeAsWoman(_ match: Match, paid: Bool, stars: Int, text: String) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }),
              !matches[idx].womanReviewedMan else { return }   // one review per date
        let bid = matches[idx].bid

        // Her verdict on him — stored on the match. The woman's stars and text
        // feed into the man's record (cosmetic — he isn't the user).
        matches[idx].womanReviewedMan = true
        if let manIdx = bidders.firstIndex(where: { $0.id == bid.man.id }) {
            bidders[manIdx].reviews.insert(
                DateReview(authorName: me.name, authorHue: me.hue, stars: stars, text: text,
                           paidBid: paid, bidAmount: bid.amount), at: 0)
        }

        let showcaseBefore = me.showcaseCredit
        let tierBefore = me.artTier
        // His simulated review of her → grows *her* Showcase score.
        var traits: [String: Int] = [:]
        for t in Trait.allCases { traits[t.rawValue] = Int.random(in: 4...5) }
        me.reviews.insert(
            DateReview(authorName: bid.man.name, authorHue: bid.man.hue, stars: Int.random(in: 4...5),
                       text: "Effortless company. Worth the bid.", traits: traits,
                       interestCategories: Array(me.interests.prefix(2))),
            at: 0)

        // Deadbeat: claw back earnings credited at acceptance.
        if !paid { earnings = max(0, earnings - bid.amount) }
        if bid.qualifiesForMasterpiece && paid {
            me.masterpiece = true
            // Her confirmation is also what verifies his Trillionaire status on record.
            matches[idx].bid.man.trillionaireVerified = true
            Haptics.success()
            toastFlash("✦ MASTERPIECE minted. A verified Trillionaire paid in full.")
            log(.masterpiece, "✦ Masterpiece minted by \(bid.man.name).")
        } else {
            Haptics.commit()
            toastFlash(paid ? "Review posted. He paid in full."
                            : "Review posted. Flagged as a deadbeat.")
            log(.reviewReceived, "\(bid.man.name) reviewed your date.")
        }
        creditPing(before: showcaseBefore)
        // Ladder climb — the reward moment for the honors system.
        if me.artTier > tierBefore && me.artTier != .masterpiece {
            Haptics.success()
            toastFlash("🖼 You've been rehung: you're now a \(me.artTier.title).")
            log(.honors, "Climbed the honors ladder — now a \(me.artTier.title).")
        }
        closeMatch(idx)
        save()
    }

    private func closeMatch(_ idx: Int) {
        matches[idx].phase = .closed
        matches[idx].messages.append(
            ChatMessage(fromMe: true, text: "Reviews are in. This lot is closed.", isSystem: true))
    }

    /// Log a credit movement whenever a headline score shifts — the "your
    /// number moved" ping that makes the bureau feel alive. Call with the
    /// score captured before the mutation.
    private func creditPing(before: Int) {
        let after = role == .woman ? me.showcaseCredit : me.auctionCredit
        guard after != before else { return }
        let delta = after - before
        let arrow = delta > 0 ? "▲" : "▼"
        log(.credit, "\(role == .woman ? "Showcase" : "Auction") Credit \(arrow)\(abs(delta)) — now \(after).")
    }

    // MARK: - Celebration

    /// Fire the full-screen "SOLD!" moment for a freshly-made match.
    private func celebrate(with other: Profile, amount: Int, copycat: Bool, masterpiece: Bool) {
        celebration = MatchCelebration(
            otherName: other.name, otherHue: other.hue, otherPhoto: other.photoName,
            otherCopycat: copycat, otherCopycatStyle: other.copycatStyle,
            otherVerified: other.verified,
            meName: me.name.isEmpty ? "You" : me.name, meHue: me.hue, mePhoto: me.photoName,
            amount: amount, masterpiece: masterpiece)
    }

    // MARK: - Simulation

    /// A woman's automated decision on a bidder's offer.
    private func scheduleWomanDecision(bidID: UUID) {
        let copycat = outgoingBids.first(where: { $0.id == bidID })?.onCopycat ?? false
        after(copycat ? 1.6 : Double.random(in: 2.5...4.2)) { [weak self] in
            guard let self, let idx = self.outgoingBids.firstIndex(where: { $0.id == bidID }) else { return }
            guard self.outgoingBids[idx].status == .pending else { return }
            var bid = self.outgoingBids[idx]

            let accepted: Bool
            if bid.onCopycat {
                accepted = true // copycats always "accept" — that's the bait
            } else {
                let threshold = bid.woman.startingBid ?? max(100, bid.woman.marketValue / 2)
                // Money + reputation both move the needle.
                let ratio = Double(bid.amount) / Double(threshold)
                let creditPull = Double(self.me.auctionCredit - 600) / 300.0
                let boostPull = self.isBoosted ? 0.25 : 0
                let gildPull = bid.gilded ? 0.30 : 0
                let priorityPull = self.priorityPlacementEnabled ? 0.20 : 0
                accepted = (ratio + creditPull + boostPull + gildPull + priorityPull + Double.random(in: -0.25...0.25)) >= 1.0
            }

            bid.status = accepted ? .accepted : .declined
            self.outgoingBids[idx] = bid

            if accepted {
                var match = Match(bid: bid, phase: .chatting)
                let opener = bid.onCopycat
                    ? "Hey you 😊 so glad you bid. Quick thing — I ask for a small deposit before I give out my number. It just filters out the games, hope you get it 💕"
                    : "Okay, you win. \(bid.woman.name) here — where are you taking me?"
                match.messages = [ChatMessage(fromMe: false, text: opener)]
                match.expiresAt = Date().addingTimeInterval(24 * 3600)
                self.matches.insert(match, at: 0)
                Haptics.success()
                self.toastFlash("\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid!")
                // Copycats were already revealed at bid time — no second reveal.
                if !bid.onCopycat {
                    self.celebrate(with: bid.woman, amount: bid.amount,
                                   copycat: false, masterpiece: bid.qualifiesForMasterpiece)
                }
                self.log(.bidAccepted, "\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid.")
            } else {
                let before = self.me.auctionCredit
                self.me.declinedBids += 1
                if self.autoRebidEnabled && !bid.onCopycat {
                    let raised = Int(Double(bid.amount) * 1.2)
                    var rebid = Bid(man: self.me, woman: bid.woman, amount: raised, note: bid.note)
                    rebid.gilded = bid.gilded
                    self.outgoingBids.insert(rebid, at: 0)
                    Haptics.commit()
                    self.toastFlash("Auto-rebid: \(Money.compact(raised)) on \(bid.woman.name).")
                    self.log(.rebid, "Auto-rebid \(Money.compact(raised)) on \(bid.woman.name) (Reserve perk).")
                    self.scheduleWomanDecision(bidID: rebid.id)
                } else {
                    Haptics.warning()
                    self.toastFlash("\(bid.woman.name) passed. Bid higher or build your reputation.")
                }
                self.log(.bidDeclined, "\(bid.woman.name) passed on your \(Money.compact(bid.amount)) bid.")
                self.creditPing(before: before)
            }
            self.save()
        }
    }

    private func scheduleSuitorReply(matchID: UUID) {
        typingMatchID = matchID
        after(Double.random(in: 1.8...3.0)) { [weak self] in
            guard let self, let idx = self.matches.firstIndex(where: { $0.id == matchID }) else { return }
            if self.typingMatchID == matchID { self.typingMatchID = nil }
            let line = self.matches[idx].bid.onCopycat
                ? "Did you see my message about the deposit? It's a small thing, promise 😘"
                : ["Thursday works for me — I know a place.", "Looking forward to this, honestly.",
                   "I made us a reservation. Don't be late.", "Wear something you can dance in."].randomElement()!
            self.matches[idx].messages.append(ChatMessage(fromMe: false, text: line))
            self.matches[idx].expiresAt = nil   // the conversation is alive — clock stops
            self.save()
        }
    }

    private func scheduleCounterpartReply(matchID: UUID) {
        typingMatchID = matchID
        after(Double.random(in: 1.4...2.6)) { [weak self] in
            guard let self, let idx = self.matches.firstIndex(where: { $0.id == matchID }) else { return }
            if self.typingMatchID == matchID { self.typingMatchID = nil }
            guard self.matches[idx].phase == .chatting else { return }
            let copycat = self.matches[idx].bid.onCopycat
            let lines = copycat
                ? ["Once the deposit clears we can plan everything 💕", "You still there? The deposit only takes a minute.",
                   "I don't meet anyone without it, it's a safety thing for me 😊"]
                : ["Looking forward to it.", "Okay tell me your worst date story — I'll trade you mine.",
                   "Counting down, not going to lie.", "You're funnier over text than your profile let on."]
            self.matches[idx].messages.append(ChatMessage(fromMe: false, text: lines.randomElement()!))
            self.matches[idx].expiresAt = nil   // the conversation is alive — clock stops
            self.save()
        }
    }

    private func seedIncomingBids() {
        let suitors = bidders.isEmpty ? SampleData.suitors() : bidders
        guard suitors.count > 3 else { return }
        let base = min(me.startingBid ?? 150, Self.maxStartingBid)
        incomingBids = [
            Bid(man: suitors[0], woman: me, amount: max(300, base &* 2),
                note: "Saw your prompts. Dinner at Carbone? My treat."),
            Bid(man: suitors[3], woman: me, amount: max(120, base),
                note: "I'll lose at trivia and pay anyway."),
        ]
    }

    // MARK: - Helpers

    /// Run `work` on the main actor after `seconds`. Keeps actor isolation clean
    /// for the simulation timers.
    private func after(_ seconds: Double, _ work: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            work()
        }
    }

    private var toastTask: Task<Void, Never>?
    func toastFlash(_ message: String) {
        Motion.run(Motion.snap) { toast = message }
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            Motion.run(Motion.smooth) { self.toast = nil }
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var role: Role?
        var me: Profile
        var wallet: Int
        var earnings: Int
        var boostUntil: Date?
        var floor: [Profile]
        var bidders: [Profile]?
        var incomingBids: [Bid]
        var outgoingBids: [Bid]
        var matches: [Match]
        var filters: FilterPreferences
        var blockedIDs: [UUID]
        var activity: [ActivityEvent]?
        var dailyStreak: Int?
        var lastDailyClaim: Date?
        var lastWeeklyBoostClaim: Date?
        var appAccountToken: UUID?
        var demoMode: Bool?
    }

    private let encryptedArchive = EncryptedArchive(filename: "auctionbaby-state.aesgcm")

    private func save() {
        let snap = Snapshot(role: role, me: me, wallet: wallet, earnings: earnings,
                            boostUntil: boostUntil, floor: floor, bidders: bidders,
                            incomingBids: incomingBids,
                            outgoingBids: outgoingBids, matches: matches,
                            filters: filters, blockedIDs: Array(blockedIDs), activity: activity,
                            dailyStreak: dailyStreak, lastDailyClaim: lastDailyClaim,
                            lastWeeklyBoostClaim: lastWeeklyBoostClaim,
                            appAccountToken: appAccountToken, demoMode: demoMode)
        if let data = try? JSONEncoder().encode(snap) {
            store.set(data, forKey: Self.key)
        }
        encryptedArchive.save(snap)
    }

    private func load() {
        // Try encrypted archive first (preferred), fall back to UserDefaults for
        // backward compatibility with pre-encryption installs.
        let snap: Snapshot? = encryptedArchive.load(Snapshot.self) ?? {
            guard let data = store.data(forKey: Self.key) else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: data)
        }()
        guard let snap else { return }
        role = snap.role
        me = snap.me
        wallet = snap.wallet
        earnings = snap.earnings
        boostUntil = snap.boostUntil
        floor = snap.floor.isEmpty ? SampleData.floor() : snap.floor
        bidders = (snap.bidders?.isEmpty ?? true) ? SampleData.suitors() : snap.bidders!
        incomingBids = snap.incomingBids
        outgoingBids = snap.outgoingBids
        matches = snap.matches
        filters = snap.filters
        blockedIDs = Set(snap.blockedIDs)
        activity = snap.activity ?? []
        dailyStreak = snap.dailyStreak ?? 0
        lastDailyClaim = snap.lastDailyClaim
        lastWeeklyBoostClaim = snap.lastWeeklyBoostClaim
        appAccountToken = snap.appAccountToken ?? appAccountToken
        demoMode = snap.demoMode ?? false
        if isBoosted, role == .woman { startBoostSummons() }
        for bid in outgoingBids where bid.status == .pending {
            scheduleWomanDecision(bidID: bid.id)
        }
    }
}
