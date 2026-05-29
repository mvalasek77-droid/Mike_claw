import Foundation
import NaturalLanguage
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif
#if canImport(CoreImage)
import CoreImage
#endif

/// Real, on-device content analysis for the AI Editor.
///
/// Honest-by-design: every function below reads actual bytes (text, PCM frames,
/// video tracks, pixel data) and returns numbers derived from them. No metadata
/// shortcuts, no procedural jitter masquerading as analysis. Callers (the
/// `AIEditor`) decide what to do with the numbers; this layer just measures.
///
/// What this **cannot** do, even with full content:
///   * Decide whether the prose is "good" in any literary sense — it can only
///     measure structural properties (length, diversity, repetition, language).
///   * Identify a specific copyrighted work — it can detect very high textual
///     overlap and visual near-duplication against the on-device catalogue, not
///     a global IP registry.
///   * Listen for stolen samples — silence and clipping are detected; melody
///     plagiarism is not.
/// We make those limits explicit in `AIEditor` so the score never overclaims.
enum ContentAnalysis {

    // MARK: - Text

    /// Structural quality measurements for a submitted manuscript.
    struct TextReport: Equatable {
        var wordCount: Int
        var sentenceCount: Int
        /// Type-token ratio (unique words / total words). 0…1. Higher = richer.
        var lexicalDiversity: Double
        /// Standard deviation of sentence length in words. Higher = varied prose;
        /// near-zero suggests monotone or templated text.
        var sentenceLengthVariance: Double
        /// Fraction of overlapping 3-grams that repeat. 0…1. High = filler/loop.
        var trigramRepetitionRate: Double
        /// Dominant detected language (ISO code or "und" if unknown).
        var dominantLanguage: String
        /// True when the text contains substantial English content.
        var isEnglish: Bool
        /// Fraction (0…1) of words matching a stock lorem-ipsum / placeholder
        /// vocabulary. Surprisingly effective at catching the audit attack.
        var loremIpsumOverlap: Double
        /// Famous IP terms detected in the body (case-insensitive, word-boundary).
        var famousIPMatches: [String]

        /// `true` when the report is essentially empty — used by the Editor to
        /// keep the score from spuriously rewarding a missing/unreadable file.
        var isEffectivelyEmpty: Bool { wordCount < 50 }
    }

    /// The minimum manuscript size we require before considering a work
    /// commercially viable on the marketplace. A "novel" of 110 words is not a
    /// novel, period.
    static let minimumNovelWords = 8_000

    /// Tokens we treat as known lorem-ipsum filler. Intentionally broad: catches
    /// classic "Lorem ipsum dolor sit amet, consectetur adipiscing elit…"
    /// permutations plus the most common follow-on words.
    private static let loremIpsumVocabulary: Set<String> = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing",
        "elit", "sed", "eiusmod", "tempor", "incididunt", "labore", "magna",
        "aliqua", "enim", "veniam", "quis", "nostrud", "exercitation", "ullamco",
        "laboris", "nisi", "aliquip", "commodo", "consequat", "duis", "aute",
        "irure", "reprehenderit", "voluptate", "velit", "esse", "cillum",
        "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat",
        "cupidatat", "non", "proident", "culpa", "officia", "deserunt", "mollit",
        "anim", "laborum"
    ]

    /// Famous IP / character names submitters should NOT be claiming they wrote.
    /// Not exhaustive — combined with overall copyright_risk in `AIEditor`,
    /// never dispositive alone.
    static let famousIPVocabulary: [String] = [
        "Mickey Mouse", "Donald Duck", "Harry Potter", "Hermione Granger",
        "Dumbledore", "Hogwarts", "Star Wars", "Darth Vader", "Luke Skywalker",
        "Jedi", "Sith", "Yoda", "Spider-Man", "Batman", "Superman",
        "Wonder Woman", "Iron Man", "Captain America", "Avengers",
        "James Bond", "007", "Sherlock Holmes", "Game of Thrones",
        "Jon Snow", "Daenerys Targaryen", "Lord of the Rings", "Frodo",
        "Gandalf", "Hobbit", "Pokemon", "Pikachu", "Mario", "Luigi",
        "Princess Peach", "Zelda", "Link", "Minecraft", "Fortnite",
        "Disney", "Pixar", "Marvel", "DC Comics", "Nintendo", "Taylor Swift",
        "Beyoncé", "Drake", "Elsa", "Anna", "Frozen"
    ]

    /// Analyses the full text of a manuscript. The caller must pass real bytes —
    /// the synopsis alone is not enough.
    static func analyseText(_ raw: String) -> TextReport {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return emptyTextReport() }

        // --- Tokenisation via NaturalLanguage (real, on-device) ---
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        var allWords: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let token = String(trimmed[range])
            // NLTokenizer hands back whitespace/punctuation tokens too — keep only words.
            if token.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
                allWords.append(token.lowercased())
            }
            return true
        }

        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = trimmed
        var sentenceLengths: [Int] = []
        sentenceTokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range])
            let length = sentence.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
            if length > 0 { sentenceLengths.append(length) }
            return true
        }

        let wordCount = allWords.count
        let sentenceCount = max(sentenceLengths.count, 1)
        let uniqueCount = Set(allWords).count
        let lexicalDiversity = wordCount > 0 ? Double(uniqueCount) / Double(wordCount) : 0

        // Sentence length variance.
        let mean = Double(sentenceLengths.reduce(0, +)) / Double(max(sentenceLengths.count, 1))
        let variance = sentenceLengths.reduce(0.0) { acc, len in
            let d = Double(len) - mean
            return acc + d * d
        } / Double(max(sentenceLengths.count, 1))
        let stdDev = variance.squareRoot()

        // Trigram repetition rate.
        let trigramRate = computeTrigramRepetitionRate(words: allWords)

        // Language detection.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let lang = recognizer.dominantLanguage?.rawValue ?? "und"
        // English is treated as "intelligible" for our pipeline; non-English is
        // not penalised here — just surfaced to the Editor.
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let isEnglish = (hypotheses[.english] ?? 0) >= 0.5 || lang == "en"

        // Lorem ipsum overlap.
        let lorem = allWords.isEmpty ? 0.0 :
            Double(allWords.filter { loremIpsumVocabulary.contains($0) }.count) / Double(allWords.count)

        // Famous IP detection (substring match, case-insensitive).
        let lowerBlob = trimmed.lowercased()
        let famous = famousIPVocabulary.filter { lowerBlob.contains($0.lowercased()) }

        return TextReport(
            wordCount: wordCount,
            sentenceCount: sentenceCount,
            lexicalDiversity: lexicalDiversity,
            sentenceLengthVariance: stdDev,
            trigramRepetitionRate: trigramRate,
            dominantLanguage: lang,
            isEnglish: isEnglish,
            loremIpsumOverlap: lorem,
            famousIPMatches: famous
        )
    }

    /// Reads a text file from disk (supports .txt, .rtf, .pdf where possible)
    /// and returns the analysis. Returns nil if the file can't be decoded.
    static func analyseTextFile(at url: URL) -> TextReport? {
        guard let text = readTextFromFile(at: url) else { return nil }
        return analyseText(text)
    }

    /// Reads the first ~N paragraphs of a manuscript (for similarity scoring
    /// against the catalogue). Returns the raw text — analysis is separate.
    static func readTextFromFile(at url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()
        if ext == "rtf" {
            guard let data = try? Data(contentsOf: url),
                  let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            else { return nil }
            return attr.string
        }
        if ext == "pdf" {
            // PDFKit isn't worth pulling in for our purposes; rely on iOS's
            // ability to read tagged-text PDFs via NSAttributedString.
            guard let data = try? Data(contentsOf: url),
                  let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
            else {
                // Fallback: try raw UTF-8 decoding (won't work for binary PDF
                // but is a last-ditch attempt before giving up).
                return try? String(contentsOf: url, encoding: .utf8)
            }
            return attr.string
        }
        // .txt or anything else — try UTF-8 then fall back to ascii.
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }

    private static func computeTrigramRepetitionRate(words: [String]) -> Double {
        guard words.count >= 6 else { return 0 }
        var counts: [String: Int] = [:]
        let total = words.count - 2
        for i in 0..<total {
            let key = "\(words[i]) \(words[i+1]) \(words[i+2])"
            counts[key, default: 0] += 1
        }
        let repeated = counts.values.filter { $0 > 1 }.reduce(0, +)
        return Double(repeated) / Double(total)
    }

    private static func emptyTextReport() -> TextReport {
        TextReport(wordCount: 0, sentenceCount: 0, lexicalDiversity: 0,
                   sentenceLengthVariance: 0, trigramRepetitionRate: 0,
                   dominantLanguage: "und", isEnglish: false,
                   loremIpsumOverlap: 0, famousIPMatches: [])
    }

    // MARK: - Audio

    /// Real audio properties read straight from the container.
    struct AudioReport: Equatable {
        var durationSeconds: Double
        var sampleRate: Double
        var channelCount: Int
        /// Linear peak amplitude across the entire file (0…1).
        var peakAmplitude: Double
        /// Linear RMS amplitude across the entire file (0…1).
        var rmsAmplitude: Double
        /// Crude dynamic-range estimate in dB (20*log10(peak/rms)). +∞ → 96 cap.
        var dynamicRangeDB: Double
        /// `true` when the file is essentially silent (peak below threshold).
        var isSilent: Bool
        /// Fraction of analysed buffer windows whose RMS was at silence level.
        var silenceRatio: Double
        /// `true` only when the file decoded at all.
        var decodedSuccessfully: Bool
    }

    /// Silence threshold in linear amplitude (≈ -60 dB FS). Anything quieter is
    /// "silent" for our purposes. Music masters never sit this low.
    private static let silenceThreshold: Double = 0.001

    static func analyseAudio(at url: URL) -> AudioReport {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let file = try? AVAudioFile(forReading: url) else {
            return AudioReport(durationSeconds: 0, sampleRate: 0, channelCount: 0,
                               peakAmplitude: 0, rmsAmplitude: 0, dynamicRangeDB: 0,
                               isSilent: true, silenceRatio: 1, decodedSuccessfully: false)
        }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0

        // Stream in chunks so multi-minute files don't blow up memory.
        let chunkFrames: AVAudioFrameCount = 32_768
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            return AudioReport(durationSeconds: duration, sampleRate: sampleRate, channelCount: channelCount,
                               peakAmplitude: 0, rmsAmplitude: 0, dynamicRangeDB: 0,
                               isSilent: true, silenceRatio: 1, decodedSuccessfully: false)
        }

        var peak: Double = 0
        var sumSquares: Double = 0
        var sampleTotal: Int = 0
        var silentWindows = 0
        var totalWindows = 0

        while file.framePosition < Int64(frameCount) {
            do { try file.read(into: chunk) } catch { break }
            let frames = Int(chunk.frameLength)
            if frames == 0 { break }
            guard let channels = chunk.floatChannelData else { break }
            var windowSumSquares: Double = 0
            var windowSamples: Int = 0
            for ch in 0..<channelCount {
                let ptr = channels[ch]
                for i in 0..<frames {
                    let v = Double(ptr[i])
                    let absV = abs(v)
                    if absV > peak { peak = absV }
                    sumSquares += v * v
                    windowSumSquares += v * v
                    sampleTotal += 1
                    windowSamples += 1
                }
            }
            totalWindows += 1
            let windowRMS = windowSamples > 0 ? (windowSumSquares / Double(windowSamples)).squareRoot() : 0
            if windowRMS < silenceThreshold { silentWindows += 1 }
        }

        let rms = sampleTotal > 0 ? (sumSquares / Double(sampleTotal)).squareRoot() : 0
        let dynamicRange: Double
        if rms > 0 && peak > 0 {
            dynamicRange = min(96, 20 * log10(peak / rms))
        } else {
            dynamicRange = 0
        }
        let silenceRatio = totalWindows > 0 ? Double(silentWindows) / Double(totalWindows) : 1
        let isSilent = peak < silenceThreshold || silenceRatio > 0.9

        return AudioReport(
            durationSeconds: duration,
            sampleRate: sampleRate,
            channelCount: channelCount,
            peakAmplitude: peak,
            rmsAmplitude: rms,
            dynamicRangeDB: dynamicRange,
            isSilent: isSilent,
            silenceRatio: silenceRatio,
            decodedSuccessfully: true
        )
    }

    // MARK: - Video

    struct VideoReport: Equatable {
        var durationSeconds: Double
        var hasVideoTrack: Bool
        var hasAudioTrack: Bool
        var width: Int
        var height: Int
        var frameRate: Double
        var bitrate: Double          // bits/sec, 0 if unknown
        var decodedSuccessfully: Bool

        var isBroken: Bool {
            !decodedSuccessfully || durationSeconds < 0.5 || !hasVideoTrack || width <= 0 || height <= 0
        }
    }

    static func analyseVideo(at url: URL) async -> VideoReport {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        do {
            let duration: CMTime
            let videoTracks: [AVAssetTrack]
            let audioTracks: [AVAssetTrack]
            if #available(iOS 16.0, *) {
                duration = try await asset.load(.duration)
                videoTracks = try await asset.loadTracks(withMediaType: .video)
                audioTracks = try await asset.loadTracks(withMediaType: .audio)
            } else {
                duration = asset.duration
                videoTracks = asset.tracks(withMediaType: .video)
                audioTracks = asset.tracks(withMediaType: .audio)
            }
            let durationSec = CMTimeGetSeconds(duration)
            let durationFinite = durationSec.isFinite ? durationSec : 0

            var width = 0, height = 0
            var frameRate = 0.0
            var bitrate = 0.0

            if let track = videoTracks.first {
                if #available(iOS 16.0, *) {
                    let size = try await track.load(.naturalSize)
                    width = Int(abs(size.width)); height = Int(abs(size.height))
                    frameRate = Double(try await track.load(.nominalFrameRate))
                    bitrate = Double(try await track.load(.estimatedDataRate))
                } else {
                    let size = track.naturalSize
                    width = Int(abs(size.width)); height = Int(abs(size.height))
                    frameRate = Double(track.nominalFrameRate)
                    bitrate = Double(track.estimatedDataRate)
                }
            }

            return VideoReport(
                durationSeconds: durationFinite,
                hasVideoTrack: !videoTracks.isEmpty,
                hasAudioTrack: !audioTracks.isEmpty,
                width: width, height: height,
                frameRate: frameRate, bitrate: bitrate,
                decodedSuccessfully: true
            )
        } catch {
            return VideoReport(durationSeconds: 0, hasVideoTrack: false, hasAudioTrack: false,
                               width: 0, height: 0, frameRate: 0, bitrate: 0,
                               decodedSuccessfully: false)
        }
    }

    // MARK: - Perceptual hashing for cover art

    /// A 64-bit perceptual hash (8x8 greyscale > mean → 1) used for near-
    /// duplicate cover-art detection. Lightweight and stable across resizes /
    /// re-encodes — but **not** a forensic match: a different work with a very
    /// similar layout (centered title on solid background) can collide. We
    /// pair it with Vision feature prints when available.
    struct CoverFingerprint: Equatable {
        /// 64 bits packed into a UInt64 (MSB = first cell).
        var pHash: UInt64
        /// Optional Vision feature-print vector (iOS 13+). Nil on platforms
        /// where the request is unavailable or the data couldn't be processed.
        var visionPrint: Data?
    }

    /// Hamming distance between two pHashes (0…64). Lower = more similar.
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Cosine similarity between two Vision feature-print blobs. Returns nil
    /// when one or both are absent. 1.0 = identical.
    static func featurePrintSimilarity(_ a: Data?, _ b: Data?) -> Double? {
        #if canImport(Vision)
        guard let aData = a, let bData = b else { return nil }
        let aObs = unarchiveFeaturePrint(aData)
        let bObs = unarchiveFeaturePrint(bData)
        guard let aObs, let bObs else { return nil }
        var distance: Float = 0
        do {
            try aObs.computeDistance(&distance, to: bObs)
        } catch {
            return nil
        }
        // computeDistance returns squared Euclidean distance; clamp to 0…1 via
        // 1/(1+d). Good enough as a similarity proxy.
        return 1.0 / (1.0 + Double(distance))
        #else
        return nil
        #endif
    }

    /// Computes a fingerprint for a cover image. Pass the encoded image bytes
    /// (PNG/JPEG/HEIC); we render and downsample on device.
    static func fingerprintCover(_ data: Data) -> CoverFingerprint? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data), let cg = image.cgImage else { return nil }
        let pHash = perceptualHash(from: cg) ?? 0
        let visionPrint = visionFeaturePrint(for: cg)
        return CoverFingerprint(pHash: pHash, visionPrint: visionPrint)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    /// 8x8 mean-greyscale perceptual hash. Same algorithm everyone uses for
    /// near-duplicate image detection — fast, deterministic, stable across
    /// resize/recompression.
    private static func perceptualHash(from cgImage: CGImage) -> UInt64? {
        let size = 8
        let width = size, height = size
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels,
                                      width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let mean = total / pixels.count
        var hash: UInt64 = 0
        for (i, p) in pixels.enumerated() {
            if Int(p) >= mean { hash |= (UInt64(1) << UInt64(63 - i)) }
        }
        return hash
    }

    private static func visionFeaturePrint(for cgImage: CGImage) -> Data? {
        #if canImport(Vision)
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let obs = request.results?.first as? VNFeaturePrintObservation else { return nil }
            return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
    #endif

    #if canImport(Vision)
    private static func unarchiveFeaturePrint(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
    #endif

    // MARK: - Catalogue text similarity

    /// Average pairwise semantic similarity between submission paragraphs and a
    /// reference body of text, using `NLEmbedding.wordEmbedding(for: .english)`.
    /// Returns nil when the on-device embedding isn't available (older OS,
    /// non-English content); the Editor falls back to lexical Jaccard in that
    /// case so we never silently let copies through.
    static func semanticSimilarity(_ submission: String, _ reference: String, maxParagraphs: Int = 6) -> Double? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let subVec = paragraphVector(submission, embedding: embedding, maxParagraphs: maxParagraphs)
        let refVec = paragraphVector(reference, embedding: embedding, maxParagraphs: maxParagraphs)
        guard let s = subVec, let r = refVec else { return nil }
        return cosineSimilarity(s, r)
    }

    private static func paragraphVector(_ text: String, embedding: NLEmbedding, maxParagraphs: Int) -> [Double]? {
        let paragraphs = text
            .split(whereSeparator: { $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 24 }
            .prefix(maxParagraphs)
        guard !paragraphs.isEmpty else {
            return wordsVector(text, embedding: embedding)
        }
        var accum: [Double]?
        var counted = 0
        for p in paragraphs {
            guard let v = wordsVector(p, embedding: embedding) else { continue }
            if accum == nil { accum = v } else {
                for i in 0..<min(accum!.count, v.count) { accum![i] += v[i] }
            }
            counted += 1
        }
        guard var result = accum, counted > 0 else { return nil }
        for i in 0..<result.count { result[i] /= Double(counted) }
        return result
    }

    private static func wordsVector(_ text: String, embedding: NLEmbedding) -> [Double]? {
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        var vec = [Double](repeating: 0, count: embedding.dimension)
        var hits = 0
        for token in tokens {
            if let v = embedding.vector(for: token) {
                for i in 0..<embedding.dimension { vec[i] += v[i] }
                hits += 1
            }
        }
        guard hits > 0 else { return nil }
        for i in 0..<vec.count { vec[i] /= Double(hits) }
        return vec
    }

    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<n { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom > 0 ? dot / denom : 0
    }
}
