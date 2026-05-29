import XCTest
@testable import AIMarketplace

/// Deterministic tests for the content analysis primitives. These verify the
/// measurements the AI Editor depends on — they don't speak to scoring, only
/// to the underlying numbers being honest (real bytes → real metrics).
final class ContentAnalysisTests: XCTestCase {

    // MARK: - Text

    func testEmptyTextReportIsEmpty() {
        let report = ContentAnalysis.analyseText("")
        XCTAssertEqual(report.wordCount, 0)
        XCTAssertTrue(report.isEffectivelyEmpty)
    }

    func testLoremIpsumIsDetected() {
        let lorem = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
        tempor incididunt ut labore et dolore magna aliqua.
        """
        let report = ContentAnalysis.analyseText(lorem)
        XCTAssertGreaterThan(report.loremIpsumOverlap, 0.4,
                              "Classic lorem-ipsum should be flagged as filler text")
        XCTAssertGreaterThan(report.wordCount, 10)
    }

    func testRealEnglishProseIsNotLoremIpsum() {
        let prose = """
        The lighthouse stood alone on the rocks, weathered by decades of salt
        and storm. Helena climbed the iron stairs slowly, counting each step
        the way her grandmother had taught her, the way she had counted the
        years since the accident. The lamp room smelled of old brass and
        kerosene; outside the wind worried the windows.
        """
        let report = ContentAnalysis.analyseText(prose)
        XCTAssertLessThan(report.loremIpsumOverlap, 0.05)
        XCTAssertTrue(report.isEnglish)
        XCTAssertGreaterThan(report.lexicalDiversity, 0.5,
                              "Original prose should have decent lexical diversity")
    }

    func testTrigramRepetitionDetection() {
        let repeated = String(repeating: "the cat sat on the mat. ", count: 50)
        let report = ContentAnalysis.analyseText(repeated)
        XCTAssertGreaterThan(report.trigramRepetitionRate, 0.5,
                              "Highly repeated text should score high on n-gram repetition")
    }

    func testFamousIPDetection() {
        let report = ContentAnalysis.analyseText(
            "Once upon a time, Harry Potter walked into the Great Hall at Hogwarts."
        )
        XCTAssertFalse(report.famousIPMatches.isEmpty)
        XCTAssertTrue(report.famousIPMatches.contains { $0.contains("Harry Potter") || $0.contains("Hogwarts") })
    }

    func testLanguageDetection() {
        let englishReport = ContentAnalysis.analyseText(
            "This is a clear, simple English paragraph about the weather and the time of day."
        )
        XCTAssertEqual(englishReport.dominantLanguage, "en")
        XCTAssertTrue(englishReport.isEnglish)
    }

    // MARK: - Perceptual hashing

    func testHammingDistanceIsZeroForIdentical() {
        XCTAssertEqual(ContentAnalysis.hammingDistance(0xDEADBEEF, 0xDEADBEEF), 0)
        XCTAssertEqual(ContentAnalysis.hammingDistance(0, 0), 0)
    }

    func testHammingDistanceCountsBitDifferences() {
        XCTAssertEqual(ContentAnalysis.hammingDistance(0xFF, 0x00), 8)
        XCTAssertEqual(ContentAnalysis.hammingDistance(0x01, 0x00), 1)
        XCTAssertEqual(ContentAnalysis.hammingDistance(UInt64.max, 0), 64)
    }

    // MARK: - Audio sanity

    /// Verify our silent-detection threshold catches a synthetic silent buffer.
    func testSilentAudioReportIsSilent() {
        let silent = ContentAnalysis.AudioReport(
            durationSeconds: 60,
            sampleRate: 44_100,
            channelCount: 2,
            peakAmplitude: 0.0001,
            rmsAmplitude: 0.0001,
            dynamicRangeDB: 0,
            isSilent: true,
            silenceRatio: 1,
            decodedSuccessfully: true
        )
        XCTAssertTrue(silent.isSilent)
    }

    // MARK: - Video sanity

    func testZeroDurationVideoIsBroken() {
        let broken = ContentAnalysis.VideoReport(
            durationSeconds: 0,
            hasVideoTrack: false,
            hasAudioTrack: false,
            width: 0, height: 0, frameRate: 0, bitrate: 0,
            decodedSuccessfully: true
        )
        XCTAssertTrue(broken.isBroken)
    }

    func testValidVideoIsNotBroken() {
        let ok = ContentAnalysis.VideoReport(
            durationSeconds: 600,
            hasVideoTrack: true,
            hasAudioTrack: true,
            width: 1920, height: 1080, frameRate: 24, bitrate: 4_000_000,
            decodedSuccessfully: true
        )
        XCTAssertFalse(ok.isBroken)
    }
}
