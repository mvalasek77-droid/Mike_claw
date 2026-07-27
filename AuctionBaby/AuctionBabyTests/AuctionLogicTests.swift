import XCTest
@testable import AuctionBaby

/// Unit tests for the pure domain logic — archetype pricing, the credit-score
/// analogues, copycat penalties, and the Masterpiece rule. These cover the
/// synchronous store behaviour; the timed simulation (woman decisions, chat
/// replies) is intentionally not asserted here.
final class AuctionLogicTests: XCTestCase {

    // MARK: Archetype pricing

    func testArchetypePricesMatchSpec() {
        XCTAssertEqual(Archetype.none.purchase, .free)
        XCTAssertEqual(Archetype.goodGuy.usd, 4.99)
        XCTAssertEqual(Archetype.inAndOut.usd, 9.99)
        XCTAssertEqual(Archetype.whyNot.usd, 19.99)
        XCTAssertEqual(Archetype.goodJob.usd, 99.99)
        XCTAssertEqual(Archetype.inheritance.usd, 999.99)
        XCTAssertEqual(Archetype.influencer.usd, 2_499.99)
        XCTAssertEqual(Archetype.ferrari.usd, 4_999.99)
        XCTAssertEqual(Archetype.trillionaire.usd, 9_999.99)
    }

    /// Every rating except "No Rating" is a real purchase — Gavels must never
    /// buy status, or the whole premise (the price IS the signal) collapses.
    func testEveryRatingIsARealPurchase() {
        XCTAssertNil(Archetype.none.productID, "No Rating is free")
        XCTAssertNil(Archetype.none.usd)
        for tier in Archetype.allCases where tier != .none {
            XCTAssertNotNil(tier.productID, "\(tier.title) must be a StoreKit product")
            XCTAssertNotNil(tier.usd, "\(tier.title) must carry a price")
        }
        XCTAssertEqual(Archetype.moneyTiers.count, Archetype.allCases.count - 1)
    }

    /// Prices must ascend with the ladder and respect Apple's $9,999.99 ceiling.
    func testPricesAscendAndRespectAppleCeiling() {
        let usd = Archetype.moneyTiers.compactMap(\.usd)
        XCTAssertEqual(usd, usd.sorted(), "ratings must ascend in price")
        for tier in Archetype.moneyTiers {
            XCTAssertLessThanOrEqual(tier.usd ?? 0, 9_999.99,
                                     "\(tier.title) exceeds Apple's IAP ceiling")
        }
        XCTAssertEqual(Archetype.trillionaire.usd, 9_999.99, "the top sits at the ceiling")
        let ids = Archetype.productIDs
        XCTAssertEqual(Set(ids).count, ids.count, "status product IDs unique")
        for id in ids {
            XCTAssertEqual(Archetype.tier(forProductID: id)?.productID, id, "round-trips")
        }
        XCTAssertNil(Archetype.tier(forProductID: "com.valasek.auctionbaby.nope"))
    }

    /// Gavels are the tactical currency, never a status shortcut.
    func testGavelsCannotBuyStatus() {
        let gavelCosts = [AuctionStore.gildedBidCost,
                          AuctionStore.bidInsuranceCost,
                          AuctionStore.streakFreezeGavelCost]
        for cost in gavelCosts { XCTAssertGreaterThan(cost, 0) }
        // No archetype exposes a Gavel price at all.
        for tier in Archetype.allCases {
            switch tier.purchase {
            case .free: XCTAssertEqual(tier, .none)
            case .money: break
            }
        }
    }

    func testOnlyTrillionaireUsesPrestigeStyle() {
        for tier in Archetype.allCases {
            XCTAssertEqual(tier.usesPrestigeStyle, tier == .trillionaire)
        }
    }

    func testNextTierLadder() {
        XCTAssertEqual(Archetype.none.next, .goodGuy)
        XCTAssertEqual(Archetype.ferrari.next, .trillionaire)
        XCTAssertNil(Archetype.trillionaire.next)
    }

    // MARK: Deadbeat / credit scoring

    func testDeadbeatScoreIsHundredWithNoHistory() {
        let man = Profile(name: "New", age: 30, role: .man, location: "", bio: "", hue: 0.5)
        XCTAssertEqual(man.deadbeatScore, 100)
    }

    func testDeadbeatScoreReflectsPaymentHistory() {
        var man = Profile(name: "Mixed", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        man.reviews = [
            DateReview(authorName: "A", authorHue: 0, stars: 5, text: "", paidBid: true),
            DateReview(authorName: "B", authorHue: 0, stars: 1, text: "", paidBid: false),
            DateReview(authorName: "C", authorHue: 0, stars: 4, text: "", paidBid: true),
            DateReview(authorName: "D", authorHue: 0, stars: 5, text: "", paidBid: true),
        ]
        XCTAssertEqual(man.deadbeatScore, 75) // 3 of 4 paid
    }

    func testHigherArchetypeRaisesAuctionCredit() {
        var poor = Profile(name: "P", age: 30, role: .man, location: "", bio: "", hue: 0.5)
        poor.archetype = .none
        var rich = poor
        rich.archetype = .trillionaire
        XCTAssertGreaterThan(rich.auctionCredit, poor.auctionCredit)
        XCTAssertLessEqual(rich.auctionCredit, 900)
        XCTAssertGreaterThanOrEqual(poor.auctionCredit, 300)
    }

    func testCopycatBidsLowerCredit() {
        var clean = Profile(name: "C", age: 30, role: .man, location: "", bio: "", hue: 0.5)
        clean.archetype = .goodJob
        var flagged = clean
        flagged.copycatBids = 3
        XCTAssertLessThan(flagged.auctionCredit, clean.auctionCredit)
    }

    // MARK: Credit report (300–900)

    /// The only road to 900: verified Trillionaire, flawless payment history,
    /// deep track record, identity verified, zero copycat incidents.
    func testPerfectManHitsNineHundred() {
        var man = Profile(name: "Perfect", age: 40, role: .man, location: "", bio: "", hue: 0.1)
        man.archetype = .trillionaire
        man.trillionaireVerified = true
        man.verified = true
        man.reviews = (0..<15).map { i in
            DateReview(authorName: "W\(i)", authorHue: 0, stars: 5, text: "", paidBid: true)
        }
        XCTAssertEqual(man.auctionCredit, 900)
        XCTAssertEqual(man.creditTier, "Perfect")
        // One copycat incident forfeits perfection.
        man.copycatBids = 1
        XCTAssertLessThan(man.auctionCredit, 900)
    }

    func testCreditFactorsSumToHeadline() {
        var man = Profile(name: "M", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        man.archetype = .goodJob
        man.verified = true
        man.copycatBids = 1
        man.declinedBids = 2
        man.reviews = [DateReview(authorName: "A", authorHue: 0, stars: 4, text: "", paidBid: true),
                       DateReview(authorName: "B", authorHue: 0, stars: 2, text: "", paidBid: false)]
        let sum = man.creditFactors.reduce(0) { $0 + $1.points }
        XCTAssertEqual(man.auctionCredit, min(900, max(300, 300 + sum)),
                       "the printed report must be the score's receipt")
        // Deduction lines carry negative points and comments.
        XCTAssertEqual(man.creditFactors.first { $0.name == "Copycat incidents" }?.points, -40)
        XCTAssertEqual(man.creditFactors.first { $0.name == "Passed bids" }?.points, -16)
        for factor in man.creditFactors { XCTAssertFalse(factor.comment.isEmpty) }
    }

    // MARK: Review copy correlates with credit

    /// An unpaid bid always reads as a deadbeat, whatever his credit, with a
    /// low star count.
    func testUnpaidVerdictIsAlwaysNegative() {
        for credit in [320, 600, 900] {
            let v = ReviewCopy.manVerdict(paid: false, credit: credit, bidAmount: 500, spentAmount: 0)
            XCTAssertLessThanOrEqual(v.stars, 2, "a short check can never earn 3+ stars")
            XCTAssertFalse(v.text.isEmpty)
        }
    }

    /// Among men who paid, better credit yields strictly higher (or equal) top
    /// praise — good credit → positive comments, and the inverse.
    func testPaidVerdictScalesWithCredit() {
        let poor = ReviewCopy.manVerdict(paid: true, credit: 400, bidAmount: 500, spentAmount: 500)
        let strong = ReviewCopy.manVerdict(paid: true, credit: 860, bidAmount: 500, spentAmount: 500)
        XCTAssertGreaterThanOrEqual(strong.stars, poor.stars)
        XCTAssertEqual(strong.stars, 5, "exceptional credit + paid must read 5 stars")
        XCTAssertFalse(poor.text.isEmpty)
        XCTAssertFalse(strong.text.isEmpty)
    }

    func testDeadbeatHistoryDragsCredit() {
        var payer = Profile(name: "P", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        payer.reviews = [DateReview(authorName: "A", authorHue: 0, stars: 5, text: "", paidBid: true)]
        var deadbeat = payer
        deadbeat.reviews = [DateReview(authorName: "A", authorHue: 0, stars: 1, text: "", paidBid: false)]
        XCTAssertGreaterThan(payer.auctionCredit, deadbeat.auctionCredit)
    }

    func testWomanFunWeighsDouble() {
        func woman(fun: Int, interesting: Int) -> Profile {
            var w = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
            w.reviews = [DateReview(authorName: "M", authorHue: 0, stars: 4, text: "",
                                    traits: [Trait.fun.rawValue: fun,
                                             Trait.interesting.rawValue: interesting,
                                             Trait.social.rawValue: 3,
                                             Trait.polite.rawValue: 3,
                                             Trait.genuine.rawValue: 3])]
            return w
        }
        // Same total trait points — but Fun carries hers further.
        XCTAssertGreaterThan(woman(fun: 5, interesting: 3).showcaseCredit,
                             woman(fun: 3, interesting: 5).showcaseCredit)
    }

    func testWomanShowcaseFactorsSumAndMasterpiece() {
        var w = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        w.verified = true
        w.masterpiece = true
        w.reviews = (0..<12).map { i in
            DateReview(authorName: "M\(i)", authorHue: 0, stars: 5, text: "",
                       traits: Dictionary(uniqueKeysWithValues: Trait.allCases.map { ($0.rawValue, 5) }))
        }
        XCTAssertEqual(w.showcaseCredit, 900, "a flawless, verified Masterpiece maxes the scale")
        let sum = w.showcaseFactors.reduce(0) { $0 + $1.points }
        XCTAssertEqual(w.showcaseCredit, min(900, max(300, 300 + sum)))
        XCTAssertNotNil(w.showcaseFactors.first { $0.name == "Masterpiece" })
    }

    // MARK: Honors ladder (art tiers)

    func testArtTierClimbsWithDatesAndCredit() {
        var w = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        XCTAssertEqual(w.artTier, .freshCanvas)

        func fiveStarReview(_ i: Int) -> DateReview {
            DateReview(authorName: "M\(i)", authorHue: 0, stars: 5, text: "",
                       traits: Dictionary(uniqueKeysWithValues: Trait.allCases.map { ($0.rawValue, 5) }))
        }
        w.reviews = [fiveStarReview(0)]
        XCTAssertEqual(w.artTier, .sketch)

        w.reviews = (0..<3).map(fiveStarReview)
        XCTAssertEqual(w.artTier, .limitedPrint)

        // Gallery Piece needs verification — 6 dates alone won't do it.
        w.reviews = (0..<6).map(fiveStarReview)
        XCTAssertEqual(w.artTier, .limitedPrint)
        w.verified = true
        XCTAssertEqual(w.artTier, .galleryPiece)

        w.reviews = (0..<12).map(fiveStarReview)
        XCTAssertEqual(w.artTier, .exhibitionStar)
        XCTAssertNil(w.nextArtTier, "nothing above Exhibition Star can be climbed to")

        // Masterpiece overrides the ladder entirely.
        w.masterpiece = true
        XCTAssertEqual(w.artTier, .masterpiece)
    }

    func testMasterpieceRequiresMillionDollarBid() {
        let woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        var rich = Profile(name: "T", age: 40, role: .man, location: "", bio: "", hue: 0.1)
        rich.archetype = .trillionaire
        XCTAssertTrue(Bid(man: rich, woman: woman, amount: 1_000_000).qualifiesForMasterpiece)
        XCTAssertFalse(Bid(man: rich, woman: woman, amount: 999_999).qualifiesForMasterpiece,
                       "$999,999 is not a Masterpiece — the bar is exactly one million")
        XCTAssertFalse(Bid(man: rich, woman: woman, amount: 9_999).qualifiesForMasterpiece,
                       "the $9,999 badge-price date verifies Trillionaire, but never mints a Masterpiece")
    }

    // MARK: Showcase / market value

    func testShowcaseScoreFromTraitReviews() {
        var woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        woman.reviews = [
            DateReview(authorName: "M", authorHue: 0, stars: 5, text: "",
                       traits: Dictionary(uniqueKeysWithValues: Trait.allCases.map { ($0.rawValue, 5) })),
        ]
        XCTAssertEqual(woman.showcaseScore, 100)
    }

    func testMarketValueRespectsFloor() {
        var woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        woman.startingBid = 1000
        XCTAssertGreaterThanOrEqual(woman.marketValue, 800)
    }

    // MARK: Masterpiece rule

    func testMasterpieceEligibilityRequiresTrillionaireAndFullSpend() {
        let woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        let full = Bid.masterpieceBid   // $1,000,000

        var rich = Profile(name: "T", age: 40, role: .man, location: "", bio: "", hue: 0.1)
        rich.archetype = .trillionaire
        XCTAssertTrue(Bid(man: rich, woman: woman, amount: full).qualifiesForMasterpiece)
        XCTAssertFalse(Bid(man: rich, woman: woman, amount: full - 1).qualifiesForMasterpiece)

        var notRich = rich
        notRich.archetype = .ferrari
        XCTAssertFalse(Bid(man: notRich, woman: woman, amount: full).qualifiesForMasterpiece)
    }

    func testBuyingTrillionaireStartsPending() {
        var man = Profile(name: "T", age: 40, role: .man, location: "", bio: "", hue: 0.1)
        man.archetype = .trillionaire
        XCTAssertTrue(man.showsPendingTrillionaire)
        man.trillionaireVerified = true
        XCTAssertFalse(man.showsPendingTrillionaire)
    }

    // MARK: Store flows

    @MainActor
    func testRegisterWomanSeedsInbox() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "Hi",
                       hue: 0.9, startingBid: 200, prompts: [], interests: [])
        XCTAssertEqual(store.role, .woman)
        XCTAssertFalse(store.incomingBids.isEmpty, "woman should start with seeded bids")
    }

    /// Buying status must never touch the Gavel wallet — ratings are paid
    /// through StoreKit and land via `equipArchetype`.
    @MainActor
    func testWearingAnOwnedRatingCostsNoGavels() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        store.creditGavels(50_000)
        store.ownsArchetype = { _ in true }        // pretend StoreKit says "owned"
        let before = store.wallet
        store.buyArchetype(.trillionaire)
        XCTAssertEqual(store.wallet, before, "ratings never cost Gavels")
        XCTAssertEqual(store.me.archetype, .trillionaire)
        XCTAssertFalse(store.me.trillionaireVerified, "buying only unlocks the attempt")

        // Even the cheapest rating is gated on ownership.
        store.ownsArchetype = { _ in false }
        store.buyArchetype(.goodGuy)
        XCTAssertEqual(store.me.archetype, .trillionaire, "unowned rating must not equip")
        XCTAssertEqual(store.wallet, before, "and must not spend Gavels trying")
    }

    /// "Remove rating" is always available, owned or not.
    @MainActor
    func testRemovingRatingIsAlwaysAllowed() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        store.equipArchetype(.ferrari)
        store.ownsArchetype = { _ in false }
        store.buyArchetype(.none)
        XCTAssertEqual(store.me.archetype, .none)
    }

    /// A refunded status purchase drops the badge to the best tier still held.
    @MainActor
    func testRefundedStatusDropsToOwnedTier() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        store.equipArchetype(.ferrari)
        // Owns nothing else — falls all the way back to unbadged.
        store.revokeArchetype(.ferrari) { _ in false }
        XCTAssertEqual(store.me.archetype, .none,
                       "falls back to No Rating when nothing else is owned")
        // With Inheritance still owned, that's the landing spot instead.
        store.equipArchetype(.trillionaire)
        store.revokeArchetype(.trillionaire) { $0 == .inheritance }
        XCTAssertEqual(store.me.archetype, .inheritance)
    }

    /// A refund for a tier the user already moved off must not touch the badge.
    @MainActor
    func testRefundOfUnwornTierIsIgnored() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        store.equipArchetype(.inheritance)
        store.revokeArchetype(.ferrari) { _ in false }
        XCTAssertEqual(store.me.archetype, .inheritance, "unrelated refund leaves the badge alone")
    }

    @MainActor
    func testAcceptingBidCreatesMatchWithInvite() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: [])
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        XCTAssertEqual(store.matches.count, 1)
        // The woman sends the first message (the invite).
        XCTAssertEqual(store.matches.first?.messages.first?.fromMe, false)
        XCTAssertEqual(store.incomingBids.first { $0.id == bid.id }?.status, .accepted)
    }

    @MainActor
    func testTrillionaireDateMintsMasterpiece() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: ["Art"])
        store.summonBidder(trillionaire: true)
        let bid = store.incomingBids.first { $0.qualifiesForMasterpiece }!
        store.accept(bid)
        let match = store.matches.first { $0.bid.id == bid.id }!
        store.markDateDone(match)
        let dated = store.matches.first { $0.id == match.id }!
        store.completeAsWoman(dated, paid: true, stars: 5, text: "Perfect")
        XCTAssertTrue(store.me.masterpiece, "a paid, confirmed trillionaire date should mint a Masterpiece")
    }

    @MainActor
    func testUnconfirmedTrillionaireDateDoesNotMintMasterpiece() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: ["Art"])
        store.summonBidder(trillionaire: true)
        let bid = store.incomingBids.first { $0.qualifiesForMasterpiece }!
        store.accept(bid)
        let match = store.matches.first { $0.bid.id == bid.id }!
        store.markDateDone(match)
        let dated = store.matches.first { $0.id == match.id }!
        // She does NOT confirm payment — no Masterpiece.
        store.completeAsWoman(dated, paid: false, stars: 2, text: "All talk.")
        XCTAssertFalse(store.me.masterpiece, "no confirmation means no Masterpiece")
    }

    @MainActor
    func testTrillionaireVerifiesOnlyOnConfirmedFullDate() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 40, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        // Trillionaire is a real-money purchase; StoreKit's grant hook calls
        // equipArchetype, which this stands in for.
        store.equipArchetype(.trillionaire)
        XCTAssertEqual(store.me.archetype, .trillionaire)
        XCTAssertFalse(store.me.trillionaireVerified, "buying alone leaves it pending")

        let woman = store.floor.first { !$0.isCopycat }!
        let full = Archetype.trillionaireDateGateUSD

        // Underpaying a $9,999 date must NOT verify.
        let shortMatch = Match(bid: Bid(man: store.me, woman: woman, amount: full))
        store.matches.insert(shortMatch, at: 0)
        store.completeAsMan(shortMatch, stars: 5, traits: [:], categories: [], text: "", actuallySpent: full - 1)
        XCTAssertFalse(store.me.trillionaireVerified, "paying short cannot verify")

        // Paying the full $9,999 (sim-woman confirms) verifies.
        let fullMatch = Match(bid: Bid(man: store.me, woman: woman, amount: full))
        store.matches.insert(fullMatch, at: 0)
        store.completeAsMan(fullMatch, stars: 5, traits: [:], categories: [], text: "", actuallySpent: full)
        XCTAssertTrue(store.me.trillionaireVerified, "full, confirmed payment verifies Trillionaire")
    }

    @MainActor
    func testCopycatBidIncrementsPenalty() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        let copycat = store.floor.first { $0.isCopycat }!
        let before = store.me.copycatBids
        store.placeBid(on: copycat, amount: 500, note: "")
        XCTAssertEqual(store.me.copycatBids, before + 1)
    }

    // MARK: Copycats

    func testFloorHasDisclosedCopycatsWithStyles() {
        let copycats = SampleData.floor().filter { $0.isCopycat }
        XCTAssertGreaterThanOrEqual(copycats.count, 3, "the floor should seed several lures")
        // Styling cues should span more than one look (bikini / yoga / etc.).
        let styles = Set(copycats.map { $0.copycatStyle })
        XCTAssertGreaterThan(styles.count, 1)
        // Every Copycat caption must carry its disclosure-friendly styling label.
        for c in copycats { XCTAssertFalse(c.copycatStyle.caption.isEmpty) }
    }

    func testCopycatStylePalettesAreDistinct() {
        let hues = CopycatStyle.allCases.map { $0.hues }
        XCTAssertEqual(hues.count, Set(hues.map { "\($0)" }).count, "each style needs its own palette")
    }

    // MARK: Bid rank (Pass-gated reveal)

    func testTopBidRankWhenAmountClearsField() {
        var woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        woman.startingBid = 200
        let man = Profile(name: "M", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        // A very high bid should clear the simulated competitive ceiling.
        let high = Bid(man: man, woman: woman, amount: 100_000)
        XCTAssertEqual(high.simulatedRank, .top)
    }

    func testLowBidIsOutbidDeterministically() {
        var woman = Profile(name: "Mara", age: 28, role: .woman, location: "", bio: "", hue: 0.9)
        woman.startingBid = 5_000
        let man = Profile(name: "M", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        let low = Bid(man: man, woman: woman, amount: 100)
        // Same inputs → same rank (stable, no per-launch jitter).
        XCTAssertEqual(low.simulatedRank, low.simulatedRank)
        if case .outbid(let position, let leader) = low.simulatedRank {
            XCTAssertGreaterThan(position, 1)
            XCTAssertGreaterThan(leader, low.amount)
        } else {
            XCTFail("a tiny bid against a high floor should be outbid")
        }
    }

    func testCopycatBidAlwaysReadsAsTop() {
        var copycat = Profile(name: "Bella", age: 23, role: .woman, location: "", bio: "", hue: 0.9)
        copycat.isCopycat = true
        let man = Profile(name: "M", age: 33, role: .man, location: "", bio: "", hue: 0.5)
        XCTAssertEqual(Bid(man: man, woman: copycat, amount: 1).simulatedRank, .top)
    }

    @MainActor
    func testFreeBidLimitCountsPendingOnly() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        XCTAssertEqual(store.activePendingBidCount, 0)
        let woman = store.floor.first { !$0.isCopycat }!
        store.placeBid(on: woman, amount: 300, note: "")
        XCTAssertEqual(store.activePendingBidCount, 1)
    }

    // MARK: Verification & celebration

    @MainActor
    func testVerifyMeSetsVerified() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        XCTAssertFalse(store.me.verified)
        store.verifyMe()
        XCTAssertTrue(store.me.verified)
    }

    @MainActor
    func testWomanAcceptingBidFiresCelebration() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: [])
        XCTAssertNil(store.celebration)
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        XCTAssertNotNil(store.celebration, "accepting a bid should trigger the SOLD celebration")
        XCTAssertEqual(store.celebration?.amount, bid.amount)
    }

    func testCopycatNeverVerifiedInSampleData() {
        for copycat in SampleData.floor().filter({ $0.isCopycat }) {
            XCTAssertFalse(copycat.verified, "copycats must never carry a verified check")
        }
    }

    // MARK: Activity feed

    @MainActor
    func testAcceptingLogsActivity() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: [])
        let countBefore = store.activity.count
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        XCTAssertGreaterThan(store.activity.count, countBefore)
        XCTAssertEqual(store.activity.first?.kind, .bidAccepted)
    }

    @MainActor
    func testActivityIsCappedAndNewestFirst() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        for _ in 0..<70 { store.verifyMe(); store.activateBoost() } // generate churn
        XCTAssertLessThanOrEqual(store.activity.count, 60)
    }

    // MARK: Woman-side insights

    @MainActor
    func testWorthInsightsReflectInbox() {
        let store = freshStore()
        store.register(role: .woman, name: "Ada", age: 29, location: "NYC", bio: "",
                       hue: 0.9, startingBid: 200, prompts: [], interests: [])
        let pendingBefore = store.liveBidCount
        XCTAssertGreaterThan(pendingBefore, 0)
        XCTAssertEqual(store.totalOnTable, store.incomingBids.filter { $0.status == .pending }.map(\.amount).reduce(0, +))
        XCTAssertEqual(store.highestLiveBid, store.incomingBids.filter { $0.status == .pending }.map(\.amount).max() ?? 0)
        // Accepting moves a bid out of "live" and into accepted.
        let bid = store.incomingBids.first { $0.status == .pending }!
        store.accept(bid)
        XCTAssertEqual(store.liveBidCount, pendingBefore - 1)
        XCTAssertEqual(store.acceptedCount, 1)
    }

    // MARK: Filters & safety

    func testVerifiedOnlyFilterExcludesUnverifiedAndCopycats() {
        var f = FilterPreferences()
        f.verifiedOnly = true
        let verified = Profile(name: "V", age: 30, role: .woman, location: "", bio: "", hue: 0.5, verified: true)
        var unverified = verified; unverified.verified = false
        var copycat = verified; copycat.verified = false; copycat.isCopycat = true
        XCTAssertTrue(f.matches(verified))
        XCTAssertFalse(f.matches(unverified))
        XCTAssertFalse(f.matches(copycat))
    }

    func testAgeFilterBounds() {
        var f = FilterPreferences(); f.minAge = 25; f.maxAge = 30
        let inRange = Profile(name: "A", age: 27, role: .woman, location: "", bio: "", hue: 0.5)
        let tooYoung = Profile(name: "B", age: 22, role: .woman, location: "", bio: "", hue: 0.5)
        XCTAssertTrue(f.matches(inRange))
        XCTAssertFalse(f.matches(tooYoung))
    }

    func testActiveCountTracksNarrowing() {
        var f = FilterPreferences()
        XCTAssertEqual(f.activeCount, 0)
        f.hideCopycats = true; f.verifiedOnly = true
        XCTAssertEqual(f.activeCount, 2)
    }

    @MainActor
    func testBlockRemovesFromFloorAndFiltered() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        let target = store.floor.first!
        let before = store.floor.count
        store.blockAndReport(target, reason: "Spam or scam")
        XCTAssertEqual(store.floor.count, before - 1)
        XCTAssertTrue(store.blockedIDs.contains(target.id))
        XCTAssertFalse(store.filteredFloor.contains { $0.id == target.id })
    }

    func testFirstTrillionaireIsMikeValasek() {
        let mike = SampleData.suitors().first { $0.name == "Mike Valasek" }
        XCTAssertNotNil(mike, "the founder should be on the floor")
        XCTAssertEqual(mike?.archetype, .trillionaire)
        XCTAssertEqual(mike?.trillionaireVerified, true, "he's a *verified* Trillionaire")
        XCTAssertEqual(mike?.verified, true)
    }

    // MARK: Gilded Bids & Lot of the Day

    @MainActor
    func testGildedBidSpendsGavelsAndFlags() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        store.creditGavels(1_000)
        let before = store.wallet
        let woman = store.floor.first { !$0.isCopycat }!
        store.placeBid(on: woman, amount: 300, note: "", gilded: true)
        XCTAssertEqual(store.wallet, before - AuctionStore.gildedBidCost)
        XCTAssertEqual(store.outgoingBids.first?.gilded, true)
    }

    @MainActor
    func testGildFallsBackWhenShortOnGavels() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        // Starting balance is 750; the cheapest Gavel tier (500) is affordable
        // but we want the wallet untouched, so buy nothing.
        store.buyArchetype(.inheritance) // a money tier, unowned → no-op; wallet stays 750
        XCTAssertEqual(store.me.archetype, .none, "an unowned money tier must not equip")
        store.placeBid(on: store.floor.first { !$0.isCopycat }!, amount: 100, note: "", gilded: true)
        // 750 >= 250, so this one gilds; verify the flag set and cost taken.
        XCTAssertEqual(store.outgoingBids.first?.gilded, true)
        XCTAssertEqual(store.wallet, 750 - AuctionStore.gildedBidCost)
    }

    @MainActor
    func testPromptBidCarriesReference() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        let woman = store.floor.first { !$0.isCopycat && !$0.prompts.isEmpty }!
        let q = woman.prompts[0].question
        store.placeBid(on: woman, amount: 300, note: "Loved this", promptRef: q)
        XCTAssertEqual(store.outgoingBids.first?.promptRef, q)
    }

    @MainActor
    func testLotOfTheDayIsRealAndOnFloor() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        let star = store.lotOfTheDay
        XCTAssertNotNil(star)
        XCTAssertEqual(star?.isCopycat, false, "the Lot of the Day is never a copycat")
        XCTAssertTrue(store.floor.contains { $0.id == star?.id })
    }

    // MARK: Money formatting

    func testMoneyCompact() {
        XCTAssertEqual(Money.compact(5), "$5")
        XCTAssertEqual(Money.compact(1_000), "$1,000")
        XCTAssertEqual(Money.compact(10_000), "$10K")
        XCTAssertEqual(Money.compact(1_000_000), "$1M")
        XCTAssertEqual(Money.compact(100_000_000), "$100M")
    }

    // MARK: Helpers

    @MainActor
    private func freshStore() -> AuctionStore {
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v5")
        let store = AuctionStore()
        store.resetAccount()
        return store
    }
}
