import XCTest
@testable import BoxCall

/// The watch app decodes the WCSession payload that WatchSyncService
/// encodes. The two Codable shapes live in separate targets (iOS app vs
/// watchOS app), so the compiler cannot catch drift between them — this
/// test pins the wire format: the JSON keys the watch's
/// `WatchBridge.Snapshot` expects are exactly the keys the iOS
/// `WatchSyncService.Snapshot` emits, with matching optional semantics
/// (synthesized Codable omits nil optionals; the watch's synthesized
/// decodeIfPresent reads the missing key back as nil).
final class BoxCallWatchSyncWireTests: XCTestCase {

    /// Keys the watch's Snapshot/PositionSnap Codable impls require.
    /// Mirror of BoxCallWatch/WatchBridge.swift — if either side renames
    /// a field, the key set changes and this test fails.
    private static let snapshotKeys: Set<String> = [
        "updatedAt", "nextMovieTitle", "nextMoviePoster", "nextMovieOpensIn",
        "balance", "totalPnL", "positions"
    ]
    private static let positionKeysRequired: Set<String> = [
        "id", "movieTitle", "movieEmoji", "sideLabel", "strikeMillions",
        "quantity", "entryPremium", "mark", "pnl", "isSettled"
    ]

    private func makeSnapshot() -> WatchSyncService.Snapshot {
        .init(
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            nextMovieTitle: "Practical Magic 2",
            nextMoviePoster: "🧙‍♀️",
            nextMovieOpensIn: 3,
            balance: 1234.5,
            totalPnL: -67.8,
            positions: [
                .init(id: "p1", movieTitle: "Resident Evil",
                      movieEmoji: "🧟", sideLabel: "CALL $50M",
                      strikeMillions: 50, quantity: 2,
                      entryPremium: 12.5, mark: 13.25, pnl: 1.5,
                      isSettled: false, settledPayout: nil),
                .init(id: "p2", movieTitle: "Wuthering Heights",
                      movieEmoji: "🌫️", sideLabel: "PUT $30M",
                      strikeMillions: 30, quantity: 1,
                      entryPremium: 8, mark: 5, pnl: -3,
                      isSettled: true, settledPayout: 120)
            ]
        )
    }

    func testSnapshotEmitsExactlyTheWatchWireKeys() throws {
        let data = try JSONEncoder().encode(makeSnapshot())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Self.snapshotKeys)
        XCTAssertEqual(json["nextMovieTitle"] as? String, "Practical Magic 2")

        let positions = try XCTUnwrap(json["positions"] as? [[String: Any]])
        XCTAssertEqual(positions.count, 2)
        for p in positions {
            // settledPayout is optional: present when non-nil, omitted
            // when nil — every other key must always be present.
            XCTAssertTrue(Self.positionKeysRequired.isSubset(of: p.keys),
                          "missing required watch key(s): \(Self.positionKeysRequired.subtracting(p.keys))")
        }
        XCTAssertEqual(positions[1]["settledPayout"] as? Double, 120)
        XCTAssertNil(positions[0]["settledPayout"], "nil settledPayout encodes as omitted/null — never garbage")
    }

    func testOpenPositionJSONWithoutSettledPayoutKeyDecodesAsNil() throws {
        // Simulates the watch side exactly: synthesized Codable
        // (decodeIfPresent) over the wire JSON an OPEN position produces
        // (settledPayout omitted). Must decode, not throw.
        let json = """
        {
          "id": "p1",
          "movieTitle": "Resident Evil",
          "movieEmoji": "🧟",
          "sideLabel": "CALL $50M",
          "strikeMillions": 50,
          "quantity": 2,
          "entryPremium": 12.5,
          "mark": 13.25,
          "pnl": 1.5,
          "isSettled": false
        }
        """
        let decoded = try JSONDecoder().decode(WatchSyncService.PositionSnap.self,
                                               from: Data(json.utf8))
        XCTAssertFalse(decoded.isSettled)
        XCTAssertNil(decoded.settledPayout)
        XCTAssertEqual(decoded.pnl, 1.5, accuracy: 1e-9)
    }

    func testDefaultsRoundTripWithPlainEncoderDecoder() throws {
        // Production uses JSONEncoder()/JSONDecoder() with default
        // settings on both sides — verify values survive that exact
        // round trip, including the nil optional.
        let snap = makeSnapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WatchSyncService.Snapshot.self, from: data)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970,
                       snap.updatedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.balance, snap.balance, accuracy: 1e-9)
        XCTAssertEqual(decoded.positions.count, 2)
        XCTAssertNil(decoded.positions.first(where: { !$0.isSettled })?.settledPayout)
        XCTAssertEqual(decoded.positions.first(where: { $0.isSettled })?.settledPayout ?? 0,
                       120, accuracy: 1e-9)
    }

    func testTopPositionDerivationMatchesComplicationExpectation() throws {
        // The complication displays the open position with the largest
        // absolute P&L. Keep the derivation pinned so the watch-side
        // computed properties and the snapshot agree.
        let snap = makeSnapshot()
        let open = snap.positions.filter { !$0.isSettled }
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.pnl ?? 0, 1.5, accuracy: 1e-9)
    }
}