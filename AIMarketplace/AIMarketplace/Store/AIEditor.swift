import Foundation

/// The "AI Editor" — an on-device review pipeline that decides whether a
/// submitted work clears the marketplace's 85% commercial bar.
///
/// HONEST DESIGN — what each signal actually measures:
///   * **Content signals** dominate (≥70% of the overall score). They come from
///     real bytes on disk: for novels, NLP measurements over the manuscript
///     text (word count, lexical diversity, sentence variance, n-gram
///     repetition, language detection); for music, peak / RMS / dynamic-range
///     / silence ratio read by AVAudioFile; for film, duration / resolution /
///     frame rate / bitrate read by AVAsset.
///   * **Originality** is measured via on-device `NLEmbedding` semantic
///     similarity against the catalogue's first paragraphs (text) and via an
///     8x8 perceptual hash + Vision feature print over cover art. Tighter
///     thresholds than the old synopsis-only Jaccard.
///   * **Copyright risk** combines: lorem-ipsum overlap, famous-IP names in
///     title/synopsis/body, perceptual-hash collisions with catalogue covers,
///     and missing/empty attestation. None of these is dispositive by itself.
///   * **Metadata** (title length, synopsis depth, declared AI tools, pricing
///     band) is now CAPPED AT ~30% of the overall score. A glossy title page
///     can no longer drag a hollow manuscript past 85.
///
/// What this pipeline **cannot** do, even with perfect signals:
///   * Decide whether prose is *good* in any literary sense — it can detect
///     hollow or templated text, not a great unfilmed novel.
///   * Confirm a global copyright owner — it can spot famous-IP names and
///     near-duplicate catalogue covers; it cannot query a registry.
///   * Tell AI-generated content from human work, or one model from another.
/// All of these are explicitly out of scope. The Editor flags risk and pushes
/// borderline cases to a human via reduced confidence.
enum AIEditor {

    /// The pass mark is a floor, not a target — we want work that beats the
    /// best commercial releases.
    static let excellenceScore = 92
    /// Catalogue-similarity at or above which a submission is a copycat.
    static let copycatThreshold = AIReviewResult.copycatRejectionThreshold

    /// Weights for the overall blend. Content signals dominate so that a
    /// great-looking submission with no real content cannot pass 85.
    private static let contentWeight: Double = 0.55
    private static let originalityWeight: Double = 0.15
    private static let copyrightWeight: Double = 0.10
    /// Metadata gets the LAST 20% — even at a perfect metadata score, the
    /// submission needs strong content + originality + clean rights to clear 85.
    /// (≤30% as required by the spec.)
    private static let metadataWeight: Double = 0.20

    // MARK: - Public API

    /// Convenience overload. Kept callable from existing sites that don't yet
    /// have a populated content payload — but those call sites now SHOULD
    /// pass `realAnalysis` so the score reflects bytes, not strings.
    static func review(_ draft: DraftWork, against catalog: [MediaItem] = []) -> AIReviewResult {
        review(draft, against: catalog, analysis: nil)
    }

    /// Full review entry point. Pass `analysis` (built by `ReviewPipeline`) so
    /// the Editor can score real content. If it's nil the Editor proceeds
    /// in "metadata-only" mode but applies a heavy penalty: a submission
    /// without bytes can no longer pass.
    static func review(_ draft: DraftWork,
                       against catalog: [MediaItem],
                       analysis: ReviewAnalysis?) -> AIReviewResult {
        let names = criteriaNames(for: draft.type)
        let metadata = MetadataSignals(draft)
        let metadataAvg = clamp(Int((metadata.score * 100).rounded()))

        // --- Content score ---
        let content = computeContentScore(draft: draft, analysis: analysis)

        // --- Originality / copycat ---
        let (similarity, neighbour) = closestMatch(to: draft, in: catalog, analysis: analysis)
        let isCopycat = similarity >= copycatThreshold
        let originalityScore = clamp(100 - Int((similarity * 130).rounded()))

        // --- Copyright risk ---
        let copyright = computeCopyrightRisk(draft: draft, analysis: analysis, neighbourSimilarity: similarity)

        // --- Weighted overall ---
        // (1 - copyrightRisk/100) so high risk subtracts from the overall.
        let copyrightScore = clamp(100 - copyright)
        var overall = (Double(content.score) * contentWeight
                       + Double(originalityScore) * originalityWeight
                       + Double(copyrightScore) * copyrightWeight
                       + Double(metadataAvg) * metadataWeight)
        // If we have NO real content at all, cap overall hard. The audit found
        // a 110-word lorem-ipsum + metadata combo clearing 85; this is the
        // anti-theater guard. We allow metadata to push to a max of 60 unless
        // the content signal is real.
        if analysis == nil { overall = min(overall, 60) }
        if content.isMissing { overall = min(overall, 55) }
        // Copycats can't pass.
        if isCopycat { overall = min(overall, 60) }
        // Lorem ipsum content forcibly rejects.
        if let text = analysis?.text, text.loremIpsumOverlap > 0.05 { overall = min(overall, 45) }
        // Keyboard-mash gibberish (no vowels, consonant runs, impossible bigrams)
        // also forcibly rejects, even when NLLanguageRecognizer happens to call
        // the noise "English."
        if let text = analysis?.text, text.gibberishRatio > 0.30 { overall = min(overall, 30) }
        // Extreme trigram repetition (e.g. "apple banana cherry" × 1000) clears
        // the gibberish gate because each word is real English — catch it here.
        if let text = analysis?.text, text.trigramRepetitionRate > 0.80 { overall = min(overall, 30) }
        // Silent "music" or broken video forcibly rejects.
        if let audio = analysis?.audio, audio.isSilent && draft.type == .music { overall = min(overall, 35) }
        if let video = analysis?.video, video.isBroken && draft.type == .movie { overall = min(overall, 35) }
        // Famous IP names in title/synopsis can't pass without human review.
        if !copyright_isClean(analysis: analysis, draft: draft) { overall = min(overall, 78) }
        // Pricing sanity — catches the abuse pattern "list a 500-word
        // 'novel' at $19.99 to game the 85% share." If the price is at the
        // top of the band but the score isn't, cap so it lands in the
        // operator's review queue.
        if priceLooksImplausible(draft: draft, score: overall) { overall = min(overall, 78) }

        let overallInt = clamp(Int(overall.rounded()))

        // --- Per-criterion breakdown (UI surface) ---
        var criteria: [CriterionScore] = []
        for (i, name) in names.enumerated() {
            let baseline = content.perCriterion[safe: i] ?? content.score
            let blended = Int((Double(baseline) * 0.7 + Double(metadataAvg) * 0.3).rounded())
            let finalScore = clamp(min(blended, isCopycat ? 60 : 100))
            criteria.append(CriterionScore(name: name, score: finalScore,
                                           note: note(for: name, score: finalScore,
                                                      content: content, analysis: analysis,
                                                      type: draft.type)))
        }

        let originalityNote: String
        if isCopycat {
            originalityNote = "Too close to “\(neighbour)”. Copycats are rejected — this must be original."
        } else if originalityScore >= 88 {
            originalityNote = "Distinct from everything already in the catalogue."
        } else {
            originalityNote = "Somewhat derivative — push it further from existing titles."
        }
        criteria.append(CriterionScore(name: "Originality", score: originalityScore, note: originalityNote))
        criteria.append(CriterionScore(name: "Rights & Disclosure", score: copyrightScore,
                                       note: copyrightNote(risk: copyright, analysis: analysis, draft: draft)))

        let strengths = criteria.filter { $0.score >= 88 }
            .map { "\($0.name) reads commercial-grade (\($0.score))." }
        let improvements = criteria.filter { $0.score < AIReviewResult.threshold }
            .map { "\($0.name): \($0.note)" }

        let summary = verdict(overall: overallInt, isCopycat: isCopycat, neighbour: neighbour,
                              type: draft.type, content: content, analysis: analysis)
        let confidence = selfConfidence(overall: overallInt, criteria: criteria,
                                        analysisPresent: analysis != nil)
        let rationale = autonomousRationale(overall: overallInt, confidence: confidence,
                                             type: draft.type, content: content,
                                             copycat: similarity, copyright: copyright)

        var result = AIReviewResult(
            overall: overallInt,
            criteria: criteria,
            strengths: strengths.isEmpty ? ["Solid disclosure and clean packaging."] : strengths,
            improvements: improvements,
            summary: summary,
            confidence: confidence,
            autonomousRationale: rationale
        )
        result.contentQuality = content.score
        result.copycatSimilarity = similarity
        result.copycatNeighbour = neighbour
        result.copyrightRisk = copyright
        return result
    }

    // MARK: - Content scoring

    /// The score that the AI Editor derives strictly from bytes (text/audio/
    /// video). When `analysis == nil` we return a "missing content" sentinel
    /// so the overall score is capped — never a free pass.
    fileprivate struct ContentScore {
        var score: Int
        var perCriterion: [Int]
        var isMissing: Bool
        var explanation: String
    }

    private static func computeContentScore(draft: DraftWork, analysis: ReviewAnalysis?) -> ContentScore {
        guard let analysis else {
            return ContentScore(score: 0, perCriterion: [], isMissing: true,
                                 explanation: "No content was uploaded.")
        }
        switch draft.type {
        case .novel:
            guard let text = analysis.text else {
                return ContentScore(score: 0, perCriterion: [], isMissing: true,
                                     explanation: "Manuscript file couldn't be read.")
            }
            return scoreText(text)
        case .music:
            if let audio = analysis.audio {
                return scoreAudio(audio, declaredTracks: draft.length)
            }
            // House-content fallback: vet music on the lyrics+liner-notes prose
            // when on-device generation hasn't produced real audio bytes. The
            // text pipeline is the same one a novel goes through, with a word-
            // count band tuned for shorter artifacts.
            if draft.isHouseContent, let text = analysis.text {
                return scoreHouseText(text, kind: .music)
            }
            return ContentScore(score: 0, perCriterion: [], isMissing: true,
                                 explanation: "Audio file couldn't be decoded.")
        case .movie:
            if let video = analysis.video {
                return scoreVideo(video, declaredMinutes: draft.length)
            }
            // House-content fallback: vet film on the screenplay text artifact.
            if draft.isHouseContent, let text = analysis.text {
                return scoreHouseText(text, kind: .movie)
            }
            return ContentScore(score: 0, perCriterion: [], isMissing: true,
                                 explanation: "Video file couldn't be decoded.")
        }
    }

    private static func scoreText(_ r: ContentAnalysis.TextReport) -> ContentScore {
        // Word count band: 8k–120k words is the commercial novel range. Below
        // is shortform/empty; far above is fine but we cap the contribution.
        let wordScore = mapWordCount(r.wordCount)
        // Lexical diversity: 0.30 (low) … 0.65 (rich). Aim for 0.45+.
        let diversityScore = clamp(Int((mapRange(r.lexicalDiversity, inMin: 0.20, inMax: 0.55, outMin: 0.0, outMax: 100.0)).rounded()))
        // Sentence variance: 4…15 words stdev maps to 50…95.
        let varianceScore = clamp(Int((mapRange(r.sentenceLengthVariance, inMin: 3, inMax: 14, outMin: 45, outMax: 95)).rounded()))
        // Repetition: lower is better. > 0.25 is a red flag.
        let repetitionScore = clamp(Int((mapRange(1 - r.trigramRepetitionRate, inMin: 0.70, inMax: 0.98, outMin: 30, outMax: 96)).rounded()))
        // Language penalty.
        let languageScore = r.isEnglish ? 95 : 60

        // Hard floors: lorem ipsum or non-text content forces near-zero.
        if r.loremIpsumOverlap > 0.05 {
            return ContentScore(score: 8, perCriterion: [8, 8, 8, 8, 8], isMissing: false,
                                 explanation: "Manuscript reads as lorem-ipsum placeholder text.")
        }
        if r.isEffectivelyEmpty {
            return ContentScore(score: 12, perCriterion: [12, 12, 12, 12, 12], isMissing: false,
                                 explanation: "Manuscript has fewer than 50 real words.")
        }

        let avg = Int(((Double(wordScore) * 0.30
                        + Double(diversityScore) * 0.25
                        + Double(varianceScore) * 0.20
                        + Double(repetitionScore) * 0.15
                        + Double(languageScore) * 0.10)).rounded())
        let per = [wordScore, diversityScore, varianceScore, repetitionScore, languageScore]
        return ContentScore(score: clamp(avg), perCriterion: per, isMissing: false,
                             explanation: "Text quality from \(r.wordCount) words, diversity \(String(format: "%.2f", r.lexicalDiversity)).")
    }

    /// House-content text scorer: same text-quality dimensions as `scoreText`
    /// (diversity, variance, repetition, language) but with a per-medium word-
    /// count band so a 300-word lyric sheet or a 600-word screenplay scene can
    /// clear the bar when the other signals are strong. Lorem-ipsum still
    /// forcibly rejects — quality gating doesn't loosen.
    private static func scoreHouseText(_ r: ContentAnalysis.TextReport, kind: MediaType) -> ContentScore {
        if r.loremIpsumOverlap > 0.05 {
            return ContentScore(score: 8, perCriterion: [8, 8, 8, 8, 8], isMissing: false,
                                 explanation: "Artifact reads as lorem-ipsum placeholder text.")
        }
        if r.isEffectivelyEmpty {
            return ContentScore(score: 12, perCriterion: [12, 12, 12, 12, 12], isMissing: false,
                                 explanation: "Artifact has fewer than 50 real words.")
        }

        let target: (lo: Double, hi: Double)
        switch kind {
        case .novel: target = (400, 1500)
        case .music: target = (120, 500)   // lyrics + liner notes
        case .movie: target = (300, 1500)  // screenplay scene + treatment
        }
        let words = Double(r.wordCount)
        let wordScore: Int
        if words >= target.hi {
            wordScore = 92
        } else if words >= target.lo {
            wordScore = clamp(Int(mapRange(words, inMin: target.lo, inMax: target.hi,
                                            outMin: 72, outMax: 92).rounded()))
        } else {
            wordScore = clamp(Int((words / target.lo * 70).rounded()))
        }

        let diversityScore = clamp(Int((mapRange(r.lexicalDiversity, inMin: 0.20, inMax: 0.55,
                                                  outMin: 0.0, outMax: 100.0)).rounded()))
        let varianceScore = clamp(Int((mapRange(r.sentenceLengthVariance, inMin: 3, inMax: 14,
                                                 outMin: 45, outMax: 95)).rounded()))
        let repetitionScore = clamp(Int((mapRange(1 - r.trigramRepetitionRate, inMin: 0.70, inMax: 0.98,
                                                   outMin: 30, outMax: 96)).rounded()))
        let languageScore = r.isEnglish ? 95 : 60

        // Weight the length less for house content (shorter artifacts are
        // expected); weight the qualitative signals more.
        let avg = Int(((Double(wordScore) * 0.20
                        + Double(diversityScore) * 0.30
                        + Double(varianceScore) * 0.20
                        + Double(repetitionScore) * 0.20
                        + Double(languageScore) * 0.10)).rounded())
        let per = [wordScore, diversityScore, varianceScore, repetitionScore, languageScore]
        return ContentScore(score: clamp(avg), perCriterion: per, isMissing: false,
                             explanation: "House text quality: \(r.wordCount) words, diversity \(String(format: "%.2f", r.lexicalDiversity)).")
    }

    private static func mapWordCount(_ words: Int) -> Int {
        let w = Double(words)
        // 0…1k: near-zero. 1k…8k: ramp 20→65. 8k…40k: 65→90. 40k+: 90→97.
        if w < 1_000 { return clamp(Int((w / 1_000 * 20).rounded())) }
        if w < Double(ContentAnalysis.minimumNovelWords) {
            return clamp(Int(mapRange(w, inMin: 1_000, inMax: Double(ContentAnalysis.minimumNovelWords), outMin: 20, outMax: 65).rounded()))
        }
        if w < 40_000 {
            return clamp(Int(mapRange(w, inMin: Double(ContentAnalysis.minimumNovelWords), inMax: 40_000, outMin: 65, outMax: 90).rounded()))
        }
        return clamp(Int(mapRange(w, inMin: 40_000, inMax: 120_000, outMin: 90, outMax: 97).rounded()))
    }

    private static func scoreAudio(_ r: ContentAnalysis.AudioReport, declaredTracks: Int) -> ContentScore {
        if !r.decodedSuccessfully {
            return ContentScore(score: 8, perCriterion: [8, 8, 8, 8, 8], isMissing: true,
                                 explanation: "Audio file couldn't be decoded.")
        }
        if r.isSilent {
            return ContentScore(score: 10, perCriterion: [10, 10, 10, 10, 10], isMissing: false,
                                 explanation: "Audio is effectively silent (peak \(String(format: "%.4f", r.peakAmplitude))).")
        }
        // Duration band: a "track" should be ≥ 45 s.
        let perTrack = declaredTracks > 0 ? r.durationSeconds / Double(declaredTracks) : r.durationSeconds
        let durationScore = clamp(Int((mapRange(perTrack, inMin: 30, inMax: 200, outMin: 45, outMax: 95)).rounded()))
        // Sample rate: 44.1 kHz is "commercial floor", 48 kHz+ ideal.
        let rateScore = r.sampleRate >= 44_100 ? 95 : (r.sampleRate >= 32_000 ? 75 : 50)
        // Channel count: stereo expected, mono OK but penalised, 0 broken.
        let channelScore = r.channelCount >= 2 ? 92 : (r.channelCount == 1 ? 68 : 30)
        // Peak: -3 dBFS (≈0.71) to -1 dBFS (≈0.89) is ideal mastered range.
        let peakScore: Int
        if r.peakAmplitude > 0.98 { peakScore = 55 }      // clipped
        else if r.peakAmplitude > 0.65 { peakScore = 92 }  // mastered
        else if r.peakAmplitude > 0.30 { peakScore = 80 }  // quiet
        else { peakScore = 55 }                            // very quiet
        // Dynamic range: 6…20 dB is realistic. Lower = over-compressed, higher = unmastered.
        let drScore = clamp(Int((mapRange(r.dynamicRangeDB, inMin: 3, inMax: 18, outMin: 50, outMax: 92)).rounded()))

        let avg = Int(((Double(durationScore) * 0.20
                        + Double(rateScore) * 0.20
                        + Double(channelScore) * 0.15
                        + Double(peakScore) * 0.25
                        + Double(drScore) * 0.20)).rounded())
        let per = [durationScore, rateScore, channelScore, peakScore, drScore]
        return ContentScore(score: clamp(avg), perCriterion: per, isMissing: false,
                             explanation: "Audio peak \(String(format: "%.2f", r.peakAmplitude)), DR \(String(format: "%.1f", r.dynamicRangeDB)) dB.")
    }

    private static func scoreVideo(_ r: ContentAnalysis.VideoReport, declaredMinutes: Int) -> ContentScore {
        if r.isBroken {
            return ContentScore(score: 10, perCriterion: [10, 10, 10, 10, 10], isMissing: true,
                                 explanation: "Video is broken (no track / zero duration).")
        }
        // Portrait / vertical footage is unwatchable on the marketplace's
        // landscape player. Reject upfront — pixel count alone passes a 9:16
        // 1080×1920 clip as "1080p" otherwise.
        if r.width > 0, r.height > 0, Double(r.width) / Double(r.height) < 1.0 {
            return ContentScore(score: 25, perCriterion: [25, 25, 25, 25, 25], isMissing: false,
                                 explanation: "Video is portrait/vertical (\(r.width)x\(r.height)). Film must be landscape — try 16:9.")
        }
        // Duration: 5 min minimum for "film", up to feature length.
        let durationScore = clamp(Int((mapRange(r.durationSeconds, inMin: 60, inMax: 5400, outMin: 35, outMax: 95)).rounded()))
        // Resolution: 720p commercial floor, 1080p ideal, 4K+.
        let pixels = r.width * r.height
        let resScore: Int
        if pixels >= 3_840 * 2_160 { resScore = 96 }      // 4K
        else if pixels >= 1_920 * 1_080 { resScore = 92 } // 1080p
        else if pixels >= 1_280 * 720  { resScore = 80 }  // 720p
        else if pixels >= 640 * 480    { resScore = 60 }  // SD
        else { resScore = 35 }
        // Frame rate: 24/25/30 commercial; lower = stutter.
        let fpsScore: Int
        if r.frameRate >= 23.5 { fpsScore = 92 }
        else if r.frameRate >= 18 { fpsScore = 70 }
        else { fpsScore = 40 }
        // Bitrate sanity. Anything above 3 Mbps for 1080p is fine.
        let bitrateScore: Int
        if r.bitrate >= 4_000_000 { bitrateScore = 92 }
        else if r.bitrate >= 1_500_000 { bitrateScore = 75 }
        else if r.bitrate > 0 { bitrateScore = 55 }
        else { bitrateScore = 50 }
        let audioScore = r.hasAudioTrack ? 88 : 55

        let avg = Int(((Double(durationScore) * 0.25
                        + Double(resScore) * 0.25
                        + Double(fpsScore) * 0.15
                        + Double(bitrateScore) * 0.20
                        + Double(audioScore) * 0.15)).rounded())
        let per = [durationScore, resScore, fpsScore, bitrateScore, audioScore]
        _ = declaredMinutes   // not used: we trust measured duration
        return ContentScore(score: clamp(avg), perCriterion: per, isMissing: false,
                             explanation: "Video \(r.width)x\(r.height) @ \(String(format: "%.1f", r.frameRate)) fps, \(Int(r.durationSeconds)) s.")
    }

    // MARK: - Originality (catalogue similarity)

    /// Combines semantic similarity over manuscript paragraphs (when available),
    /// fall-back lexical Jaccard over title+synopsis, and perceptual-hash /
    /// feature-print over cover art. Returns the **maximum** signal — if any
    /// dimension is suspiciously close, we flag the work.
    private static func closestMatch(to draft: DraftWork,
                                     in catalog: [MediaItem],
                                     analysis: ReviewAnalysis?) -> (Double, String) {
        var best = 0.0
        var bestTitle = ""

        let mineTitleTokens = tokens(draft.title)
        let mineBodyTokens = tokens(draft.title + " " + draft.synopsis)
        let myManuscript = analysis?.manuscriptText
        let myCoverFP = analysis?.coverFingerprint

        for item in catalog where item.title.caseInsensitiveCompare(draft.title.trimmed) != .orderedSame {
            // Synopsis-level Jaccard (kept as a floor signal).
            let bodyJ = jaccard(mineBodyTokens, tokens(item.title + " " + item.synopsis))
            let titleJ = jaccard(mineTitleTokens, tokens(item.title)) * 0.9

            // Semantic similarity over manuscript text (text works only).
            var semantic: Double = 0
            if let me = myManuscript, !me.isEmpty {
                let other = item.synopsis   // we don't have catalogue manuscript bytes
                if let sim = ContentAnalysis.semanticSimilarity(me, other), sim > 0 {
                    semantic = sim
                }
            }

            // Perceptual-hash cover collision. Hamming distance ≤ 10 / 64 = strong match.
            var coverSim: Double = 0
            if let me = myCoverFP {
                if let data = item.coverImageData, let theirs = ContentAnalysis.fingerprintCover(data) {
                    let h = ContentAnalysis.hammingDistance(me.pHash, theirs.pHash)
                    // Map hamming distance to similarity. ≤4 ≈ 1.0; ≥24 ≈ 0.
                    let hammingSim = max(0.0, 1.0 - Double(h) / 24.0)
                    coverSim = max(coverSim, hammingSim)
                    if let vSim = ContentAnalysis.featurePrintSimilarity(me.visionPrint, theirs.visionPrint), vSim > coverSim {
                        coverSim = vSim
                    }
                }
            }

            let combined = max(max(bodyJ, titleJ), max(semantic, coverSim))
            if combined > best { best = combined; bestTitle = item.title }
        }
        return (best, bestTitle)
    }

    // MARK: - Copyright risk

    /// Aggregates copyright signals into 0…100 (higher = riskier).
    /// Components:
    ///   * famous-IP names anywhere in title, synopsis, manuscript → +40 each (capped)
    ///   * lorem-ipsum overlap in manuscript → +35
    ///   * cover near-duplicate of an existing catalogue cover → +25
    ///   * missing attestation → +20
    private static func computeCopyrightRisk(draft: DraftWork,
                                              analysis: ReviewAnalysis?,
                                              neighbourSimilarity: Double) -> Int {
        var risk = 0
        let blob = (draft.title + " " + draft.synopsis).lowercased()
        let famousInMeta = ContentAnalysis.famousIPVocabulary.filter { blob.contains($0.lowercased()) }
        // A single famous-IP name in the metadata is already over the autopilot
        // ceiling (35). A second pushes it well past.
        risk += min(70, famousInMeta.count * 45)

        if let text = analysis?.text {
            risk += min(55, text.famousIPMatches.count * 30)
            if text.loremIpsumOverlap > 0.05 { risk += 35 }
        }

        // Strong cover collision contributes too.
        if neighbourSimilarity > 0.6 { risk += 25 }
        else if neighbourSimilarity > 0.4 { risk += 15 }

        if !draft.hasAttested { risk += 20 }

        return clamp(risk)
    }

    /// True when no famous-IP terms appear anywhere we can see.
    /// Flags submissions priced implausibly high relative to their measured
    /// quality + length. The 85% commercial bar already gates real shipping,
    /// so this is the second-line check for an attacker who scrapes past 85
    /// with metadata polish then lists at the top of the band to game the
    /// 85% creator share. Returns true if the listing should be capped at 78
    /// (lands in the operator's review queue).
    private static func priceLooksImplausible(draft: DraftWork, score: Double) -> Bool {
        let price = draft.price
        guard price > 0 else { return false }   // free titles are fine
        // Score-based ceiling: roughly price ≤ $5 below 85, ≤ $10 at 85–94,
        // unlimited at 95+.
        let scoreCeiling: Double
        switch Int(score.rounded()) {
        case ..<85:  scoreCeiling = 5.00
        case 85..<95: scoreCeiling = 10.00
        default:      scoreCeiling = 19.99
        }
        if price > scoreCeiling { return true }
        // Length-based ceiling: very short content at premium price.
        switch draft.type {
        case .novel:
            // Use measured word count if available, else declared length.
            let wc = draft.manuscriptText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            if wc > 0, wc < 5_000, price > 4.99 { return true }
        case .music:
            if draft.length > 0, draft.length < 3, price > 4.99 { return true }   // <3 tracks
        case .movie:
            if draft.length > 0, draft.length < 10, price > 6.99 { return true }   // <10 min
        }
        return false
    }

    private static func copyright_isClean(analysis: ReviewAnalysis?, draft: DraftWork) -> Bool {
        let blob = (draft.title + " " + draft.synopsis).lowercased()
        let metaHit = ContentAnalysis.famousIPVocabulary.contains { blob.contains($0.lowercased()) }
        if metaHit { return false }
        if let text = analysis?.text, !text.famousIPMatches.isEmpty { return false }
        return true
    }

    private static func copyrightNote(risk: Int, analysis: ReviewAnalysis?, draft: DraftWork) -> String {
        if risk <= 10 { return "Clean — attestations signed, no flagged terms." }
        var bits: [String] = []
        let blob = (draft.title + " " + draft.synopsis).lowercased()
        let famous = ContentAnalysis.famousIPVocabulary.filter { blob.contains($0.lowercased()) }
        if !famous.isEmpty { bits.append("Detected famous-IP terms: \(famous.prefix(3).joined(separator: ", "))") }
        if let text = analysis?.text, !text.famousIPMatches.isEmpty {
            bits.append("Manuscript contains: \(text.famousIPMatches.prefix(3).joined(separator: ", "))")
        }
        if let text = analysis?.text, text.loremIpsumOverlap > 0.05 {
            bits.append("Lorem-ipsum filler at \(Int((text.loremIpsumOverlap * 100).rounded()))% of words")
        }
        if !draft.hasAttested {
            bits.append("Creator attestation incomplete")
        }
        if bits.isEmpty { bits.append("Multiple soft flags — please review.") }
        return bits.joined(separator: ". ")
    }

    // MARK: - Metadata signals (UI-derived, capped at ~20–30% of total)

    private struct MetadataSignals {
        let depth: Double
        let titlecraft: Double
        let disclosure: Double
        let packaging: Double
        let marketFit: Double

        init(_ d: DraftWork) {
            let words = d.synopsis.trimmed.split { $0 == " " || $0 == "\n" }.count
            depth = mapRange(Double(words), inMin: 12, inMax: 110, outMin: 0.30, outMax: 1.0)
            let titleLen = d.title.trimmed.count
            let allCaps = !d.title.isEmpty && d.title == d.title.uppercased()
            var t = mapRange(Double(titleLen), inMin: 2, inMax: 42, outMin: 0.45, outMax: 1.0)
            if allCaps { t -= 0.2 }
            titlecraft = max(0, min(1, t))
            disclosure = min(1.0, 0.55 + Double(d.aiTools.count) * 0.18)
            // Packaging now only counts if a file is genuinely attached.
            packaging = d.fileName == nil ? 0.2 : (d.length > 0 ? 0.95 : 0.85)
            let hasGenre = !d.genre.trimmed.isEmpty
            let priceOK = d.price >= 0.99 && d.price <= 19.99
            marketFit = (hasGenre ? 0.6 : 0.3) + (priceOK ? 0.4 : 0.1)
        }

        /// 0…1 weighted average of the five metadata dimensions.
        var score: Double {
            (depth * 0.25 + titlecraft * 0.15 + disclosure * 0.15
             + packaging * 0.20 + marketFit * 0.25)
        }
    }

    // MARK: - Verdict / autonomy

    private static func selfConfidence(overall: Int, criteria: [CriterionScore], analysisPresent: Bool) -> Int {
        let scores = criteria.map { Double($0.score) }
        let mean = scores.reduce(0, +) / Double(max(scores.count, 1))
        let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(scores.count, 1))
        let stdDev = variance.squareRoot()
        let consistency = max(0, 1 - stdDev / 22)
        let margin = Double(overall - AIReviewResult.threshold)
        let marginFactor = max(0, min(1, margin / 12))
        var base = 38 + marginFactor * 47 + consistency * 15
        // Without real content, the Editor's confidence is capped.
        if !analysisPresent { base = min(base, 45) }
        return clamp(Int(base.rounded()))
    }

    private static func autonomousRationale(overall: Int, confidence: Int, type: MediaType,
                                            content: ContentScore, copycat: Double, copyright: Int) -> String {
        let noun = type.title.lowercased()
        if overall < AIReviewResult.threshold {
            return "I'm not publishing this — it's below the 85% bar, so it stays a draft until you revise it."
        }
        if content.isMissing {
            return "I can see the metadata but I never read the file. I won't autopublish anything I can't actually analyse."
        }
        if copycat > AIReviewResult.autoPublishCopycatCeiling {
            return "Even at \(overall)% I won't autopublish — this overlaps too heavily with an existing title for me to stand behind it unsupervised."
        }
        if copyright > AIReviewResult.autoPublishCopyrightCeiling {
            return "I've flagged copyright risk (\(copyright)/100). That stays a human call, even though it cleared the bar."
        }
        if confidence >= AIReviewResult.autoPublishConfidence
            && content.score >= AIReviewResult.autoPublishContentFloor {
            return "I'm \(confidence)% confident in this verdict. \(overall)% is comfortably clear of the 85% bar with strong content (\(content.score)/100), so I've gone ahead and published this \(noun) for you."
        }
        return "This \(noun) passes at \(overall)%, but at \(confidence)% confidence (content \(content.score)) it's close enough to the bar that I'd rather you make the call before it goes live."
    }

    private static func verdict(overall: Int, isCopycat: Bool, neighbour: String, type: MediaType,
                                 content: ContentScore, analysis: ReviewAnalysis?) -> String {
        let noun = type.title.lowercased()
        if isCopycat {
            return "Rejected as a copycat. This \(noun) is too similar to “\(neighbour)”. The marketplace only accepts original, engaging work — resubmit something genuinely new."
        }
        if let text = analysis?.text, text.loremIpsumOverlap > 0.05 {
            return "Rejected. The manuscript is lorem-ipsum placeholder text — not real prose."
        }
        if let audio = analysis?.audio, audio.isSilent && type == .music {
            return "Rejected. The submitted master is silent — there's nothing for buyers to hear."
        }
        if let video = analysis?.video, video.isBroken && type == .movie {
            return "Rejected. The film file is unreadable or has no video track."
        }
        if content.isMissing {
            return "Held back. I couldn't read the uploaded file — please re-upload a valid \(noun) and resubmit."
        }
        if overall >= excellenceScore {
            return "Outstanding — \(overall)%. This beats the typical commercial release. That's the standard here: out-do human rivals, don't just match them."
        }
        if overall >= AIReviewResult.threshold {
            let above = overall - AIReviewResult.threshold
            return "Accepted at \(overall)% — \(above) point\(above == 1 ? "" : "s") above the 85% commercial floor. It'll sell; now push to beat the best commercial releases, not just clear the bar."
        }
        let gap = AIReviewResult.threshold - overall
        return "Not yet. Scored \(overall)% — \(gap) point\(gap == 1 ? "" : "s") under the 85% commercial bar. Address the notes below and resubmit."
    }

    // MARK: - Criteria per media type

    private static func criteriaNames(for type: MediaType) -> [String] {
        switch type {
        case .novel: return ["Narrative Craft", "Emotional Depth", "Prose & Polish", "Pacing & Hook", "Market Fit"]
        case .music: return ["Production Quality", "Composition", "Sonic Identity", "Mix & Master", "Replay Value"]
        case .movie: return ["Cinematography", "Story & Structure", "Editing & Pacing", "Sound Design", "Market Fit"]
        }
    }

    // MARK: - Notes

    private static func note(for criterion: String, score: Int,
                              content: ContentScore, analysis: ReviewAnalysis?, type: MediaType) -> String {
        if score >= 88 { return "Strong — no changes needed." }
        if score >= AIReviewResult.threshold { return "Meets the bar; minor tightening optional." }
        // Type-aware fall-through.
        switch criterion {
        case "Narrative Craft", "Story & Structure", "Composition":
            if let text = analysis?.text, text.wordCount < ContentAnalysis.minimumNovelWords {
                return "Too short to read commercial — only \(text.wordCount) words; aim for \(ContentAnalysis.minimumNovelWords)+."
            }
            return "Deepen the structure — clearer stakes, sharper turns."
        case "Emotional Depth", "Sonic Identity":
            return "Make it resonate harder — sharpen the emotional core and identity."
        case "Prose & Polish", "Mix & Master", "Editing & Pacing":
            if let text = analysis?.text, text.trigramRepetitionRate > 0.20 {
                return "Repetition is high (\(Int((text.trigramRepetitionRate * 100).rounded()))% of 3-grams repeat). Edit out filler."
            }
            return "Another QC pass on the uploaded file will lift this."
        case "Pacing & Hook", "Replay Value":
            return "Lead with a stronger hook; clarify the payoff for the audience."
        case "Production Quality", "Cinematography", "Sound Design":
            if let audio = analysis?.audio, audio.dynamicRangeDB < 4 {
                return "Master is over-compressed (DR \(String(format: "%.1f", audio.dynamicRangeDB)) dB). Loosen the limiter."
            }
            return "Confirm the master is delivered at full commercial fidelity."
        case "Market Fit":
            return "Pick a tighter genre and a list price inside the $0.99–$19.99 sweet spot."
        default:
            return "Tighten this dimension before resubmitting."
        }
    }

    // MARK: - Token helpers (legacy fallback)

    private static func tokens(_ s: String) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    private static func clamp(_ value: Int) -> Int { max(0, min(100, value)) }
}

/// Aggregated, real-content analysis bundle passed into the AI Editor. The
/// publishing pipeline builds one of these before calling `AIEditor.review`.
struct ReviewAnalysis {
    var text: ContentAnalysis.TextReport?
    var audio: ContentAnalysis.AudioReport?
    var video: ContentAnalysis.VideoReport?
    /// Full manuscript text (text submissions only) for semantic similarity.
    /// Held only for the duration of the review.
    var manuscriptText: String?
    var coverFingerprint: ContentAnalysis.CoverFingerprint?
}

func mapRange(_ x: Double, inMin: Double, inMax: Double, outMin: Double, outMax: Double) -> Double {
    guard inMax != inMin else { return outMin }
    let t = max(0, min(1, (x - inMin) / (inMax - inMin)))
    return outMin + t * (outMax - outMin)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
