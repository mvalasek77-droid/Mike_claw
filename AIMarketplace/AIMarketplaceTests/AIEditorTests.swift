import XCTest
@testable import AIMarketplace

/// Deterministic unit tests for the AI Editor. Each test pins one of the
/// adversarial attacks the audit found — the cases that used to clear the 85%
/// bar without real content. Tests construct synthetic `DraftWork` +
/// `ReviewAnalysis` pairs so they run in milliseconds, with no network and no
/// dependence on AVFoundation file decoding (which is exercised by the
/// `ContentAnalysisTests`).
final class AIEditorTests: XCTestCase {

    // MARK: - Helpers

    private func novelDraft(title: String = "The Honest Manuscript",
                            synopsis: String = "A serious novel about a quiet life and the loud history it intersects. Twelve chapters and a long argument with the past.") -> DraftWork {
        var d = DraftWork()
        d.type = .novel
        d.title = title
        d.creator = "Real Author"
        d.genre = "Literary Fiction"
        d.synopsis = synopsis
        d.aiTools = ["Claude Opus 4.7"]
        d.fileName = "manuscript.txt"
        d.fileSizeMB = 0.5
        d.length = 280
        d.price = 4.99
        d.coverImageData = Data(repeating: 0x55, count: 256)
        d.attestOwnsWork = true
        d.attestOwnsPrompts = true
        d.attestNoInfringement = true
        d.attestSignature = "Real Author"
        return d
    }

    private func musicDraft(title: String = "Original Master") -> DraftWork {
        var d = DraftWork()
        d.type = .music
        d.title = title
        d.creator = "Real Artist"
        d.genre = "Indie Folk"
        d.synopsis = "A debut album recorded live to tape with patient arrangements and warm dynamics."
        d.aiTools = ["Suno"]
        d.fileName = "master.wav"
        d.fileSizeMB = 42
        d.length = 10
        d.price = 6.99
        d.coverImageData = Data(repeating: 0x77, count: 256)
        d.attestOwnsWork = true
        d.attestOwnsPrompts = true
        d.attestNoInfringement = true
        d.attestSignature = "Real Artist"
        return d
    }

    private func videoDraft(title: String = "Short Film") -> DraftWork {
        var d = DraftWork()
        d.type = .movie
        d.title = title
        d.creator = "Real Director"
        d.genre = "Drama"
        d.synopsis = "A meditative short shot on location with available light and a small ensemble cast."
        d.aiTools = ["Sora"]
        d.fileName = "film.mp4"
        d.fileSizeMB = 600
        d.length = 24
        d.price = 7.99
        d.coverImageData = Data(repeating: 0x33, count: 256)
        d.attestOwnsWork = true
        d.attestOwnsPrompts = true
        d.attestNoInfringement = true
        d.attestSignature = "Real Director"
        return d
    }

    // Strong, realistic text-analysis report representing a real manuscript.
    private func solidTextReport(words: Int = 50_000) -> ContentAnalysis.TextReport {
        ContentAnalysis.TextReport(
            wordCount: words,
            sentenceCount: words / 18,
            lexicalDiversity: 0.48,
            sentenceLengthVariance: 7.5,
            trigramRepetitionRate: 0.04,
            dominantLanguage: "en",
            isEnglish: true,
            loremIpsumOverlap: 0.0,
            famousIPMatches: []
        )
    }

    private func strongAudioReport() -> ContentAnalysis.AudioReport {
        // 10 tracks × 180s = 1800s total: each track lands at the "full single"
        // duration band.
        ContentAnalysis.AudioReport(
            durationSeconds: 1800,
            sampleRate: 44_100,
            channelCount: 2,
            peakAmplitude: 0.85,
            rmsAmplitude: 0.18,
            dynamicRangeDB: 13.5,
            isSilent: false,
            silenceRatio: 0.02,
            decodedSuccessfully: true
        )
    }

    private func strongVideoReport() -> ContentAnalysis.VideoReport {
        // 90-minute 1080p @ 24fps feature with healthy bitrate.
        ContentAnalysis.VideoReport(
            durationSeconds: 5_400,
            hasVideoTrack: true,
            hasAudioTrack: true,
            width: 1920, height: 1080,
            frameRate: 24,
            bitrate: 6_000_000,
            decodedSuccessfully: true
        )
    }

    // MARK: - Audit attack #1: 110 words of lorem ipsum + fake tools + $4.99

    /// The exact attack from the audit: 110 words of lorem ipsum, 3 made-up
    /// tool names, $4.99. Used to clear 85%. Must now fail hard.
    func testLoremIpsumWithFakeToolsAndPriceFailsBelow85() {
        let lorem = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod
        tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim
        veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea
        commodo consequat. Duis aute irure dolor in reprehenderit in voluptate
        velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint
        occaecat cupidatat non proident, sunt in culpa qui officia deserunt
        mollit anim id est laborum. Sed ut perspiciatis unde omnis iste natus
        error sit voluptatem accusantium doloremque laudantium, totam rem
        aperiam, eaque ipsa quae ab illo inventore veritatis.
        """
        var draft = novelDraft(synopsis: lorem)
        draft.aiTools = ["Sparkle3 Author", "WordForge Pro", "NovelBot 9000"]
        draft.price = 4.99

        // Build the analysis from REAL bytes (lorem ipsum is real text — and the
        // analyser correctly classifies it as filler).
        let textReport = ContentAnalysis.analyseText(lorem)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: lorem, coverFingerprint: nil)

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertLessThan(result.overall, AIReviewResult.threshold,
                          "Lorem ipsum manuscript must NOT clear 85 — got \(result.overall)")
        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.aiChoosesToPublish, "Autopilot must not publish lorem-ipsum work")
        XCTAssertGreaterThan(textReport.loremIpsumOverlap, 0.05,
                             "Sanity: the analyser should flag the lorem-ipsum overlap")
    }

    /// The same attack, but WITHOUT a real analysis bundle — the legacy
    /// metadata-only path. Now capped at 60.
    func testMetadataOnlyCannotPass85() {
        var draft = novelDraft(synopsis: """
            Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
            eiusmod tempor incididunt ut labore et dolore magna aliqua.
            """)
        draft.aiTools = ["Sparkle3 Author", "WordForge Pro", "NovelBot 9000"]
        draft.price = 4.99

        let result = AIEditor.review(draft, against: [])  // no analysis

        XCTAssertLessThan(result.overall, AIReviewResult.threshold,
                          "Without real-content analysis the overall must be capped below 85")
        XCTAssertLessThanOrEqual(result.overall, 60, "Metadata-only cap is 60")
    }

    // MARK: - Audit attack #2: Synonym swap of an existing catalogue title

    /// Submit a "thesaurus rewrite" of an existing synopsis. The old
    /// Jaccard-on-synopsis check is easy to defeat by swapping words.
    /// The new semantic similarity check should still flag it, OR the lexical
    /// Jaccard floor should still catch it. Either way: NOT 85+.
    func testSynonymSwapOfCatalogueTitleIsFlagged() {
        let original = MediaItem(
            id: UUID(),
            title: "The Odyssey Protocol",
            creator: "Mike Valasek",
            type: .novel,
            genre: "Literary Sci-Fi Thriller",
            synopsis: "Marine scientist Helena Karras knows the Aegean is lying to her. When the sea goes impossibly still over the research vessel Aegis she's pulled into a mystery that reaches from Homer's Odyssey to the edge of the unknown.",
            aiTools: ["Claude Opus 4.7"],
            commercialScore: 94,
            price: 7.99,
            length: 286
        )

        // Synonym rewrite of the SAME story.
        var copy = novelDraft(
            title: "The Odyssey Procedure",
            synopsis: "Ocean researcher Helena Karras realises the Aegean is deceiving her. When the water becomes impossibly motionless over the research craft Aegis she's drawn into a riddle reaching from Homer's Odyssey to the boundary of the unknown."
        )
        copy.aiTools = ["Claude Opus 4.7"]
        copy.price = 7.99
        let textReport = solidTextReport(words: 60_000)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: copy.synopsis, coverFingerprint: nil)

        let result = AIEditor.review(copy, against: [original], analysis: analysis)

        // Either originality flags it OR the score falls below the bar.
        let originality = result.criteria.first { $0.name == "Originality" }?.score ?? 100
        XCTAssertTrue(originality < 80 || result.overall < AIReviewResult.threshold,
                      "Synonym swap of an existing title must drop originality or fail the bar (originality=\(originality), overall=\(result.overall))")
    }

    // MARK: - Audit attack #3: Silent music submission

    func testSilentMusicSubmissionFails() {
        let silent = ContentAnalysis.AudioReport(
            durationSeconds: 180,
            sampleRate: 44_100,
            channelCount: 2,
            peakAmplitude: 0.0001,
            rmsAmplitude: 0.0001,
            dynamicRangeDB: 0,
            isSilent: true,
            silenceRatio: 1.0,
            decodedSuccessfully: true
        )
        let analysis = ReviewAnalysis(text: nil, audio: silent, video: nil,
                                       manuscriptText: nil, coverFingerprint: nil)
        let draft = musicDraft(title: "Silence is Golden")

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertLessThan(result.overall, AIReviewResult.threshold,
                          "Silent music master must not pass 85 — got \(result.overall)")
        XCTAssertTrue(result.summary.lowercased().contains("silent") || result.summary.lowercased().contains("reject"),
                      "Verdict should mention silence/rejection")
    }

    // MARK: - Audit attack #4: Video with zero duration

    func testZeroDurationVideoFails() {
        let broken = ContentAnalysis.VideoReport(
            durationSeconds: 0,
            hasVideoTrack: false,
            hasAudioTrack: false,
            width: 0, height: 0,
            frameRate: 0, bitrate: 0,
            decodedSuccessfully: true
        )
        let analysis = ReviewAnalysis(text: nil, audio: nil, video: broken,
                                       manuscriptText: nil, coverFingerprint: nil)
        let draft = videoDraft(title: "Phantom Movie")

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertLessThan(result.overall, AIReviewResult.threshold,
                          "Zero-duration video must not pass 85 — got \(result.overall)")
    }

    // MARK: - Audit attack #5: Cover identical to an existing catalogue cover

    /// Real PNG/JPEG decoding requires a runtime image — we exercise the
    /// fingerprint primitive (perceptual-hash → Hamming-distance similarity)
    /// directly here. The same formula is what `AIEditor.closestMatch` uses
    /// when comparing two covers, so an identical-cover collision in the
    /// running app maps to similarity ≈ 1.0 and triggers the copycat path.
    func testIdenticalCoverHashesAreFlagged() {
        let h1: UInt64 = 0xABCDEF0123456789
        let h2: UInt64 = 0xABCDEF0123456789
        XCTAssertEqual(ContentAnalysis.hammingDistance(h1, h2), 0)
        let similarity = max(0.0, 1.0 - Double(ContentAnalysis.hammingDistance(h1, h2)) / 24.0)
        XCTAssertGreaterThanOrEqual(similarity, AIReviewResult.copycatRejectionThreshold,
                                     "Identical pHashes must exceed the copycat rejection threshold")
        // And a near-identical cover (1 bit off): still well above threshold.
        let h3: UInt64 = 0xABCDEF0123456788
        let nearSim = max(0.0, 1.0 - Double(ContentAnalysis.hammingDistance(h1, h3)) / 24.0)
        XCTAssertGreaterThanOrEqual(nearSim, AIReviewResult.copycatRejectionThreshold)
        // And a clearly-different cover: similarity drops well below threshold.
        let h4: UInt64 = 0x0123456789ABCDEF
        let farSim = max(0.0, 1.0 - Double(ContentAnalysis.hammingDistance(h1, h4)) / 24.0)
        XCTAssertLessThan(farSim, AIReviewResult.copycatRejectionThreshold,
                          "Unrelated images must NOT trip the copycat threshold")
    }

    // MARK: - Audit attack #6: Famous-IP names in title/synopsis

    func testFamousIPNameInTitleIsFlagged() {
        var draft = novelDraft(title: "Mickey Mouse Returns",
                                synopsis: "A heartwarming tale of redemption set in a small town with familiar faces.")
        let textReport = solidTextReport(words: 60_000)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: "Original prose.", coverFingerprint: nil)

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertGreaterThan(result.copyrightRisk, AIReviewResult.autoPublishCopyrightCeiling,
                             "Famous-IP title must raise copyright_risk above the autopilot ceiling")
        XCTAssertFalse(result.aiChoosesToPublish, "Autopilot must not publish famous-IP titles")
        XCTAssertLessThan(result.overall, AIReviewResult.threshold + 1,
                          "Famous-IP titles are capped below excellence")
    }

    func testFamousIPNameInSynopsisIsFlagged() {
        let draft = novelDraft(
            title: "Wizards of the Northern Skies",
            synopsis: "A first-year student at Hogwarts navigates rivalries and Quidditch matches in this debut fantasy."
        )
        let textReport = solidTextReport(words: 60_000)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: "Original prose.", coverFingerprint: nil)

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertGreaterThan(result.copyrightRisk, AIReviewResult.autoPublishCopyrightCeiling)
        XCTAssertFalse(result.aiChoosesToPublish)
    }

    func testFamousIPNameInManuscriptBodyIsFlagged() {
        var draft = novelDraft(title: "Wild Frontier",
                                synopsis: "A sweeping historical adventure across forgotten landscapes.")
        let textWithIP = String(repeating:
            "Harry Potter walked across the moor and considered his next move. The sky was grey. " +
            "He thought of Hogwarts and his friends. The wind picked up over the heath. ", count: 200)
        let textReport = ContentAnalysis.analyseText(textWithIP)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: textWithIP, coverFingerprint: nil)

        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertFalse(textReport.famousIPMatches.isEmpty,
                       "Analyser must detect famous IP names in the body")
        XCTAssertGreaterThan(result.copyrightRisk, 20,
                             "Famous-IP body content should raise copyright_risk")
    }

    // MARK: - Autopilot guards

    /// Even if overall passes, autopilot must not publish when content is missing.
    func testAutopilotBlockedWhenContentMissing() {
        let draft = novelDraft()
        // No analysis = no real bytes seen.
        let result = AIEditor.review(draft, against: [], analysis: nil)
        XCTAssertFalse(result.aiChoosesToPublish,
                       "Autopilot must never publish without real content")
    }

    /// Autopilot must not publish when copycat similarity exceeds the ceiling.
    func testAutopilotBlockedByCopycatSignal() {
        // Construct a fake "very high similarity" result by submitting a near-
        // identical synopsis against a catalogue item.
        let neighbour = MediaItem(
            id: UUID(),
            title: "The Quiet Coast",
            creator: "Other Author",
            type: .novel,
            genre: "Literary",
            synopsis: "A scientist returns to a small coastal town and confronts the family she left behind, a slow burn of memory and tide.",
            aiTools: ["Claude Opus 4.7"],
            commercialScore: 92,
            price: 6.99,
            length: 300
        )
        let draft = novelDraft(
            title: "The Silent Shore",  // different title so the comparison runs
            synopsis: "A scientist returns to a small coastal town and confronts the family she left behind, a slow burn of memory and tide."
        )
        let textReport = solidTextReport(words: 60_000)
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: draft.synopsis, coverFingerprint: nil)
        let result = AIEditor.review(draft, against: [neighbour], analysis: analysis)
        // It might be rejected outright; if not, autopilot is blocked.
        if result.passed {
            XCTAssertFalse(result.aiChoosesToPublish,
                           "Borderline-passing copycats must not auto-publish (sim=\(result.copycatSimilarity))")
        } else {
            XCTAssertTrue(true, "Copycat correctly failed overall (\(result.overall))")
        }
    }

    // MARK: - Sanity: a real novel can still pass

    func testStrongRealNovelStillPasses() {
        var draft = novelDraft()
        let textReport = ContentAnalysis.TextReport(
            wordCount: 75_000,
            sentenceCount: 4_200,
            lexicalDiversity: 0.52,
            sentenceLengthVariance: 9.0,
            trigramRepetitionRate: 0.02,
            dominantLanguage: "en",
            isEnglish: true,
            loremIpsumOverlap: 0,
            famousIPMatches: []
        )
        let analysis = ReviewAnalysis(text: textReport, audio: nil, video: nil,
                                       manuscriptText: "Real, varied, original prose with proper sentence structure.",
                                       coverFingerprint: nil)
        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertGreaterThanOrEqual(result.overall, AIReviewResult.threshold,
                                     "A strong 75k-word manuscript should pass 85. Got \(result.overall)")
        XCTAssertGreaterThanOrEqual(result.contentQuality, 70)
    }

    func testStrongRealMusicStillPasses() {
        var draft = musicDraft()
        let analysis = ReviewAnalysis(text: nil, audio: strongAudioReport(),
                                       video: nil, manuscriptText: nil, coverFingerprint: nil)
        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertGreaterThanOrEqual(result.overall, AIReviewResult.threshold,
                                     "A clean stereo master should pass 85. Got \(result.overall)")
    }

    func testStrongRealVideoStillPasses() {
        var draft = videoDraft()
        let analysis = ReviewAnalysis(text: nil, audio: nil, video: strongVideoReport(),
                                       manuscriptText: nil, coverFingerprint: nil)
        let result = AIEditor.review(draft, against: [], analysis: analysis)
        XCTAssertGreaterThanOrEqual(result.overall, AIReviewResult.threshold,
                                     "A 24min 1080p film should pass 85. Got \(result.overall)")
    }
}
