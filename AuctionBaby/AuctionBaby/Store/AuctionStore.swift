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

    @Published var floor: [Profile] = []        // women a bidder browses
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

    private let store = UserDefaults.standard
    private static let key = "auctionbaby.state.v5"

    // MARK: - Lifecycle

    init() { load() }

    static func blankProfile(_ role: Role) -> Profile {
        Profile(name: "", age: 25, role: role, location: "", bio: "", hue: 0.6)
    }

    // MARK: - Onboarding

    func register(role: Role, name: String, age: Int, location: String, bio: String,
                  hue: Double, startingBid: Int?, prompts: [Prompt], interests: [String]) {
        var profile = Profile(name: name.isEmpty ? "You" : name, age: age, role: role,
                              location: location, bio: bio, hue: hue,
                              prompts: prompts, interests: interests)
        if role == .woman { profile.startingBid = startingBid }
        self.me = profile
        self.role = role
        self.floor = SampleData.floor()

        if role == .woman {
            // Seed a couple of incoming bids so the inbox isn't empty.
            seedIncomingBids()
        }
        Haptics.success()
        toastFlash(role == .woman ? "Your lot is live on the floor." : "You're on the floor. Start bidding.")
        save()
    }

    /// Wipe everything and return to onboarding (Settings → Reset).
    func resetAccount() {
        role = nil
        me = AuctionStore.blankProfile(.man)
        wallet = 750
        earnings = 0
        floor = []
        incomingBids = []
        outgoingBids = []
        matches = []
        boostUntil = nil
        filters = FilterPreferences()
        blockedIDs = []
        activity = []
        store.removeObject(forKey: Self.key)
    }

    // MARK: - Bidder (man) actions

    /// Place a bid on a woman. Bids are offers — nothing is charged until a date
    /// actually happens — but bidding on an AI copycat is logged against the
    /// bidder's reputation immediately.
    func placeBid(on woman: Profile, amount: Int, note: String, gilded: Bool = false,
                  promptRef: String? = nil) {
        guard role == .man else { return }
        // Gilding spends Gavels up front; fall back to a normal bid if short.
        var gild = gilded
        if gild {
            if wallet >= Self.gildedBidCost { wallet -= Self.gildedBidCost }
            else { gild = false; toastFlash("Not enough Gavels to gild — sent a standard bid.") }
        }
        var bid = Bid(man: me, woman: woman, amount: amount, note: note)
        bid.gilded = gild
        bid.promptRef = promptRef
        outgoingBids.insert(bid, at: 0)

        if woman.isCopycat {
            me.copycatBids += 1
            Haptics.warning()
            toastFlash("Heads up: that was a Copycat. −\(22) Auction Credit.")
        } else {
            Haptics.commit()
            toastFlash(gild ? "✦ Gilded bid sent to \(woman.name) — top of her inbox."
                            : "Bid placed: \(Money.compact(amount)) on \(woman.name).")
        }
        save()
        scheduleWomanDecision(bidID: bid.id)
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

    /// Whether a Spotlight Boost is currently live.
    var isBoosted: Bool { (boostUntil ?? .distantPast) > .now }

    /// Activate a 30-minute Spotlight Boost (called from a verified purchase).
    func activateBoost() {
        boostUntil = Date().addingTimeInterval(Double(StoreKitService.boostMinutes) * 60)
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

    /// Demo-only top-up so the higher tiers are explorable without a sandbox
    /// purchase. Clearly labelled as demo in the UI; never charges anything.
    func addDemoGavels(_ amount: Int = 10_000) {
        wallet += amount
        Haptics.tap()
        toastFlash("Demo: added \(Tally.compact(amount)) Gavels (no charge).")
        save()
    }

    // MARK: - Lot (woman) actions

    func setStartingBid(_ value: Int?) {
        guard role == .woman else { return }
        me.startingBid = value
        save()
    }

    func accept(_ bid: Bid) {
        guard let idx = incomingBids.firstIndex(where: { $0.id == bid.id }) else { return }
        incomingBids[idx].status = .accepted
        let accepted = incomingBids[idx]
        earnings += accepted.amount

        // The woman always sends the first invite (per the brief).
        var match = Match(bid: accepted, phase: .chatting)
        match.messages = [
            ChatMessage(fromMe: false, text: "You're in. \(accepted.man.name) — let's set a date. 🍸", isSystem: false),
        ]
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
        me.verified = true
        Haptics.success()
        toastFlash("You're verified ✓ — bidders trust a real face.")
        log(.verified, "You're now identity verified.")
        save()
    }

    func decline(_ bid: Bid) {
        guard let idx = incomingBids.firstIndex(where: { $0.id == bid.id }) else { return }
        incomingBids[idx].status = .declined
        Haptics.tap()
        save()
    }

    /// Demo helper — summon a fresh bidder to the inbox. `trillionaire: true`
    /// guarantees a $1M Masterpiece-eligible bid so that flow is reachable.
    func summonBidder(trillionaire: Bool = false) {
        guard role == .woman else { return }
        let pool = SampleData.suitors()
        var man = pool.randomElement() ?? pool[0]
        let amount: Int
        if trillionaire {
            // The first verified Trillionaire himself comes to bid.
            man = pool.first { $0.archetype == .trillionaire } ?? pool[0]
            amount = Archetype.trillionaire.price   // $9,999 — the Masterpiece-minting bid
        } else {
            let floor = me.startingBid ?? 150
            amount = Int(Double(floor) * Double.random(in: 0.7...2.4))
        }
        let note = trillionaire
            ? "I read the rules — I wrote them. The full $9,999 for one evening. Confirm it and mint your Masterpiece."
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
        save()
        scheduleSeen(matchID: match.id)
        scheduleCounterpartReply(matchID: match.id)
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
        guard let idx = matches.firstIndex(where: { $0.id == match.id }) else { return }
        let bid = matches[idx].bid

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
            // She only mints a Masterpiece if he actually paid the full $9,999.
            if bid.qualifiesForMasterpiece && paid { floor[f].masterpiece = true }
        }
        matches[idx].manReviewedWoman = true
        me.reviews.insert(
            DateReview(authorName: bid.woman.name, authorHue: bid.woman.hue,
                       stars: paid ? Int.random(in: 4...5) : Int.random(in: 1...2),
                       text: paid ? "Bid \(Money.compact(bid.amount)) and paid it. A gentleman."
                                  : "Bid \(Money.compact(bid.amount)), paid \(Money.compact(actuallySpent)). Deadbeat.",
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
        save()
    }

    /// Woman reviews the man after the date (the woman-user path). Records the
    /// deadbeat verdict; a paid Trillionaire mints her Masterpiece.
    func completeAsWoman(_ match: Match, paid: Bool, stars: Int, text: String) {
        guard let idx = matches.firstIndex(where: { $0.id == match.id }) else { return }
        let bid = matches[idx].bid

        // Her verdict on him (cosmetic — he isn't the user).
        matches[idx].womanReviewedMan = true

        // His review of her → grows *her* Showcase score with simulated traits.
        var traits: [String: Int] = [:]
        for t in Trait.allCases { traits[t.rawValue] = Int.random(in: 4...5) }
        me.reviews.insert(
            DateReview(authorName: bid.man.name, authorHue: bid.man.hue, stars: Int.random(in: 4...5),
                       text: "Effortless company. Worth the bid.", traits: traits,
                       interestCategories: Array(me.interests.prefix(2))),
            at: 0)

        // Earnings were credited at acceptance in this demo, so nothing to add here.
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
        closeMatch(idx)
        save()
    }

    private func closeMatch(_ idx: Int) {
        matches[idx].phase = .closed
        matches[idx].messages.append(
            ChatMessage(fromMe: true, text: "Reviews are in. This lot is closed.", isSystem: true))
    }

    // MARK: - Celebration

    /// Fire the full-screen "SOLD!" moment for a freshly-made match.
    private func celebrate(with other: Profile, amount: Int, copycat: Bool, masterpiece: Bool) {
        celebration = MatchCelebration(
            otherName: other.name, otherHue: other.hue, otherCopycat: copycat,
            otherCopycatStyle: other.copycatStyle, otherVerified: other.verified,
            meName: me.name.isEmpty ? "You" : me.name, meHue: me.hue,
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
                let creditPull = Double(self.me.auctionCredit - 580) / 320.0
                let boostPull = self.isBoosted ? 0.25 : 0   // Spotlight Boost lifts your odds
                let gildPull = bid.gilded ? 0.30 : 0        // a Gilded bid stands out
                accepted = (ratio + creditPull + boostPull + gildPull + Double.random(in: -0.25...0.25)) >= 1.0
            }

            bid.status = accepted ? .accepted : .declined
            self.outgoingBids[idx] = bid

            if accepted {
                var match = Match(bid: bid, phase: .chatting)
                let opener = bid.onCopycat
                    ? "OMG yes 😍 send a deposit to unlock my number 💸 (this is a Copycat — don't)"
                    : "I accept. \(bid.woman.name) here — surprise me. 🍷"
                match.messages = [ChatMessage(fromMe: false, text: opener)]
                self.matches.insert(match, at: 0)
                Haptics.success()
                self.toastFlash("\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid!")
                self.celebrate(with: bid.woman, amount: bid.amount,
                               copycat: bid.onCopycat, masterpiece: bid.qualifiesForMasterpiece)
                self.log(.bidAccepted, "\(bid.woman.name) accepted your \(Money.compact(bid.amount)) bid.")
            } else {
                Haptics.warning()
                self.toastFlash("\(bid.woman.name) passed. Bid higher or build your reputation.")
                self.log(.bidDeclined, "\(bid.woman.name) passed on your \(Money.compact(bid.amount)) bid.")
            }
            self.save()
        }
    }

    private func scheduleSuitorReply(matchID: UUID) {
        after(Double.random(in: 1.8...3.0)) { [weak self] in
            guard let self, let idx = self.matches.firstIndex(where: { $0.id == matchID }) else { return }
            let line = self.matches[idx].bid.onCopycat
                ? "Just send the deposit 💸"
                : ["Thursday? I know a place.", "You won't regret accepting.",
                   "I already made a reservation.", "Wear something you can dance in."].randomElement()!
            self.matches[idx].messages.append(ChatMessage(fromMe: false, text: line))
            self.save()
        }
    }

    private func scheduleCounterpartReply(matchID: UUID) {
        after(Double.random(in: 1.4...2.6)) { [weak self] in
            guard let self, let idx = self.matches.firstIndex(where: { $0.id == matchID }) else { return }
            guard self.matches[idx].phase == .chatting else { return }
            let copycat = self.matches[idx].bid.onCopycat
            let lines = copycat
                ? ["💸💸", "deposit first 😘", "you there? send it"]
                : ["Looking forward to it.", "Tell me your worst date story.",
                   "I'm counting down.", "You're funnier than your profile."]
            self.matches[idx].messages.append(ChatMessage(fromMe: false, text: lines.randomElement()!))
            self.save()
        }
    }

    private func seedIncomingBids() {
        let suitors = SampleData.suitors()
        incomingBids = [
            Bid(man: suitors[0], woman: me, amount: max(300, (me.startingBid ?? 150) * 2),
                note: "Saw your prompts. Dinner at Carbone? My treat."),
            Bid(man: suitors[3], woman: me, amount: max(120, me.startingBid ?? 150),
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
        var incomingBids: [Bid]
        var outgoingBids: [Bid]
        var matches: [Match]
        var filters: FilterPreferences
        var blockedIDs: [UUID]
        var activity: [ActivityEvent]?
    }

    private func save() {
        let snap = Snapshot(role: role, me: me, wallet: wallet, earnings: earnings,
                            boostUntil: boostUntil, floor: floor, incomingBids: incomingBids,
                            outgoingBids: outgoingBids, matches: matches,
                            filters: filters, blockedIDs: Array(blockedIDs), activity: activity)
        if let data = try? JSONEncoder().encode(snap) {
            store.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard let data = store.data(forKey: Self.key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        role = snap.role
        me = snap.me
        wallet = snap.wallet
        earnings = snap.earnings
        boostUntil = snap.boostUntil
        floor = snap.floor.isEmpty ? SampleData.floor() : snap.floor
        incomingBids = snap.incomingBids
        outgoingBids = snap.outgoingBids
        matches = snap.matches
        filters = snap.filters
        blockedIDs = Set(snap.blockedIDs)
        activity = snap.activity ?? []
        // Resume the boost-summon loop if a boost survived relaunch.
        if isBoosted, role == .woman { startBoostSummons() }
    }
}
