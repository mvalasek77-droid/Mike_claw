import XCTest
@testable import BoxCall

final class MarketMakerTests: XCTestCase {
    private func series(_ values: [Double]) -> [PricePoint] {
        var t = Date().addingTimeInterval(-Double(values.count))
        return values.map { v in
            defer { t = t.addingTimeInterval(1) }
            return PricePoint(time: t, mark: v)
        }
    }

    func testLevels_nilForShortHistory() {
        XCTAssertNil(MarketMaker.levels(from: series([1, 2, 3])))
    }

    func testLevels_supportLessThanResistance() {
        let pts = series([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        let lvl = MarketMaker.levels(from: pts)
        XCTAssertNotNil(lvl)
        XCTAssertLessThan(lvl!.support, lvl!.resistance)
    }

    func testDemandDelta_positiveNearSupport() {
        let lvl = SRLevel(support: 5, resistance: 10, mid: 7.5)
        XCTAssertGreaterThan(MarketMaker.demandDelta(mark: 5.1, level: lvl), 0)
    }

    func testDemandDelta_negativeNearResistance() {
        let lvl = SRLevel(support: 5, resistance: 10, mid: 7.5)
        XCTAssertLessThan(MarketMaker.demandDelta(mark: 9.9, level: lvl), 0)
    }

    func testDemandDelta_scalesWithDepth() {
        let lvl = SRLevel(support: 5, resistance: 10, mid: 7.5)
        let shallow = MarketMaker.demandDelta(mark: 5.5, level: lvl)   // small dip below support+zone
        let deep    = MarketMaker.demandDelta(mark: 3.0, level: lvl)   // way under support
        XCTAssertGreaterThan(deep, shallow)
    }
}
