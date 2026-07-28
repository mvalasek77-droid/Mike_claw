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
    @Published var earnings: Int = 0            // woman side: sum of accepted bids (a local display total, NOT payment; clawed back on a deadbeat verdict). Never networked.
    @Published var boostUntil: Date?           // active Spotlight Boost expiry, if any
    @Published var dailyStreak: Int = 0        // consecutive days claimed
    @Published var lastDailyClaim: Date?
    @Published var lastWeeklyBoostClaim: Date? // Pass perk: one free Boost / week
    /// Day-key of the last Lot-of-the-Day intro sheet the user saw. Set to
    /// `Calendar.startOfDay` so a new day flips it clean.
    @Published var lastLotOfDaySeen: Date?
    /// The Docket — streak-freeze inventory. Each token consumed automatically
    /// on a missed day (in claimDaily) protects the streak from resetting.
    @Published var streakFreezeCount: Int = 0
    /// Whisper nods whose follow-up real bid hasn't landed yet. Persisted so
    /// a kill inside the 2–4s follow-up window re-arms on next launch.
    var pendingNodManIDs: Set<UUID> = []

    /// Per-user UUID attached to every IAP purchase so Apple server notifications
    /// can route refunds to the correct wallet. Generated once, persisted forever.
    @Published private(set) var appAccountToken: UUID = UUID()

    /// Fires after any explicit profile-mutating function (register, edit-name,
    /// updateProfilePhotos, updateOpeningBidScript, updateArchetype-adjacent).
    /// Wired at app root to `ProfileService.uploadMyProfile(from:)` so signed-in
    /// users' server-side public profile stays in sync with the local record.
    /// Absent hook / local-only session → nothing happens.
    var onProfileChanged: ((Profile) -> Void)?

    /// Demo Mode for Apple App Review. Activated by registering with the name
    /// "demo" (case-insensitive) — see DEMO_MODE.md. Free demo top-ups and a
    /// free demo Pass appear in the store surfaces; everything else (bidding,
    /// matches, copycat reveals, reviews) is identical to production. Persists
    /// across launches; cleared by Reset account.
    @Published private(set) var demoMode = false

    @Published var floor: [Profile] = []        // women a bidder browses (sim)
    /// Slice 4b1a — real signed-in women fetched from the auth Worker's
    /// `GET /users/floor` feed. Populated on foreground/appear by
    /// `refreshRemoteFloor(profileSync:)` when the user is signed in and
    /// the auth Worker is wired. Empty otherwise → the UI falls back to the
    /// sim `floor` above, which is what Demo Mode + local-only sessions use.
    @Published var remoteFloor: [Profile] = []
    /// When true, `filteredFloor` sources from `remoteFloor`; when false,
    /// from `floor` (the sim). Flipped by the refresh cycle — a signed-in
    /// user whose fetch returned zero real profiles stays on the sim so the
    /// UI isn't blank while the platform is bootstrapping.
    @Published private(set) var isRemoteFloor: Bool = false

    /// Slice 4b1b — real bids in a signed-in woman's inbox, fetched from the
    /// matching Worker's `GET /bids/incoming`. Populated by
    /// `refreshRemoteInbox(matching:)` on foreground/appear + when a
    /// bid-received push wakes the app. Empty otherwise → UI falls back to
    /// the sim `incomingBids` (what Demo Mode uses).
    @Published var remoteIncomingBids: [Bid] = []
    /// Flipped once a signed-in user's fetch has been performed; then the
    /// inbox UI reads from `remoteIncomingBids` even when it's empty (a signed
    /// in user with zero real bids should see an empty inbox, not seeded sim
    /// bids). Demo Mode + local-only sessions never flip this.
    @Published private(set) var isRemoteInbox: Bool = false

    /// Slice 4b1c — outgoing bids the signed-in bidder has placed via the
    /// matching Worker. Optimistically appended on `placeRemoteBid` success;
    /// full refresh from `GET /bids/outgoing` lands here in slice 4b1d.
    @Published var remoteOutgoingBids: [Bid] = []
    /// Same semantics as `isRemoteInbox` — once a signed-in bidder has placed
    /// any real bid, MyBidsView reads from the remote list. Sim-only sessions
    /// never flip it, so Demo Mode keeps the sim outgoing behavior.
    @Published private(set) var isRemoteOutgoing: Bool = false
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

    /// Set by the app root when the user has Reserve or Black Card.
    var autoRebidEnabled = false
    /// Set by the app root when the user has Black Card.
    var priorityPlacementEnabled = false

    var isRegistered: Bool { role != nil }

    /// Free bidders may keep this many *live* (pending) bids at once. A Pass
    /// lifts the cap — the "unlimited bids" perk.
    static let freeActiveBidLimit = 3
    /// Gavel cost of gilding a bid (the premium "Rose" move).
    static let gildedBidCost = 250
    /// Bid Insurance premium — small Gavel amount added on top of a bid.
    /// Refunded plus a Gilded Bid credit when she declines. Deliberately
    /// cheaper than the Gilded fee so the ceiling on total spend stays sane.
    static let bidInsuranceCost = 200
    /// Free live-bid ceiling: only real bids count. Whispers are a
    /// zero-Gavel signal that shouldn't sink you into the paywall.
    var activePendingBidCount: Int {
        outgoingBids.filter { $0.status == .pending && !$0.isWhisper }.count
    }

    // MARK: Woman-side insights ("what you're worth")
    // Whispers are anonymous $0 signals — counting them as "live bidders"
    // would inflate her demand dashboard with non-committal noise.
    private var livePending: [Bid] { incomingBids.filter { $0.status == .pending && !$0.isWhisper } }
    var liveBidCount: Int { livePending.count }
    var highestLiveBid: Int { livePending.map(\.amount).max() ?? 0 }
    var totalOnTable: Int { livePending.map(\.amount).reduce(0, +) }
    var acceptedCount: Int { incomingBids.filter { $0.status == .accepted && !$0.isWhisper }.count }

    /// The floor after blocks + filters are applied — what the bidder actually
    /// sees. Sources from `remoteFloor` (real signed-in women) when it's
    /// active, otherwise `floor` (the sim). Demo Mode + local-only sessions
    /// always see the sim — `isRemoteFloor` only ever flips true for a
    /// signed-in user whose fetch returned real profiles.
    var filteredFloor: [Profile] {
        let source = isRemoteFloor ? remoteFloor : floor
        return source.filter { !blockedIDs.contains($0.id) && filters.matches($0) }
    }

    /// The Lot of the Day — a real (non-copycat) lot, rotating daily and
    /// favouring verified, high-Showcase profiles. Rendered as the pinned
    /// gold-framed hero above the floor and as the once-a-day full-screen
    /// intro (`shouldShowLotOfDayIntro`).
    var lotOfTheDay: Profile? {
        let pool = filteredFloor.filter { !$0.isCopycat }
            .sorted { ($0.verified ? 1 : 0, $0.showcaseScore) > ($1.verified ? 1 : 0, $1.showcaseScore) }
        guard !pool.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return pool[day % pool.count]
    }

    /// True the first time the user opens the app on a new calendar day.
    /// The feed presents the full-screen "Tonight's Lot" moment; dismissing
    /// it stamps `lastLotOfDaySeen`, so it never re-fires the same day.
    var shouldShowLotOfDayIntro: Bool {
        guard role == .man, lotOfTheDay != nil else { return false }
        guard let last = lastLotOfDaySeen else { return true }
        return !Calendar.current.isDate(last, inSameDayAs: Date())
    }

    func markLotOfDaySeen() {
        lastLotOfDaySeen = Calendar.current.startOfDay(for: Date())
        save()
    }

    // MARK: - The Standing (weekly leaderboards)

    /// One line on the leaderboard — a profile plus their numeric standing.
    struct StandingEntry: Identifiable, Hashable {
        let id: UUID           // profile.id
        let name: String
        let hue: Double
        let photoName: String?
        let photoData: Data?
        let value: Int
        let subtitle: String
        let isYou: Bool
    }

    /// Loose locality match: compare the last comma-separated component of
    /// each location, case-insensitively ("Tribeca, New York" ↔ "new york").
    /// Exact string equality made every real user's leaderboard empty —
    /// nobody types "Venice, Los Angeles" into a free-text field.
    private static func sameCity(_ a: String, _ b: String) -> Bool {
        func token(_ s: String) -> String {
            (s.split(separator: ",").last.map(String.init) ?? s)
                .trimmingCharacters(in: .whitespaces).lowercased()
        }
        let ta = token(a), tb = token(b)
        guard !ta.isEmpty, !tb.isEmpty else { return false }
        return ta == tb || ta.contains(tb) || tb.contains(ta)
    }

    /// Weekly top-bidders leaderboard for the user's city, falling back to
    /// the whole floor when the city match comes up empty (free-text
    /// locations rarely align). Reads the LIVE bidders roster and honours
    /// blocks — a reported man must never rank on her own board.
    var topBiddersInCity: [StandingEntry] {
        var pool: [Profile] = (bidders.isEmpty ? SampleData.suitors() : bidders)
            .filter { !blockedIDs.contains($0.id) }
        if role == .man { pool.append(me) }
        var scoped = me.location.isEmpty
            ? pool
            : pool.filter { Self.sameCity($0.location, me.location) || $0.id == me.id }
        // A one-row (just you) or empty board isn't a leaderboard — widen out.
        if scoped.count < 3 { scoped = pool }
        return scoped
            .sorted { $0.auctionCredit > $1.auctionCredit }
            .prefix(5)
            .map { p in
                StandingEntry(id: p.id, name: p.name, hue: p.hue, photoName: p.photoName,
                              photoData: p.photoData,
                              value: p.auctionCredit,
                              subtitle: p.creditTier,
                              isYou: p.id == me.id)
            }
    }

    /// Weekly most-contested lots — the women whose Showcase Credit runs
    /// hottest right now. Reads `floor` (already scrubbed by blockAndReport),
    /// same loose city match + widen-on-empty as the bidders board.
    var mostContestedLots: [StandingEntry] {
        let pool = floor.filter { !$0.isCopycat && !blockedIDs.contains($0.id) }
        var scoped = me.location.isEmpty
            ? pool
            : pool.filter { Self.sameCity($0.location, me.location) }
        if scoped.count < 3 { scoped = pool }
        return scoped
            .sorted { $0.showcaseCredit > $1.showcaseCredit }
            .prefix(5)
            .map { p in
                StandingEntry(id: p.id, name: p.name, hue: p.hue, photoName: p.photoName,
                              photoData: p.photoData,
                              value: p.showcaseCredit,
                              subtitle: p.showcaseTier,
                              isYou: false)
            }
    }

    /// Stable per-week seed. Used only to tag the leaderboard as "week of X"
    /// in the UI — the sort inputs are already week-stable.
    private func weekKey() -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }

    var currentWeekLabel: String { weekKey() }

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
        onProfileChanged?(me)
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
        // Newer state that must not leak into the "fresh" account.
        streakFreezeCount = 0
        lastLotOfDaySeen = nil
        pendingNodManIDs = []
        autoRebidEnabled = false
        priorityPlacementEnabled = false
        // A reset is a new identity: rotate the money-routing token and drop
        // every token-adjacent bookkeeping key. (Any undrained web-Gavel
        // balance under the old token is intentionally abandoned — the old
        // account is gone.)
        appAccountToken = UUID()
        UserDefaults.standard.removeObject(forKey: Self.pendingDrainKey)
        UserDefaults.standard.removeObject(forKey: Self.revokedKey)
        UserDefaults.standard.removeObject(forKey: Self.clawedKey)
        store.removeObject(forKey: Self.key + ".rescue")
        store.removeObject(forKey: Self.key)
        encryptedArchive.delete()
    }

    // MARK: - Bidder (man) actions

    /// Place a bid on a woman. Bids are offers — nothing is charged until a date
    /// actually happens — but bidding on an AI copycat is logged against the
    /// bidder's reputation immediately.
    /// Whisper Bid — an anonymous, no-Gavel signal of interest. She sees
    /// "someone whispered on your lot" without his identity or archetype;
    /// he can escalate to a real bid once she's nodded back. Doesn't spend
    /// Gavels, doesn't touch Auction Credit, doesn't count against the
    /// free live-bid limit. Copycats never receive whispers — the point of
    /// a Whisper is to test intent before committing, and a Copycat has
    /// nothing to test.
    func placeWhisper(on woman: Profile) {
        guard role == .man, !woman.isCopycat else { return }
        var bid = Bid(man: me, woman: woman, amount: 0, note: "")
        bid.isWhisper = true
        outgoingBids.insert(bid, at: 0)
        Haptics.tap()
        toastFlash("Whisper sent — she'll see interest, not who.")
        log(.bidReceived, "You whispered on \(woman.name).")
        // Sim: her decision timer still runs but on a lighter cadence.
        scheduleWomanDecision(bidID: bid.id)
        save()
    }

    func placeBid(on woman: Profile, amount: Int, note: String, gilded: Bool = false,
                  insured: Bool = false, promptRef: String? = nil) {
        guard role == .man, amount > 0 else { return }
        // Gilding spends Gavels up front; fall back to a normal bid if short.
        // Real currency never flows toward an AI lure — a gild/insurance attempt
        // on a copycat is silently uncharged (the reveal lands a second later).
        var gild = gilded
        if gild && woman.isCopycat {
            gild = false
        } else if gild {
            if wallet >= Self.gildedBidCost { wallet -= Self.gildedBidCost }
            else { gild = false; toastFlash("Not enough Gavels to gild — sent a standard bid.") }
        }
        // Bid Insurance premium — copycats never charge it either.
        var insure = insured
        if insure && woman.isCopycat {
            insure = false
        } else if insure {
            if wallet >= Self.bidInsuranceCost { wallet -= Self.bidInsuranceCost }
            else { insure = false }
        }
        var bid = Bid(man: me, woman: woman, amount: amount, note: note)
        bid.gilded = gild
        bid.insured = insure
        bid.promptRef = promptRef
        outgoingBids.insert(bid, at: 0)

        if woman.isCopycat {
            // A copycat bid never becomes a match or a conversation. Reveal that
            // she's fake, dock the credit, and stop. The app never role-plays a
            // scam and never asks the user for anything.
            if let i = outgoingBids.firstIndex(where: { $0.id == bid.id }) {
                outgoingBids[i].status = .declined
            }
            let before = me.auctionCredit
            me.copycatBids += 1
            Haptics.warning()
            celebrate(with: woman, amount: amount, copycat: true, masterpiece: woman.masterpiece)
            log(.bidDeclined, "You bid on \(woman.name) — a copycat, not a real person. Your Auction Credit took the hit.")
            creditPing(before: before)
            save()
            return
        }

        Haptics.commit()
        toastFlash(gild ? "✦ Gilded Bid sent to \(woman.name) — top of her inbox."
                        : "Bid placed: \(Money.compact(amount)) on \(woman.name).")
        save()
        scheduleWomanDecision(bidID: bid.id)
    }

    /// Raise a live bid — the one-tap answer to "you've been outbid". The raised
    /// amount gets a fresh decision from the (simulated) woman.
    func raiseBid(_ bidID: UUID, to newAmount: Int) {
        guard let idx = outgoingBids.firstIndex(where: { $0.id == bidID }),
              outgoingBids[idx].status == .pending,
              !outgoingBids[idx].isWhisper,   // whispers have no amount to raise
              newAmount > outgoingBids[idx].amount else { return }
        outgoingBids[idx].amount = newAmount
        Haptics.commit()
        toastFlash("Raised to \(Money.compact(newAmount)) on \(outgoingBids[idx].woman.name).")
        log(.rebid, "You raised your bid on \(outgoingBids[idx].woman.name) to \(Money.compact(newAmount)).")
        save()
        scheduleWomanDecision(bidID: bidID)
    }

    /// Buy (or switch to) a status archetype. The price is the point — it's how
    /// a man proves he has money.
    ///
    /// Every rating is a real StoreKit purchase, so this method never spends
    /// Gavels — it only handles "wear a rating I already own" (and removing
    /// the badge). Buying goes through `ArchetypeStoreView` →
    /// `storeKit.purchase`, landing back on `equipArchetype` via the
    /// `onStatusPurchased` hook once Apple confirms.
    func buyArchetype(_ archetype: Archetype) {
        guard role == .man else { return }
        guard archetype != me.archetype else { return }
        switch archetype.purchase {
        case .free:
            equipArchetype(archetype)   // "Remove rating" is always allowed
        case .money:
            // Only an already-owned rating can be worn for free. Anything else
            // must go through StoreKit — never hand out a paid badge because a
            // caller took the wrong branch.
            guard ownsArchetype(archetype) else {
                Haptics.error()
                toastFlash("\(archetype.title) has to be bought from the App Store first.")
                return
            }
            equipArchetype(archetype)
        }
    }

    /// Does the user own this real-money tier? Wired to StoreKit at app root;
    /// defaults to "no" so a missing wiring fails closed (no free badges).
    var ownsArchetype: (Archetype) -> Bool = { $0.productID == nil }

    /// Put a badge on the profile. Called directly for free/Gavel tiers, and
    /// from the StoreKit grant hook once a real-money tier is paid for.
    func equipArchetype(_ archetype: Archetype) {
        guard role == .man else { return }
        let before = me.auctionCredit
        me.archetype = archetype
        // Trillionaire is earned: buying only unlocks the *attempt*. Verification
        // resets and must be re-won on a confirmed $9,999 date.
        me.trillionaireVerified = false
        Haptics.success()
        if archetype == .trillionaire {
            toastFlash("Trillionaire pending — pay $\(Archetype.trillionaireDateGateUSD.formatted()) on a date and get confirmed to verify.")
        } else {
            toastFlash(archetype == .none ? "Rating removed." : "You're now a \(archetype.title).")
        }
        creditPing(before: before)
        save()
        onProfileChanged?(me)
    }

    /// A status purchase was refunded. Drop the badge to the best rating the
    /// user still holds so a refunded Ferrari doesn't keep flexing.
    /// `stillOwned` is asked of StoreKit (wired at app root).
    func revokeArchetype(_ archetype: Archetype, stillOwned: (Archetype) -> Bool) {
        guard me.archetype == archetype else { return }   // already moved on
        let fallback = Archetype.allCases
            .filter { $0 != archetype && $0.rawValue < archetype.rawValue }
            .last { tier in
                switch tier.purchase {
                case .free: return true
                case .money: return stillOwned(tier)
                }
            } ?? .none
        let before = me.auctionCredit
        me.archetype = fallback
        me.trillionaireVerified = false
        toastFlash("\(archetype.title) refunded — badge dropped to \(fallback.title).")
        log(.admin, "\(archetype.title) refunded; status reset to \(fallback.title).")
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
        await syncWebGavels(backend: backend)
        await refreshReservations(backend: backend)
    }

    // MARK: - Remote floor (slice 4b1a)

    /// Pull the real signed-in floor from the auth Worker. Called from
    /// `AuctionFeedView.task` on appear and on foreground. Demo Mode and
    /// unsigned-in users are silent no-ops — they keep seeing the sim.
    ///
    /// The flip to `isRemoteFloor = true` happens only when the fetch
    /// returned at least one real profile, so a signed-in user on a fresh
    /// platform (nobody else has joined yet) still sees the sim rather than
    /// a blank screen. As soon as ONE other real user exists, they take over.
    func refreshRemoteFloor(profileSync: ProfileService) async {
        guard !demoMode, profileSync.isEnabled, let role else { return }
        // A bidder browses women; a lot's own "floor" isn't a fetch surface
        // (she reads her incoming inbox, wired in later slices).
        let feedRole: Role = role == .man ? .woman : .man
        let result = await profileSync.fetchFloor(role: feedRole, limit: 60)
        guard case .success(let page) = result else { return }
        let converted = page.profiles.map(Profile.init(from:))
        remoteFloor = converted
        isRemoteFloor = !converted.isEmpty
    }

    // MARK: - Remote inbox (slice 4b1b)

    /// Pull the woman's real inbox (`GET /bids/incoming`) from the matching
    /// Worker. Called from `IncomingBidsView.task` on appear, on foreground,
    /// and when a `bid.received` push wakes the app.
    ///
    /// Demo Mode + local-only sessions are silent no-ops (they keep their
    /// seeded sim bids). For a signed-in woman: the fetch always flips
    /// `isRemoteInbox = true` — an empty real inbox is legitimate ("no bids
    /// yet"), and we don't want stale sim bids leaking into it.
    func refreshRemoteInbox(matching: MatchingService) async {
        guard !demoMode, matching.isEnabled, role == .woman else { return }
        let result = await matching.refreshIncoming()
        guard case .success(let list) = result else { return }
        // Direction is `.inbox` here — I'm the lot, peers are the bidders.
        remoteIncomingBids = list.map { Bid(from: $0, mine: me, direction: .inbox) }
        isRemoteInbox = true
    }

    /// Route accept through the matching Worker when the row is remote (came
    /// from `remoteIncomingBids`). Falls through to the sim `accept(_:)` for
    /// local rows so Demo Mode + backward compat still work.
    func acceptRemote(_ bid: Bid, matching: MatchingService) async {
        guard isRemoteInbox else { accept(bid); return }
        // Optimistic UI: drop from the visible inbox immediately.
        remoteIncomingBids.removeAll { $0.id == bid.id }
        Haptics.commit()
        _ = await matching.accept(bidId: bid.id.uuidString.lowercased())
        // TODO(4b1c/4b1d): pull the resulting match into `matches` here.
    }

    func declineRemote(_ bid: Bid, matching: MatchingService) async {
        guard isRemoteInbox else { decline(bid); return }
        remoteIncomingBids.removeAll { $0.id == bid.id }
        Haptics.tap()
        _ = await matching.decline(bidId: bid.id.uuidString.lowercased())
    }

    // MARK: - Remote bid write (slice 4b1c)

    /// Place a real bid on a signed-in woman via the matching Worker.
    /// Falls through to the sim `placeBid` when the target isn't a remote
    /// profile (Demo Mode, local-only, or a summoned/lot-of-the-day figure).
    ///
    /// **Gavel accounting rolls back on server failure.** Gild + Bid Insurance
    /// still cost Gavels locally (real money via IAP), and we deduct them
    /// BEFORE the network call so a user can see the intent lock in. If the
    /// Worker rejects the bid — network failure, invalid target, rate-limit
    /// once we add one — we refund the debit and toast the error. The bid
    /// itself never moves money in either direction.
    func placeRemoteBid(on woman: Profile, amount: Int, note: String,
                        gilded: Bool = false, insured: Bool = false,
                        promptRef: String? = nil,
                        matching: MatchingService) async {
        guard role == .man, amount > 0 else { return }

        // Match the sim path's Gavel debits — real users never copycat, so
        // we don't need the sim's copycat-skip guard here.
        var didGild = false
        var didInsure = false
        if gilded {
            if wallet >= Self.gildedBidCost { wallet -= Self.gildedBidCost; didGild = true }
            else { toastFlash("Not enough Gavels to gild — sent a standard bid.") }
        }
        if insured {
            if wallet >= Self.bidInsuranceCost { wallet -= Self.bidInsuranceCost; didInsure = true }
        }

        let lotId = woman.id.uuidString.lowercased()
        let result = await matching.placeBid(
            lotId: lotId, amount: amount, note: note,
            gilded: didGild, insured: didInsure, isWhisper: false,
            promptRef: promptRef,
        )
        switch result {
        case .success(let remoteBid):
            // Optimistic entry into the outbox so MyBidsView shows it right
            // away without a round-trip. The full outbox refresh will land it
            // with the peer snapshot once slice 4b1d wires that up.
            let bid = Bid(from: remoteBid, mine: me, direction: .outbox)
            remoteOutgoingBids.insert(bid, at: 0)
            isRemoteOutgoing = true
            Haptics.commit()
            toastFlash(didGild ? "✦ Gilded Bid sent to \(woman.name) — top of her inbox."
                               : "Bid sent to \(woman.name). She'll get a notification.")
            save()
        case .failure(let message):
            // Roll back the Gavel debits — the bid didn't reach the server.
            if didGild { wallet += Self.gildedBidCost }
            if didInsure { wallet += Self.bidInsuranceCost }
            Haptics.warning()
            toastFlash(message)
            save()
        case .notConfigured:
            // Shouldn't happen — BidSheet only routes here when remote mode
            // is active. Refund defensively so a race can't strand Gavels.
            if didGild { wallet += Self.gildedBidCost }
            if didInsure { wallet += Self.bidInsuranceCost }
            save()
        }
    }

    // MARK: - Web Gavel shop sync (Stripe consumables Worker)

    /// Gavels bought on the web shop (Stripe Checkout) land in a KV balance
    /// keyed by `appAccountToken`. This drains that balance into the local
    /// wallet: fetch → /consume (idempotent) → credit.
    ///
    /// Crash-safety follows the StoreKit house rule — overpay, never
    /// under-credit: the pending drain (idempotency key + amount) persists in
    /// UserDefaults before the network call, and is only cleared AFTER the
    /// wallet credit is saved. A crash in between re-runs the drain; the
    /// Worker replies `replay` without double-spending the web balance.
    private static let pendingDrainKey = "auctionbaby.webgavels.pendingdrain.v1"

    /// Re-entrancy guard: launch (.task) and foreground (.onChange scenePhase)
    /// both fire refreshPendingRefunds almost simultaneously on cold start.
    /// @MainActor doesn't exclude across await suspension points, so without
    /// this flag two overlapping syncs each fetch the same web balance, write
    /// DIFFERENT idempotency keys, and both drains succeed — double credit.
    private var webGavelSyncInFlight = false

    func syncWebGavels(backend: BackendService) async {
        guard backend.isConsumablesConfigured else { return }
        guard !webGavelSyncInFlight else { return }
        webGavelSyncInFlight = true
        defer { webGavelSyncInFlight = false }

        // 1. Finish any drain that was interrupted mid-flight.
        if let pending = UserDefaults.standard.dictionary(forKey: Self.pendingDrainKey),
           let key = pending["key"] as? String, let amount = pending["amount"] as? Int {
            await completeDrain(backend: backend, key: key, amount: amount)
            return   // one drain per foreground pass keeps the flow simple
        }

        // 2. Fresh pass: anything waiting on the web balance?
        guard case .success(let balance) = await backend.fetchWebGavels(appAccountToken: appAccountToken),
              balance > 0 else { return }

        let key = "drain-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(["key": key, "amount": balance], forKey: Self.pendingDrainKey)
        await completeDrain(backend: backend, key: key, amount: balance)
    }

    private func completeDrain(backend: BackendService, key: String, amount: Int) async {
        switch await backend.drainWebGavels(appAccountToken: appAccountToken,
                                            gavels: amount, idempotencyKey: key) {
        case .success(let drained):
            wallet += drained
            save()   // credit first…
            UserDefaults.standard.removeObject(forKey: Self.pendingDrainKey)  // …then clear
            Haptics.success()
            toastFlash("Web shop synced — +\(Tally.compact(drained)) Gavels.")
            log(.daily, "Synced \(Tally.compact(drained)) Gavels from the web shop.")
            ErrorMonitor.shared.record(category: "Backend",
                                       message: "Web Gavel drain: +\(drained)",
                                       detail: "key \(key)")
        case .failure(let message):
            // Leave the pending record in place — the next foreground retries
            // with the same idempotency key. 402 (insufficient) means a refund
            // raced the drain; clear so the next pass re-reads the balance.
            if message.contains("insufficient") {
                UserDefaults.standard.removeObject(forKey: Self.pendingDrainKey)
            }
            ErrorMonitor.shared.record(category: "Backend",
                                       message: "Web Gavel drain failed", detail: message)
        }
    }

    // MARK: - Reserve the date (Stripe booking fee)

    /// Mark a date booked locally. The ONLY thing reserving changes is this
    /// real-world confirmation flag — it deliberately unlocks no in-app content
    /// (Apple: a real-world service fee must not gate digital features). Called
    /// by the demo path and after the Worker confirms a completed web checkout.
    func markDateReserved(_ matchID: UUID, amountCents: Int? = nil) {
        guard let idx = matches.firstIndex(where: { $0.id == matchID }),
              !matches[idx].dateReserved else { return }
        matches[idx].dateReserved = true
        matches[idx].reservedAmountCents = amountCents
        Haptics.success()
        toastFlash("Date reserved — you're locked in. Pay her in person as agreed.")
        log(.bidAccepted, "You reserved your date with \(matches[idx].bid.woman.name).")
        save()
    }

    /// Demo/App-Review convenience: reserve with no real charge, so a reviewer
    /// can see the booked state (and the "Reserved · $X" label) without a live
    /// Stripe account.
    func reserveDateDemo(_ matchID: UUID, amountCents: Int? = nil) {
        guard demoMode else { return }
        markDateReserved(matchID, amountCents: amountCents)
    }

    /// On foreground, reflect any booking fees paid on the web since we last
    /// looked. Only checks the bidder's own un-reserved live matches.
    func refreshReservations(backend: BackendService) async {
        guard role == .man, backend.isConsumablesConfigured else { return }
        let pending = matches.filter { $0.phase == .chatting && !$0.dateReserved }
        for match in pending {
            if case .success(let state) = await backend.reservationStatus(matchID: match.id),
               state.reserved {
                markDateReserved(match.id, amountCents: state.amountCents)
            }
        }
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
    /// resets it — unless the user holds a streak-freeze token, in which case
    /// one token is spent per missed day and the streak survives.
    ///
    /// The Docket variable-reward layer: 20% chance the base reward is
    /// replaced by a mystery bonus (a Gilded Bid credit, a bonus streak-freeze
    /// token, or an extra Gavel windfall). Deterministic-per-day so the same
    /// claim isn't reroll-able within a session.
    func claimDaily(now: Date = .now) {
        guard canClaimDaily(now: now) else { return }
        let missed = missedDays(from: lastDailyClaim, to: now)
        if missed == 0 {
            dailyStreak += 1
        } else if missed <= streakFreezeCount {
            // Spend one freeze per missed day; streak survives, grows by 1.
            streakFreezeCount -= missed
            dailyStreak += 1
            toastFlash("Streak-freeze spent — day \(dailyStreak) preserved.")
        } else {
            dailyStreak = 1
        }
        lastDailyClaim = now
        let reward = Self.dailyGavelBase * min(dailyStreak, 7)

        // Mystery box roll — deterministic on the day so it can't be rerolled.
        let dayKey = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        let mysteryRoll = (dayKey &+ Int(appAccountToken.uuidString.hashValue & 0x3FF)) % 5
        switch mysteryRoll {
        case 0:  // Gilded Bid credit (worth gildedBidCost Gavels)
            wallet += reward + Self.gildedBidCost
            toastFlash("Docket mystery — +\(Tally.compact(reward + Self.gildedBidCost)) Gavels (Gilded credit).")
        case 1:  // Streak-freeze token
            wallet += reward
            streakFreezeCount += 1
            toastFlash("Docket mystery — streak-freeze added to your inventory.")
        default: // Standard reward
            wallet += reward
            toastFlash("Day \(dailyStreak) streak — +\(Tally.compact(reward)) Gavels.")
        }
        Haptics.success()
        log(.daily, "Claimed your day-\(dailyStreak) streak: \(Tally.compact(reward)) Gavels.")
        save()
    }

    /// Days elapsed between `last` and `now` that weren't the "next day". 0 if
    /// today is the day after last; N otherwise.
    private func missedDays(from last: Date?, to now: Date) -> Int {
        guard let last else { return 0 }
        let cal = Calendar.current
        let lastDay = cal.startOfDay(for: last)
        let today = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return max(0, days - 1)
    }

    /// Buy an extra streak-freeze token from the Docket for a Gavel amount.
    /// Used by the DailyClaimCard's "Get another" action.
    static let streakFreezeGavelCost = 500
    func buyStreakFreeze() {
        guard wallet >= Self.streakFreezeGavelCost else {
            toastFlash("Not enough Gavels for a streak-freeze."); return
        }
        wallet -= Self.streakFreezeGavelCost
        streakFreezeCount += 1
        Haptics.success()
        toastFlash("Streak-freeze added — miss a day, streak survives.")
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

    /// Save the woman's Opening Bid Script. Passing nil clears it.
    func updateOpeningBidScript(_ script: String?) {
        me.openingBidScript = script
        save()
        onProfileChanged?(me)
        toastFlash(script == nil ? "Opener cleared." : "Opener saved.")
    }

    func setStartingBid(_ value: Int?) {
        guard role == .woman else { return }
        me.startingBid = value.map { max(0, min($0, Self.maxStartingBid)) }
        save()
        onProfileChanged?(me)
    }

    func accept(_ bid: Bid) {
        guard let idx = incomingBids.firstIndex(where: { $0.id == bid.id }),
              incomingBids[idx].status == .pending else { return }   // idempotent: no double-credit
        // A whisper has no amount to accept — it resolves via nodAtWhisper.
        guard !incomingBids[idx].isWhisper else { nodAtWhisper(bid); return }
        incomingBids[idx].status = .accepted
        let accepted = incomingBids[idx]
        earnings += accepted.amount

        // The woman always sends the first invite (per the brief). Opening Bid
        // Script (if she set one) takes precedence over the canned line.
        var match = Match(bid: accepted, phase: .chatting)
        let opener: String
        if let scripted = me.openingBidScript,
           !scripted.trimmingCharacters(in: .whitespaces).isEmpty {
            opener = scripted
        } else {
            opener = "You're in. \(accepted.man.name) — let's set a date. 🍸"
        }
        match.messages = [
            ChatMessage(fromMe: true, text: opener, isSystem: false),
        ]
        // 24h freshness clock (Bumble-style), cleared by the next activity —
        // the sim suitor's reply or her next message. See
        // testAcceptedMatchStartsWithA24HourClockAndCorrectSender.
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

    /// Nod back at a whisper. Never a match (there's no bid to accept) — the
    /// nod invites the whisperer to come back with a real number, which the
    /// simulation delivers a few seconds later.
    func nodAtWhisper(_ bid: Bid) {
        guard role == .woman,
              let idx = incomingBids.firstIndex(where: { $0.id == bid.id }),
              incomingBids[idx].status == .pending, incomingBids[idx].isWhisper else { return }
        incomingBids[idx].status = .accepted
        pendingNodManIDs.insert(bid.man.id)   // persisted; re-armed in load()
        Haptics.tap()
        toastFlash("You nodded back — watch for his real bid.")
        save()
        scheduleNodFollowUp(man: bid.man)
    }

    /// The whisperer's follow-up real bid, 2–4s after the nod. Split out so
    /// load() can re-arm nods that were interrupted by a kill.
    private func scheduleNodFollowUp(man: Profile) {
        after(Double.random(in: 2.0...4.0)) { [weak self] in
            guard let self else { return }
            guard self.pendingNodManIDs.contains(man.id) else { return }   // already delivered
            self.pendingNodManIDs.remove(man.id)
            guard !self.blockedIDs.contains(man.id) else { self.save(); return }
            let floor = min(self.me.startingBid ?? 150, Self.maxStartingBid)
            let amount = max(120, Int(Double(floor) * Double.random(in: 1.0...2.0)))
            let real = Bid(man: man, woman: self.me, amount: amount,
                           note: "You nodded. I don't waste a second chance — here's my number.")
            self.incomingBids.insert(real, at: 0)
            Haptics.commit()
            self.toastFlash("\(man.name) came back with \(Money.compact(amount)).")
            self.log(.bidReceived, "\(man.name) followed his whisper with \(Money.compact(amount)).")
            self.save()
        }
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
            // The first verified Trillionaire himself comes to bid. If he's
            // been blocked/removed there is no impostor fallback — a $1M bid
            // from a non-Trillionaire can never mint (qualifiesForMasterpiece
            // checks the archetype), so the copy would over-promise.
            guard let trillionaireMan = pool.first(where: { $0.archetype == .trillionaire }) else {
                toastFlash("The Trillionaire isn't on your floor right now.")
                return
            }
            man = trillionaireMan
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
        // Store-level expiry guard — the composer lock in ChatView is view-only.
        guard !matches[idx].isExpired else { return }
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

    /// Undo your most recent live bid — a Reserve / Black Card Pass perk. Only
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
                       categories: [String], text: String, actuallySpent: Int,
                       confirmedMet: Bool = true) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }),
              !matches[idx].manReviewedWoman else { return }   // one review per date
        matches[idx].manConfirmedMet = confirmedMet
        // Sim woman corroborates when he confirmed — that's what makes the
        // signal Gavel Confirmed. If he says they didn't meet, no corroboration.
        if confirmedMet { matches[idx].womanConfirmedMet = true }
        let bid = matches[idx].bid

        let creditBefore = me.auctionCredit
        // NOTE: no in-app debit here. A bid is a letter of intent — the date
        // money is settled in the real world, peer-to-peer. `actuallySpent` is
        // only what he reports paying in person, which she confirms or disputes;
        // it drives his deadbeat score and Trillionaire verification, nothing more.

        // His review of her — stored on the match and reflected on the floor.
        var traitDict: [String: Int] = [:]
        for (t, v) in traits { traitDict[t.rawValue] = v }
        var review = DateReview(authorName: me.name, authorHue: me.hue, stars: stars, text: text,
                                traits: traitDict, interestCategories: categories)
        review.gavelConfirmed = matches[idx].gavelConfirmed
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
        var wReview = DateReview(authorName: bid.woman.name, authorHue: bid.woman.hue,
                                  stars: verdict.stars, text: verdict.text,
                                  paidBid: paid, bidAmount: bid.amount, spentAmount: actuallySpent)
        wReview.gavelConfirmed = matches[idx].gavelConfirmed
        me.reviews.insert(wReview, at: 0)

        // Trillionaire is earned here: he bought the badge, bid & paid the full
        // $9,999, and the woman (sim) confirmed it. That's the third gate.
        if me.archetype == .trillionaire && !me.trillionaireVerified
            && bid.amount >= Archetype.trillionaireDateGateUSD
            && actuallySpent >= Archetype.trillionaireDateGateUSD && paid {
            me.trillionaireVerified = true
            closeMatch(idx)
            Haptics.success()
            toastFlash("✦ TRILLIONAIRE VERIFIED — she confirmed your $9,999.")
            log(.trillionaire, "You're a verified Trillionaire — \(bid.woman.name) confirmed your $9,999.")
            save()
            return
        }

        let confirmed = matches[idx].gavelConfirmed
        closeMatch(idx)
        Haptics.success()
        if confirmed {
            toastFlash(paid ? "✓ Gavel Confirmed. Your credit just moved."
                            : "✓ Gavel Confirmed — but paying short still dented your credit.")
        } else {
            toastFlash("Review posted (self-reported). Full weight when both sides confirm.")
        }
        log(.reviewReceived, "\(bid.woman.name) reviewed your date.")
        creditPing(before: creditBefore)
        save()
    }

    /// Woman reviews the man after the date (the woman-user path). Records the
    /// deadbeat verdict; a paid Trillionaire mints her Masterpiece.
    func completeAsWoman(_ match: Match, paid: Bool, stars: Int, text: String,
                         confirmedMet: Bool = true) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }),
              !matches[idx].womanReviewedMan else { return }   // one review per date
        matches[idx].womanConfirmedMet = confirmedMet
        // Sim man corroborates when she confirmed the meetup.
        if confirmedMet { matches[idx].manConfirmedMet = true }
        let bid = matches[idx].bid

        // Her verdict on him — stored on the match. The woman's stars and text
        // feed into the man's record (cosmetic — he isn't the user).
        matches[idx].womanReviewedMan = true
        if let manIdx = bidders.firstIndex(where: { $0.id == bid.man.id }) {
            var mReview = DateReview(authorName: me.name, authorHue: me.hue, stars: stars, text: text,
                                     paidBid: paid, bidAmount: bid.amount)
            mReview.gavelConfirmed = matches[idx].gavelConfirmed
            bidders[manIdx].reviews.insert(mReview, at: 0)
        }

        let showcaseBefore = me.showcaseCredit
        let tierBefore = me.artTier
        // His simulated review of her → grows *her* Showcase score. Only mint it
        // when the date actually happened: if she flagged a no-show, there's no
        // meetup to review, so a corroborating 5★ of her would be dishonest.
        if confirmedMet {
            var traits: [String: Int] = [:]
            for t in Trait.allCases { traits[t.rawValue] = Int.random(in: 4...5) }
            var meRev = DateReview(authorName: bid.man.name, authorHue: bid.man.hue,
                                    stars: Int.random(in: 4...5),
                                    text: "Effortless company. Worth the bid.",
                                    traits: traits,
                                    interestCategories: Array(me.interests.prefix(2)))
            meRev.gavelConfirmed = matches[idx].gavelConfirmed
            me.reviews.insert(meRev, at: 0)
        }

        // Deadbeat: claw back earnings credited at acceptance.
        if !paid { earnings = max(0, earnings - bid.amount) }
        if bid.qualifiesForMasterpiece && paid {
            me.masterpiece = true
            // Her confirmation is also what verifies his Trillionaire status —
            // on the match snapshot AND the live roster, or he'd read
            // "Pending" everywhere else he appears.
            matches[idx].bid.man.trillionaireVerified = true
            if let rosterIdx = bidders.firstIndex(where: { $0.id == bid.man.id }) {
                bidders[rosterIdx].trillionaireVerified = true
            }
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

    /// A woman's automated decision on a bidder's offer. Whispers resolve on a
    /// lighter cadence than real bids (a nod is a smaller decision than money).
    /// Copycats never reach here — they're resolved at bid time in placeBid.
    private func scheduleWomanDecision(bidID: UUID) {
        let pending = outgoingBids.first(where: { $0.id == bidID })
        // Copycats are fully resolved in placeBid (reveal + credit hit, no match),
        // so a copycat bid must never reach the decision simulation.
        guard !(pending?.onCopycat ?? false) else { return }
        let whisper = pending?.isWhisper ?? false
        let delay = whisper ? Double.random(in: 1.5...2.5) : Double.random(in: 2.5...4.2)
        after(delay) { [weak self] in
            guard let self, let idx = self.outgoingBids.firstIndex(where: { $0.id == bidID }) else { return }
            guard self.outgoingBids[idx].status == .pending else { return }
            var bid = self.outgoingBids[idx]

            // Whispers resolve softly: she either nods back (inviting a real
            // bid) or lets it fade. Never a credit event, never a match, never
            // an auto-rebid — that's the whole point of a zero-stakes signal.
            if bid.isWhisper {
                let nodded = Double.random(in: 0...1) < 0.7
                bid.status = nodded ? .accepted : .declined
                self.outgoingBids[idx] = bid
                if nodded {
                    Haptics.tap()
                    self.toastFlash("\(bid.woman.name) noticed your whisper — she's waiting for a real bid.")
                    self.log(.bidReceived, "\(bid.woman.name) nodded at your whisper. Your move.")
                }
                self.save()
                return
            }

            let threshold = bid.woman.startingBid ?? max(100, bid.woman.marketValue / 2)
            // Money + reputation both move the needle.
            let ratio = Double(bid.amount) / Double(threshold)
            let creditPull = Double(self.me.auctionCredit - 600) / 300.0
            let boostPull = self.isBoosted ? 0.25 : 0
            let gildPull = bid.gilded ? 0.30 : 0
            let priorityPull = self.priorityPlacementEnabled ? 0.20 : 0
            let accepted = (ratio + creditPull + boostPull + gildPull + priorityPull + Double.random(in: -0.25...0.25)) >= 1.0

            bid.status = accepted ? .accepted : .declined
            self.outgoingBids[idx] = bid

            if accepted {
                var match = Match(bid: bid, phase: .chatting)
                // Opening Bid Script: the woman's authored opener when she set one.
                let opener: String
                if let scripted = bid.woman.openingBidScript,
                   !scripted.trimmingCharacters(in: .whitespaces).isEmpty {
                    opener = scripted
                } else {
                    opener = "Okay, you win. \(bid.woman.name) here — where are you taking me?"
                }
                match.messages = [ChatMessage(fromMe: false, text: opener)]
                match.expiresAt = Date().addingTimeInterval(24 * 3600)
                self.matches.insert(match, at: 0)
                Haptics.success()
                self.toastFlash("\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid!")
                self.celebrate(with: bid.woman, amount: bid.amount,
                               copycat: false, masterpiece: bid.qualifiesForMasterpiece)
                self.log(.bidAccepted, "\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid.")
            } else {
                let before = self.me.auctionCredit
                self.me.declinedBids += 1
                // Bid Insurance payout: the premium comes back, and the gild
                // fee too when the bid was actually gilded. Payout can never
                // exceed what the bid cost — an unconditional Gilded credit
                // here was a farmable +250/decline money printer.
                if bid.insured {
                    let refund = Self.bidInsuranceCost + (bid.gilded ? Self.gildedBidCost : 0)
                    self.wallet += refund
                    self.toastFlash(bid.gilded
                        ? "Bid Insurance paid — premium + gild fee back."
                        : "Bid Insurance paid — premium back.")
                }
                // Cap the chain at 3 rounds: it converges naturally (each
                // round raises the accept ratio 1.2×) but an explicit ceiling
                // guarantees termination and bounds the amount growth.
                if self.autoRebidEnabled && !bid.onCopycat && bid.rebidDepth < 3 {
                    let raised = min(Int(Double(bid.amount) * 1.2), Self.maxStartingBid)
                    var rebid = Bid(man: self.me, woman: bid.woman, amount: raised, note: bid.note)
                    // The auto-rebid is a courtesy re-bid — it must NOT inherit the
                    // gild. Carrying gilded=true for free let a Pass user farm
                    // Gavels: the free gild was refunded once by insurance on
                    // decline AND a second time by rewindLastBid (which credits off
                    // the flag). A plain rebid closes that and the free +gildPull.
                    rebid.rebidDepth = bid.rebidDepth + 1
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
            let line = ["Thursday works for me — I know a place.", "Looking forward to this, honestly.",
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
            let lines = ["Looking forward to it.", "Okay tell me your worst date story — I'll trade you mine.",
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
        var whisper = Bid(man: suitors[1], woman: me, amount: 0, note: "")
        whisper.isWhisper = true
        incomingBids = [
            Bid(man: suitors[0], woman: me, amount: max(300, base &* 2),
                note: "Saw your prompts. Dinner at Carbone? My treat."),
            Bid(man: suitors[3], woman: me, amount: max(120, base),
                note: "I'll lose at trivia and pay anyway."),
            whisper,
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
        var lastLotOfDaySeen: Date?
        var streakFreezeCount: Int?
        /// Write timestamp — load() picks whichever store (archive vs
        /// UserDefaults) carries the newer snapshot, so a silently-failed
        /// archive write can't permanently shadow fresher UD data.
        var savedAt: Date?
        /// Pending whisper nods whose follow-up real bid hasn't landed yet
        /// (man ids). Re-armed in load() so a kill inside the 2–4s window
        /// doesn't lose the promised bid.
        var pendingNodManIDs: [UUID]?
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
                            appAccountToken: appAccountToken, demoMode: demoMode,
                            lastLotOfDaySeen: lastLotOfDaySeen,
                            streakFreezeCount: streakFreezeCount,
                            savedAt: Date(),
                            pendingNodManIDs: Array(pendingNodManIDs))
        if let data = try? JSONEncoder().encode(snap) {
            store.set(data, forKey: Self.key)
        }
        encryptedArchive.save(snap)
    }

    private func load() {
        // Decode BOTH stores and keep the newer one (savedAt; missing = old),
        // so a silently-failed archive write can't shadow fresher UD data.
        let archiveSnap = encryptedArchive.load(Snapshot.self)
        let udData = store.data(forKey: Self.key)
        let udSnap = udData.flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let snap: Snapshot?
        switch (archiveSnap, udSnap) {
        case (let a?, let u?):
            snap = (a.savedAt ?? .distantPast) >= (u.savedAt ?? .distantPast) ? a : u
        case (let a?, nil): snap = a
        case (nil, let u?): snap = u
        case (nil, nil): snap = nil
        }
        // Data exists but nothing decoded: stash the raw bytes under a rescue
        // key (once) before the next save() overwrites them, so a hotfix
        // build can still recover the account + its appAccountToken.
        if snap == nil, let udData,
           store.data(forKey: Self.key + ".rescue") == nil {
            store.set(udData, forKey: Self.key + ".rescue")
            ErrorMonitor.shared.record(category: "Persistence",
                                       message: "Snapshot decode failed — raw bytes stashed to .rescue")
        }
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
        lastLotOfDaySeen = snap.lastLotOfDaySeen
        streakFreezeCount = snap.streakFreezeCount ?? 0
        pendingNodManIDs = Set(snap.pendingNodManIDs ?? [])
        if isBoosted, role == .woman { startBoostSummons() }
        for bid in outgoingBids where bid.status == .pending {
            scheduleWomanDecision(bidID: bid.id)
        }
        // Re-arm whisper follow-ups interrupted by a kill.
        for manID in pendingNodManIDs {
            if let man = bidders.first(where: { $0.id == manID }) {
                scheduleNodFollowUp(man: man)
            } else {
                pendingNodManIDs.remove(manID)
            }
        }
    }
}
