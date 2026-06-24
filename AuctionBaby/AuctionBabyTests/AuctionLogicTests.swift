import XCTest
@testable import AuctionBaby

/// Unit tests for the pure domain logic — archetype pricing, the credit-score
/// analogues, copycat penalties, and the Masterpiece rule. These cover the
/// synchronous store behaviour; the timed simulation (woman decisions, chat
/// replies) is intentionally not asserted here.
final class AuctionLogicTests: XCTestCase {

    // MARK: Archetype pricing

    func testArchetypePricesMatchSpec() {
        XCTAssertEqual(Archetype.none.price, 0)
        XCTAssertEqual(Archetype.goodGuy.price, 5)
        XCTAssertEqual(Archetype.inAndOut.price, 10)
        XCTAssertEqual(Archetype.whyNot.price, 20)
        XCTAssertEqual(Archetype.goodJob.price, 100)
        XCTAssertEqual(Archetype.inheritance.price, 1_000)
        XCTAssertEqual(Archetype.influencer.price, 10_000)
        XCTAssertEqual(Archetype.ferrari.price, 100_000)
        XCTAssertEqual(Archetype.trillionaire.price, 1_000_000)
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
        XCTAssertLessEqual(rich.auctionCredit, 850)
        XCTAssertGreaterThanOrEqual(poor.auctionCredit, 300)
    }

    func testCopycatBidsLowerCredit() {
        var clean = Profile(name: "C", age: 30, role: .man, location: "", bio: "", hue: 0.5)
        clean.archetype = .goodJob
        var flagged = clean
        flagged.copycatBids = 3
        XCTAssertLessThan(flagged.auctionCredit, clean.auctionCredit)
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

    func testMasterpieceRequiresTrillionaireAndMillion() {
        let woman = Profile(name: "W", age: 28, role: .woman, location: "", bio: "", hue: 0.9)

        var rich = Profile(name: "T", age: 40, role: .man, location: "", bio: "", hue: 0.1)
        rich.archetype = .trillionaire
        let qualifying = Bid(man: rich, woman: woman, amount: 1_000_000)
        XCTAssertTrue(qualifying.qualifiesForMasterpiece)

        let tooLow = Bid(man: rich, woman: woman, amount: 999_999)
        XCTAssertFalse(tooLow.qualifiesForMasterpiece)

        var notRich = rich
        notRich.archetype = .ferrari
        let wrongTier = Bid(man: notRich, woman: woman, amount: 1_000_000)
        XCTAssertFalse(wrongTier.qualifiesForMasterpiece)
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

    @MainActor
    func testBuyArchetypeDeductsWallet() {
        let store = freshStore()
        store.register(role: .man, name: "Max", age: 31, location: "LA", bio: "",
                       hue: 0.6, startingBid: nil, prompts: [], interests: [])
        let before = store.wallet
        store.buyArchetype(.goodJob)
        XCTAssertEqual(store.me.archetype, .goodJob)
        XCTAssertEqual(store.wallet, before - 100)
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
        XCTAssertTrue(store.me.masterpiece, "a paid trillionaire date should mint a Masterpiece")
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
        UserDefaults.standard.removeObject(forKey: "auctionbaby.state.v2")
        let store = AuctionStore()
        store.resetAccount()
        return store
    }
}
