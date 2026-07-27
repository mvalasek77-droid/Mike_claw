import XCTest
@testable import AuctionBaby

/// End-to-end flow tests: complete simulated user journeys plus the edge cases
/// a reviewer would poke at — idempotency, invalid inputs, persistence
/// round-trips, and the streak/perk clocks (via injected dates).
@MainActor
final class FlowTests: XCTestCase {

    private func freshStore() -> AuctionStore {
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v5")
        let store = AuctionStore()
        store.resetAccount()
        return store
    }

    private func registerMan(_ store: AuctionStore) {
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "Hi",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
    }

    private func registerWoman(_ store: AuctionStore) {
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "Hi",
                       hue: 0.9, startingBid: 200, prompts: [], interests: ["Art"])
    }

    // MARK: - Complete journeys

    /// Bidder journey: register → bid → match → date → review → reputation moves.
    func testManFullJourneyMovesReputation() {
        let store = freshStore()
        registerMan(store)
        let creditBefore = store.me.auctionCredit
        let woman = store.floor.first { !$0.isCopycat }!

        store.placeBid(on: woman, amount: 400, note: "Dinner?")
        XCTAssertEqual(store.outgoingBids.count, 1)

        // Deterministic match (bypasses the async sim decision).
        let match = Match(bid: store.outgoingBids[0])
        store.matches.insert(match, at: 0)
        store.markDateDone(match)
        let dated = store.matches.first { $0.id == match.id }!
        XCTAssertEqual(dated.phase, .dateDone)

        store.completeAsMan(dated, stars: 5,
                            traits: [.fun: 5, .genuine: 4], categories: ["Wine bars"],
                            text: "Great night", actuallySpent: 400)

        let closed = store.matches.first { $0.id == match.id }!
        XCTAssertEqual(closed.phase, .closed)
        XCTAssertTrue(closed.manReviewedWoman)
        XCTAssertEqual(store.me.reviews.first?.paidBid, true, "paying in full earns a paid verdict")
        XCTAssertGreaterThanOrEqual(store.me.auctionCredit, creditBefore, "paying in full never hurts credit")
        // Her floor profile received his review.
        let her = store.floor.first { $0.id == woman.id }!
        XCTAssertEqual(her.reviews.first?.interestCategories, ["Wine bars"])
    }

    /// Lot journey: register → accept → date → deadbeat verdict lands on record.
    func testWomanDeadbeatVerdictJourney() {
        let store = freshStore()
        registerWoman(store)
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        let match = store.matches.first!
        store.markDateDone(match)
        store.completeAsWoman(store.matches.first!, paid: false, stars: 2, text: "All talk.")
        XCTAssertFalse(store.me.masterpiece, "an unpaid date can't mint anything")
        XCTAssertEqual(store.matches.first?.phase, .closed)
        XCTAssertTrue(store.matches.first!.womanReviewedMan)
    }

    // MARK: - Admin console

    func testAdminAddsAndDeletesUsers() {
        let store = freshStore()
        registerMan(store)
        let before = store.floor.count
        store.adminAddUser(name: "Test Lot", age: 27, location: "Austin", bio: "Hi",
                           startingBid: 300, verified: true, isCopycat: false, copycatStyle: .glam)
        XCTAssertEqual(store.floor.count, before + 1)
        let added = store.floor.first { $0.name == "Test Lot" }
        XCTAssertNotNil(added)
        XCTAssertEqual(added?.startingBid, 300)
        XCTAssertTrue(added?.verified == true)

        store.adminDeleteUser(added!.id)
        XCTAssertEqual(store.floor.count, before, "delete removes the added lot")
        XCTAssertNil(store.floor.first { $0.name == "Test Lot" })
    }

    /// A blank name is rejected, and a copycat can never be verified even if the
    /// verified flag is passed in.
    func testAdminAddRejectsBlankAndForcesCopycatUnverified() {
        let store = freshStore()
        registerMan(store)
        let before = store.floor.count
        store.adminAddUser(name: "   ", age: 25, location: "", bio: "",
                           startingBid: nil, verified: true, isCopycat: false, copycatStyle: .glam)
        XCTAssertEqual(store.floor.count, before, "a blank name adds nobody")

        store.adminAddUser(name: "Lure", age: 23, location: "Miami", bio: "",
                           startingBid: nil, verified: true, isCopycat: true, copycatStyle: .poolside)
        let lure = store.floor.first { $0.name == "Lure" }
        XCTAssertTrue(lure?.isCopycat == true)
        XCTAssertFalse(lure?.verified == true, "copycats can never be verified")
    }

    func testAdminDeleteScrubsRelatedBids() {
        let store = freshStore()
        registerMan(store)
        let woman = store.floor.first { !$0.isCopycat }!
        store.placeBid(on: woman, amount: 300, note: "Hi")
        XCTAssertEqual(store.outgoingBids.count, 1)
        store.adminDeleteUser(woman.id)
        XCTAssertTrue(store.outgoingBids.isEmpty, "deleting a lot clears bids that referenced her")
    }

    func testAdminManagesBidderRoster() {
        let store = freshStore()
        registerWoman(store)   // woman side seeds the bidder pool
        let before = store.adminBidders.count
        XCTAssertGreaterThan(before, 0, "the bidder pool is seeded on register")
        store.adminAddBidder(name: "Rex Vaughn", age: 44, location: "Aspen", bio: "Skis.",
                             archetype: .ferrari, verified: true)
        XCTAssertEqual(store.adminBidders.count, before + 1)
        let rex = store.adminBidders.first { $0.name == "Rex Vaughn" }
        XCTAssertEqual(rex?.archetype, .ferrari)
        XCTAssertTrue(rex?.verified == true)

        store.adminDeleteUser(rex!.id)
        XCTAssertNil(store.adminBidders.first { $0.name == "Rex Vaughn" })
    }

    func testAdminEditPreservesIdentityAndReviews() {
        let store = freshStore()
        registerMan(store)
        var lot = store.floor.first { !$0.isCopycat }!
        let id = lot.id
        let reviewCount = lot.reviews.count
        lot.name = "Renamed Lot"
        lot.startingBid = 777
        store.adminUpdate(lot)
        let after = store.floor.first { $0.id == id }
        XCTAssertEqual(after?.name, "Renamed Lot")
        XCTAssertEqual(after?.startingBid, 777)
        XCTAssertEqual(after?.reviews.count, reviewCount, "editing keeps existing reviews")
    }

    func testAdminEditCanRetargetTheCurrentUser() {
        let store = freshStore()
        registerMan(store)
        var me = store.me
        me.name = "New Name"
        me.archetype = .goodJob
        store.adminUpdate(me)
        XCTAssertEqual(store.me.name, "New Name")
        XCTAssertEqual(store.me.archetype, .goodJob)
    }

    func testAdminUpdateForcesCopycatUnverified() {
        let store = freshStore()
        registerMan(store)
        var lot = store.floor.first { !$0.isCopycat }!
        lot.isCopycat = true
        lot.verified = true
        store.adminUpdate(lot)
        let after = store.floor.first { $0.id == lot.id }
        XCTAssertTrue(after?.isCopycat == true)
        XCTAssertFalse(after?.verified == true, "a copycat can never stay verified")
    }

    func testFounderIsAdmin() {
        let store = freshStore()
        store.register(role: .man, name: "Mike Valasek", age: 39, location: "", bio: "",
                       hue: 0.1, startingBid: nil, prompts: [], interests: [])
        XCTAssertTrue(store.isAdmin)
        let store2 = freshStore()
        registerMan(store2)
        XCTAssertFalse(store2.isAdmin, "a normal user is not an admin")
    }

    // MARK: - Idempotency & abuse

    func testDoubleAcceptCreditsEarningsOnce() {
        let store = freshStore()
        registerWoman(store)
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        let earningsAfterFirst = store.earnings
        let matchesAfterFirst = store.matches.count
        store.accept(bid)   // replay — must be a no-op
        XCTAssertEqual(store.earnings, earningsAfterFirst, "double-accept must not double-credit")
        XCTAssertEqual(store.matches.count, matchesAfterFirst, "double-accept must not duplicate the match")
    }

    func testDeclineCannotFlipAnAcceptedBid() {
        let store = freshStore()
        registerWoman(store)
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        store.decline(bid)
        XCTAssertEqual(store.incomingBids.first { $0.id == bid.id }?.status, .accepted)
    }

    func testReviewsPostExactlyOnce() {
        let store = freshStore()
        registerMan(store)
        let woman = store.floor.first { !$0.isCopycat }!
        let match = Match(bid: Bid(man: store.me, woman: woman, amount: 300))
        store.matches.insert(match, at: 0)
        store.completeAsMan(match, stars: 5, traits: [:], categories: [], text: "", actuallySpent: 300)
        let mine = store.me.reviews.count
        let hers = store.floor.first { $0.id == woman.id }!.reviews.count
        store.completeAsMan(match, stars: 1, traits: [:], categories: [], text: "again", actuallySpent: 0)
        XCTAssertEqual(store.me.reviews.count, mine, "second review attempt must be a no-op")
        XCTAssertEqual(store.floor.first { $0.id == woman.id }!.reviews.count, hers)
    }

    func testZeroAndNegativeBidsRejected() {
        let store = freshStore()
        registerMan(store)
        let woman = store.floor[0]
        store.placeBid(on: woman, amount: 0, note: "")
        store.placeBid(on: woman, amount: -50, note: "")
        XCTAssertTrue(store.outgoingBids.isEmpty)
    }

    // MARK: - Rebid loop

    func testRaiseBidTakesTheTop() {
        let store = freshStore()
        registerMan(store)
        var woman = store.floor.first { !$0.isCopycat }!
        woman.startingBid = 5_000   // guarantee the low bid starts outbid
        store.placeBid(on: woman, amount: 100, note: "")
        let bid = store.outgoingBids[0]
        guard case let .outbid(_, leader) = bid.simulatedRank else {
            return XCTFail("low bid vs high floor should start outbid")
        }
        store.raiseBid(bid.id, to: leader)
        XCTAssertEqual(store.outgoingBids[0].amount, leader)
        XCTAssertEqual(store.outgoingBids[0].simulatedRank, .top, "rebidding to the leader takes the top")
    }

    func testRaiseBidGuards() {
        let store = freshStore()
        registerMan(store)
        let woman = store.floor.first { !$0.isCopycat }!
        store.placeBid(on: woman, amount: 300, note: "")
        let bid = store.outgoingBids[0]
        store.raiseBid(bid.id, to: 200)   // lower — rejected
        XCTAssertEqual(store.outgoingBids[0].amount, 300)
        store.outgoingBids[0].status = .declined
        store.raiseBid(bid.id, to: 900)   // settled — rejected
        XCTAssertEqual(store.outgoingBids[0].amount, 300)
    }

    // MARK: - Daily streak & weekly Boost (injected clocks)

    func testDailyStreakGrowsResetsAndCaps() {
        let store = freshStore()
        registerMan(store)
        let cal = Calendar.current
        let day0 = Date()
        let base = AuctionStore.dailyGavelBase

        var wallet = store.wallet
        store.claimDaily(now: day0)
        XCTAssertEqual(store.dailyStreak, 1)
        XCTAssertEqual(store.wallet, wallet + base)

        store.claimDaily(now: day0)                                   // same day — no-op
        XCTAssertEqual(store.dailyStreak, 1)

        let day1 = cal.date(byAdding: .day, value: 1, to: day0)!
        wallet = store.wallet
        store.claimDaily(now: day1)                                   // consecutive — streak 2
        XCTAssertEqual(store.dailyStreak, 2)
        XCTAssertEqual(store.wallet, wallet + base * 2)

        let day5 = cal.date(byAdding: .day, value: 4, to: day1)!
        store.claimDaily(now: day5)                                   // gap — streak resets
        XCTAssertEqual(store.dailyStreak, 1)

        // March to the cap: reward never exceeds 7×.
        var d = day5
        for _ in 0..<10 {
            d = cal.date(byAdding: .day, value: 1, to: d)!
            wallet = store.wallet
            store.claimDaily(now: d)
            XCTAssertLessThanOrEqual(store.wallet - wallet, base * 7)
        }
        XCTAssertEqual(store.dailyStreak, 11)
    }

    func testWeeklyBoostClaimHonorsTheClock() {
        let store = freshStore()
        registerWoman(store)
        let now = Date()
        XCTAssertTrue(store.canClaimWeeklyBoost(now: now))
        store.claimWeeklyBoost(now: now)
        XCTAssertTrue(store.isBoosted)
        XCTAssertFalse(store.canClaimWeeklyBoost(now: now.addingTimeInterval(3 * 24 * 3600)))
        XCTAssertTrue(store.canClaimWeeklyBoost(now: now.addingTimeInterval(8 * 24 * 3600)))
    }

    // MARK: - Persistence round-trip

    func testStateSurvivesRelaunch() {
        let store = freshStore()
        registerMan(store)
        store.creditGavels(20_000)
        store.equipArchetype(.goodJob)   // ratings are IAPs; StoreKit grants them
        store.placeBid(on: store.floor.first { !$0.isCopycat }!, amount: 250, note: "Hello")
        store.claimDaily()

        // "Relaunch": a brand-new store instance decodes the same snapshot.
        let reloaded = AuctionStore()
        XCTAssertEqual(reloaded.role, .man)
        XCTAssertEqual(reloaded.me.name, "Max")
        XCTAssertEqual(reloaded.me.archetype, .goodJob)
        XCTAssertEqual(reloaded.wallet, store.wallet)
        XCTAssertEqual(reloaded.outgoingBids.count, 1)
        XCTAssertEqual(reloaded.dailyStreak, 1)
        XCTAssertEqual(reloaded.activity.count, store.activity.count)
    }

    // MARK: - Match expiry (Bumble-style urgency)

    func testAcceptedMatchStartsWithA24HourClockAndCorrectSender() {
        let store = freshStore()
        registerWoman(store)
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        let match = store.matches.first!
        XCTAssertNotNil(match.expiresAt)
        XCTAssertFalse(match.isExpired)
        // She's the current user accepting — her own invite must render as hers.
        XCTAssertEqual(match.messages.first?.fromMe, true)
        guard let until = match.expiresAt else { return XCTFail() }
        XCTAssertGreaterThan(until.timeIntervalSinceNow, 23 * 3600)
    }

    func testExpiredMatchDetectedAfterWindowLapses() {
        let store = freshStore()
        registerWoman(store)
        store.accept(store.incomingBids.first { $0.status == .pending }!)
        let idx = store.matches.startIndex
        store.matches[idx].expiresAt = Date().addingTimeInterval(-60)   // simulate a lapsed clock
        XCTAssertTrue(store.matches[idx].isExpired)
    }

    func testSendingClearsTheExpiryClock() {
        let store = freshStore()
        registerWoman(store)
        store.accept(store.incomingBids.first { $0.status == .pending }!)
        var match = store.matches.first!
        XCTAssertNotNil(match.expiresAt)
        store.send("Looking forward to it!", in: match)
        match = store.matches.first!
        XCTAssertNil(match.expiresAt, "replying should stop the urgency clock")
    }

    func testExpiredMatchNeverShowsExpiredOncePhaseAdvances() {
        var match = Match(bid: Bid(man: Profile(name: "M", age: 30, role: .man, location: "", bio: "", hue: 0.5),
                                   woman: Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9),
                                   amount: 200))
        match.expiresAt = Date().addingTimeInterval(-60)
        XCTAssertTrue(match.isExpired)
        match.phase = .dateDone
        XCTAssertFalse(match.isExpired, "a match that progressed past chatting can't be 'cold'")
    }

    // MARK: - Message reactions

    @MainActor
    func testToggleReactionSetsAndTogglesOff() {
        let store = freshStore()
        registerWoman(store)
        store.accept(store.incomingBids.first { $0.status == .pending }!)
        let match = store.matches.first!
        let messageID = match.messages.first!.id
        store.toggleReaction("❤️", on: messageID, in: match)
        XCTAssertEqual(store.matches.first?.messages.first?.reaction, "❤️")
        store.toggleReaction("❤️", on: messageID, in: match)
        XCTAssertNil(store.matches.first?.messages.first?.reaction, "tapping the same emoji again clears it")
        store.toggleReaction("😂", on: messageID, in: match)
        XCTAssertEqual(store.matches.first?.messages.first?.reaction, "😂", "a different emoji replaces the old one")
    }

    // MARK: - Rewind last bid (Reserve perk)

    func testRewindRemovesOnlyTheLatestPendingBidAndRefundsGilding() {
        let store = freshStore()
        registerMan(store)
        store.creditGavels(5_000)
        let women = store.floor.filter { !$0.isCopycat }
        store.placeBid(on: women[0], amount: 200, note: "")
        XCTAssertTrue(store.canRewindLastBid(), "a fresh pending bid must be rewindable")
        store.placeBid(on: women[1], amount: 300, note: "", gilded: true)
        let walletBeforeRewind = store.wallet
        XCTAssertTrue(store.canRewindLastBid())
        store.rewindLastBid()
        XCTAssertEqual(store.outgoingBids.count, 1, "only the most recent bid is recalled")
        XCTAssertEqual(store.outgoingBids.first?.woman.id, women[0].id)
        XCTAssertEqual(store.wallet, walletBeforeRewind + AuctionStore.gildedBidCost, "gilding cost is refunded")
    }

    func testCannotRewindASettledBid() {
        let store = freshStore()
        registerMan(store)
        store.placeBid(on: store.floor.first { !$0.isCopycat }!, amount: 200, note: "")
        store.outgoingBids[0].status = .accepted
        XCTAssertFalse(store.canRewindLastBid())
    }

    // MARK: - Icebreakers

    func testIcebreakersDeriveFromPromptsAndInterests() {
        var p = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        p.prompts = [Prompt(question: "My simple pleasures", answer: "Sunday markets and cold brew")]
        p.interests = ["Art"]
        let lines = p.icebreakers
        XCTAssertFalse(lines.isEmpty)
        XCTAssertLessThanOrEqual(lines.count, 3)
        XCTAssertTrue(lines.contains { $0.contains("Sunday markets and cold brew") })
    }

    func testIcebreakersNeverEmptyForABareProfile() {
        let bare = Profile(name: "Bare", age: 30, role: .man, location: "", bio: "", hue: 0.5)
        XCTAssertFalse(bare.icebreakers.isEmpty)
    }
}
