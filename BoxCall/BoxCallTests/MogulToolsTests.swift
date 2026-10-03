import XCTest
@testable import BoxCall

final class MogulToolsTests: XCTestCase {
    private func position(_ side: ContractSide, cost premium: Double, qty: Int = 1,
                          payout: Double?, genre: String? = "Horror", voided: Bool? = nil,
                          actual: Double? = 40, title: String = "Clayface") -> Position {
        var p = Position(id: UUID(), contractId: "c", movieId: "m", side: side,
                         strikeMillions: 40, multiplier: 1, quantity: qty,
                         entryPremium: premium, openedAt: Date(timeIntervalSince1970: 1_790_000_000),
                         settledPayout: payout, actualOWMillions: payout == nil ? nil : actual,
                         movieTitle: title, posterEmoji: "🎬", genre: genre)
        p.voided = voided
        return p
    }

    func testStats_splitBySideAndGenre_andSkipOpenAndRefundedTrades() {
        let stats = TradeStats(positions: [
            position(.call, cost: 10, payout: 30),                  // +20
            position(.call, cost: 10, payout: 0, genre: "Comedy"),  // -10
            position(.put, cost: 5, payout: 15),                     // +10
            position(.put, cost: 5, payout: nil),                    // open: ignored
            position(.call, cost: 8, payout: 8, voided: true),       // refunded: ignored
        ])
        XCTAssertEqual(stats.tradeCount, 3)
        let calls = stats.bySide.first { $0.name == "Calls" }
        XCTAssertEqual(calls?.trades, 2)
        XCTAssertEqual(calls?.wins, 1)
        XCTAssertEqual(calls?.profit ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(stats.byGenre.first?.name, "Horror")
        XCTAssertEqual(stats.byGenre.first?.profit ?? 0, 30, accuracy: 0.001)
        XCTAssertEqual(stats.best.map { ($0.settledPayout ?? 0) - $0.cost } ?? 0, 20, accuracy: 0.001)
        XCTAssertEqual(stats.worst.map { ($0.settledPayout ?? 0) - $0.cost } ?? 0, -10, accuracy: 0.001)
        // (+200% − 100% + 200%) / 3
        XCTAssertEqual(stats.averageReturn, 1.0, accuracy: 0.001)
    }

    func testStats_missingGenreIsOther() {
        let stats = TradeStats(positions: [position(.call, cost: 1, payout: 2, genre: nil)])
        XCTAssertEqual(stats.byGenre.map(\.name), ["Other"])
    }

    func testCSV_hasAHeaderAndOneRowPerTrade_withStatus() {
        let csv = TradeHistoryCSV.make(positions: [
            position(.call, cost: 2.5, qty: 4, payout: 30),
            position(.put, cost: 1, payout: nil),
            position(.call, cost: 1, payout: 1, voided: true),
            position(.call, cost: 1, payout: 3, actual: nil),
        ])
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, TradeHistoryCSV.header)
        XCTAssertEqual(lines.count, 5)
        XCTAssertTrue(lines[1].contains(",CALL,40,4,2.50,10.00,settled,40.0,30.00,20.00"))
        XCTAssertTrue(lines[2].contains(",open,,,"))
        XCTAssertTrue(lines[3].contains(",refunded,"))
        XCTAssertTrue(lines[4].contains(",closed early,"))
    }

    func testCSV_quotesTitlesWithCommas() {
        XCTAssertEqual(TradeHistoryCSV.field("Your Mother, Your Mother"), "\"Your Mother, Your Mother\"")
        XCTAssertEqual(TradeHistoryCSV.field("Say \"Hi\""), "\"Say \"\"Hi\"\"\"")
        XCTAssertEqual(TradeHistoryCSV.field("Clayface"), "Clayface")
    }

    func testOnlyMogulGetsTheMogulTools() {
        for tier in Membership.allCases {
            XCTAssertEqual(tier.hasProAnalytics, tier == .mogul)
            XCTAssertEqual(tier.canExportHistory, tier == .mogul)
            XCTAssertEqual(tier.hasAlternateIcons, tier == .mogul)
            XCTAssertEqual(tier.weeklyAllowance, Membership.free.weeklyAllowance, "no plan adds coins")
        }
    }

    func testEveryIconChoiceHasAPreview() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.previewImage), choice.previewImage)
        }
    }
}
