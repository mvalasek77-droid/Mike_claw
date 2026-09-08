import XCTest
@testable import BoxCall

/// The published data set is the app's only source of crowd chatter, so
/// its wire format is pinned here. The contract these tests describe is
/// produced by `backend/pipeline` and verified on the other side by
/// `backend/pipeline/tests/test_pipeline.py`.
final class BoxCallAPISourceTests: XCTestCase {

    private func decode(_ json: String) throws -> BoxCallAPISource.Envelope {
        try JSONDecoder().decode(
            BoxCallAPISource.Envelope.self, from: Data(json.utf8))
    }

    // MARK: - Wire format

    func testDecodesAFullyPopulatedRecord() throws {
        let envelope = try decode("""
        {
          "version": 1,
          "generatedAt": "2026-09-08T12:00:00Z",
          "signals": {
            "tmdb_42": {
              "title": "Dune: Part Three",
              "socialMentions24h": 1843,
              "socialSentiment": 0.42,
              "socialDispersion": 0.31,
              "youtubeViews7d": 12000000,
              "youtubeEngagementRate": 0.031
            }
          }
        }
        """)
        let wire = try XCTUnwrap(envelope.signals["tmdb_42"])
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(wire.socialMentions24h, 1843)
        XCTAssertEqual(wire.socialSentiment ?? 0, 0.42, accuracy: 1e-9)
        XCTAssertEqual(wire.youtubeViews7d, 12_000_000)
    }

    /// The whole point of the pipeline publishing null instead of zero.
    /// If null decoded to 0 here, every gap would come back as a bearish
    /// measurement and the bias fix would be undone at the last step.
    func testNullsSurviveAsNilRatherThanZero() throws {
        let envelope = try decode("""
        {
          "version": 1,
          "signals": {
            "m1": {
              "title": "Quiet Film",
              "socialMentions24h": null,
              "socialSentiment": null,
              "socialDispersion": null,
              "youtubeViews7d": null,
              "youtubeEngagementRate": null
            }
          }
        }
        """)
        let signal = try XCTUnwrap(envelope.signals["m1"]).asSignal()
        XCTAssertNil(signal.socialMentions24h)
        XCTAssertNil(signal.socialSentiment)
        XCTAssertNil(signal.youtubeTrailerViews7d)
        XCTAssertNil(signal.youtubeEngagementRate)
        XCTAssertFalse(signal.hasAnyData)
        XCTAssertEqual(signal.coverage, 0)
    }

    func testMissingKeysAreToleratedLikeNulls() throws {
        let envelope = try decode("""
        {"version": 1, "signals": {"m1": {"title": "Sparse"}}}
        """)
        let signal = try XCTUnwrap(envelope.signals["m1"]).asSignal()
        XCTAssertFalse(signal.hasAnyData)
    }

    func testPartialRecordReportsPartialCoverage() throws {
        let envelope = try decode("""
        {
          "version": 1,
          "signals": {
            "m1": {"title": "Bluesky only",
                   "socialMentions24h": 900, "socialSentiment": 0.2}
          }
        }
        """)
        let signal = try XCTUnwrap(envelope.signals["m1"]).asSignal()
        XCTAssertTrue(signal.hasAnyData)
        XCTAssertEqual(signal.coverage, 0.5, accuracy: 0.001)
        XCTAssertNil(signal.youtubeTrailerViews7d)
    }

    /// A measured zero is a real bearish reading and must not be
    /// flattened into "no data" on the way in.
    func testMeasuredZeroDecodesAsAMeasurement() throws {
        let envelope = try decode("""
        {"version": 1, "signals": {"m1": {"title": "Ignored",
          "socialMentions24h": 0, "socialSentiment": 0.0}}}
        """)
        let signal = try XCTUnwrap(envelope.signals["m1"]).asSignal()
        XCTAssertEqual(signal.socialMentions24h, 0)
        XCTAssertEqual(signal.socialSentiment, 0.0)
        XCTAssertTrue(signal.hasAnyData)
    }

    func testEmptySignalSetDecodesCleanly() throws {
        let envelope = try decode(#"{"version": 1, "signals": {}}"#)
        XCTAssertTrue(envelope.signals.isEmpty)
    }

    func testUnknownFieldsDoNotBreakDecoding() throws {
        // The pipeline may add fields the shipped app has never seen.
        let envelope = try decode("""
        {"version": 2, "generatedAt": "2026-09-08T12:00:00Z",
         "signals": {"m1": {"title": "Future", "socialMentions24h": 5,
                            "somethingNew": {"nested": true}}}}
        """)
        XCTAssertEqual(try XCTUnwrap(envelope.signals["m1"]).socialMentions24h, 5)
    }

    // MARK: - Configuration

    func testDefaultBaseURLPointsAtThePublishedSite() {
        let url = Config.dataAPIBaseURL.absoluteString
        XCTAssertTrue(url.hasPrefix("https://"), "The API must be fetched over TLS")
        XCTAssertTrue(url.hasSuffix("/"),
                      "Base URL needs a trailing slash or appendingPathComponent drops a segment")
    }

    /// The signal file has to sit directly under the base URL, or the
    /// app fetches a 404 and silently reports no crowd data.
    func testSignalsPathResolvesUnderTheBase() {
        let resolved = Config.dataAPIBaseURL.appendingPathComponent("signals.json")
        XCTAssertTrue(resolved.absoluteString.hasSuffix("/api/v1/signals.json"),
                      "Got \(resolved.absoluteString)")
    }
}
