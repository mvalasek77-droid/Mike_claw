import XCTest
@testable import BoxCall

final class PriceSetterTests: XCTestCase {
    private func makeMovie(daysOut: Int = 14, consensus: Double = 20, iv: Double = 40) -> Movie {
        let release = Calendar.current.date(byAdding: .day, value: daysOut, to: Date())!
        return Movie(id: "m_test", title: "Test", studio: "Test Co",
                     releaseDate: release, posterEmoji: "🎬",
                     tagline: "", consensusOpeningMillions: consensus,
                     impliedVolPct: iv, genre: "Test")
    }

    func testChainHasTenContracts_fiveCallsFivePuts() {
        let movie = makeMovie()
        let chain = PriceSetter().chain(for: movie,
                                        tracking: .init(openingWeekendMillions: 20, impliedVolPct: 40))
        XCTAssertEqual(chain.count, 10)
        XCTAssertEqual(chain.filter { $0.side == .call }.count, 5)
        XCTAssertEqual(chain.filter { $0.side == .put  }.count, 5)
    }

    func testAtTheMoneyCall_isTimeValueOnly() {
        let movie = makeMovie(consensus: 20)
        let chain = PriceSetter().chain(for: movie,
                                        tracking: .init(openingWeekendMillions: 20, impliedVolPct: 40))
        let atmCall = chain.first { $0.side == .call && $0.strikeMillions == 20 }!
        // Intrinsic = 0 at the money; premium must be > floor and less
        // than 100% of consensus.
        XCTAssertGreaterThan(atmCall.premium, 0.25)
        XCTAssertLessThan(atmCall.premium, 20)
    }

    func testDeepInTheMoneyCall_isAtLeastIntrinsic() {
        let movie = makeMovie(consensus: 20)
        let chain = PriceSetter().chain(for: movie,
                                        tracking: .init(openingWeekendMillions: 20, impliedVolPct: 40))
        // Strike two steps below consensus is deep ITM for a Call.
        let deepITM = chain.filter { $0.side == .call }.min { $0.strikeMillions < $1.strikeMillions }!
        let intrinsic = max(20 - deepITM.strikeMillions, 0)
        XCTAssertGreaterThanOrEqual(deepITM.premium, intrinsic - 0.01)
    }

    func testHigherIV_producesHigherATMPremium() {
        let movie = makeMovie(consensus: 20)
        let low = PriceSetter().chain(for: movie,
                                      tracking: .init(openingWeekendMillions: 20, impliedVolPct: 20))
        let high = PriceSetter().chain(for: movie,
                                       tracking: .init(openingWeekendMillions: 20, impliedVolPct: 80))
        let lowATM  = low.first  { $0.side == .call && $0.strikeMillions == 20 }!.premium
        let highATM = high.first { $0.side == .call && $0.strikeMillions == 20 }!.premium
        XCTAssertGreaterThan(highATM, lowATM)
    }

    func testFloorPremium_neverBelowFloor() {
        let movie = makeMovie(daysOut: 1, consensus: 20)
        let chain = PriceSetter(floorPremium: 0.5).chain(
            for: movie, tracking: .init(openingWeekendMillions: 20, impliedVolPct: 10))
        for c in chain { XCTAssertGreaterThanOrEqual(c.premium, 0.5 - 1e-9) }
    }

    func testCallStrikes_ascendInPremiumWhenBelowConsensus() {
        let movie = makeMovie(consensus: 20)
        let chain = PriceSetter().chain(for: movie,
                                        tracking: .init(openingWeekendMillions: 20, impliedVolPct: 40))
        let calls = chain.filter { $0.side == .call }.sorted { $0.strikeMillions < $1.strikeMillions }
        // Lower strike calls should be at least as expensive as higher-strike calls.
        for i in 0..<(calls.count - 1) {
            XCTAssertGreaterThanOrEqual(calls[i].premium, calls[i + 1].premium)
        }
    }
}
