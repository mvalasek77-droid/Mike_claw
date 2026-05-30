import Foundation

/// The in-progress work a creator assembles in the KDP-style publishing flow.
///
/// Real-content fields:
///   * `contentURL` — the file the creator picked, opened from `.fileImporter`
///     / PhotosPicker. Used by the AI Editor to actually open and analyse bytes.
///   * `contentData` — for short payloads (cover art, in-app drafts) we can
///     also hold the bytes directly. Persisted with the draft.
///   * `fileName`/`fileSizeMB` — display only; never used for scoring.
///
/// Creator attestation: the publishing flow now requires structured, recorded
/// claims (ownership, prompts, no infringement). These do not *prove* anything
/// on their own — they put a record on the submission and feed the copyright_risk
/// signal so the Editor can flag mismatches.
struct DraftWork: Codable {
    var type: MediaType = .novel
    var title: String = ""
    var subtitle: String = ""
    var creator: String = ""
    var genre: String = ""
    var synopsis: String = ""
    var aiTools: [String] = []
    var customTool: String = ""
    var fileName: String? = nil
    var fileSizeMB: Double = 0
    var length: Int = 0
    var maturity: String = "Everyone"
    var price: Double = 4.99
    /// Cover art (book cover / album cover / film poster), captured as encoded
    /// image data during upload. Required to publish.
    var coverImageData: Data? = nil

    // MARK: - Real content

    /// Local URL of the picked manuscript/master/film. Not persisted across app
    /// launches — security-scoped URLs are session-bound. We keep the bytes in
    /// memory (for novels) via `manuscriptText` so the analysis pipeline can
    /// always re-read them inside the same session.
    var contentURL: URL? = nil
    /// Cached, decoded manuscript text — only populated for novel submissions
    /// (text is small enough to keep around). Audio/video stay file-backed.
    var manuscriptText: String? = nil

    // MARK: - Attestation

    /// Required affirmation that the creator owns the work and the prompts used
    /// to make it. Stored on the submission for auditability.
    var attestOwnsWork: Bool = false
    var attestOwnsPrompts: Bool = false
    var attestNoInfringement: Bool = false
    var attestSignature: String = ""   // typed creator name

    /// Marks a draft as marketplace-house content (Scout-produced). The Editor
    /// uses this to allow text-artifact vetting (lyrics for music, screenplay
    /// for film) when the on-device generator can't produce real audio/video
    /// bytes — without it, music/film would be capped at the missing-content
    /// floor. User submissions stay strict (this flag stays false).
    var isHouseContent: Bool = false

    /// True iff every required affirmation is recorded.
    var hasAttested: Bool {
        attestOwnsWork && attestOwnsPrompts && attestNoInfringement
        && !attestSignature.trimmed.isEmpty
    }

    /// Minimum gate before the work can be sent to the AI Editor.
    var canSubmit: Bool {
        !title.trimmed.isEmpty
        && !creator.trimmed.isEmpty
        && !genre.trimmed.isEmpty
        && synopsis.trimmed.count >= 20
        && !aiTools.isEmpty
        && fileName != nil
        && coverImageData != nil
        && hasAttested
    }

    var contentVerbed: String {
        switch type {
        case .novel: return "manuscript"
        case .music: return "master"
        case .movie: return "film file"
        }
    }

    var coverNoun: String {
        switch type {
        case .novel: return "book cover"
        case .music: return "album cover"
        case .movie: return "film poster"
        }
    }

    // MARK: - Codable

    /// We only persist user-typed metadata and small image data. The
    /// security-scoped URL and full manuscript bytes stay in memory (the
    /// `contentURL` would not be valid across app launches anyway).
    enum CodingKeys: String, CodingKey {
        case type, title, subtitle, creator, genre, synopsis, aiTools, customTool
        case fileName, fileSizeMB, length, maturity, price
        case coverImageData
        case attestOwnsWork, attestOwnsPrompts, attestNoInfringement, attestSignature
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(MediaType.self, forKey: .type) ?? .novel
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        creator = try c.decodeIfPresent(String.self, forKey: .creator) ?? ""
        genre = try c.decodeIfPresent(String.self, forKey: .genre) ?? ""
        synopsis = try c.decodeIfPresent(String.self, forKey: .synopsis) ?? ""
        aiTools = try c.decodeIfPresent([String].self, forKey: .aiTools) ?? []
        customTool = try c.decodeIfPresent(String.self, forKey: .customTool) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        fileSizeMB = try c.decodeIfPresent(Double.self, forKey: .fileSizeMB) ?? 0
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 0
        maturity = try c.decodeIfPresent(String.self, forKey: .maturity) ?? "Everyone"
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 4.99
        coverImageData = try c.decodeIfPresent(Data.self, forKey: .coverImageData)
        attestOwnsWork = try c.decodeIfPresent(Bool.self, forKey: .attestOwnsWork) ?? false
        attestOwnsPrompts = try c.decodeIfPresent(Bool.self, forKey: .attestOwnsPrompts) ?? false
        attestNoInfringement = try c.decodeIfPresent(Bool.self, forKey: .attestNoInfringement) ?? false
        attestSignature = try c.decodeIfPresent(String.self, forKey: .attestSignature) ?? ""
        // contentURL / manuscriptText are session-only, not persisted.
    }

    /// Explicit encode mirroring `init(from:)` so the non-encoded session
    /// fields (`contentURL`, `manuscriptText`) never appear in persisted state.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encode(subtitle, forKey: .subtitle)
        try c.encode(creator, forKey: .creator)
        try c.encode(genre, forKey: .genre)
        try c.encode(synopsis, forKey: .synopsis)
        try c.encode(aiTools, forKey: .aiTools)
        try c.encode(customTool, forKey: .customTool)
        try c.encodeIfPresent(fileName, forKey: .fileName)
        try c.encode(fileSizeMB, forKey: .fileSizeMB)
        try c.encode(length, forKey: .length)
        try c.encode(maturity, forKey: .maturity)
        try c.encode(price, forKey: .price)
        try c.encodeIfPresent(coverImageData, forKey: .coverImageData)
        try c.encode(attestOwnsWork, forKey: .attestOwnsWork)
        try c.encode(attestOwnsPrompts, forKey: .attestOwnsPrompts)
        try c.encode(attestNoInfringement, forKey: .attestNoInfringement)
        try c.encode(attestSignature, forKey: .attestSignature)
    }
}

/// One scored dimension in the AI Editor's report.
struct CriterionScore: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let score: Int
    let note: String
}

/// The AI Editor's verdict on a submission.
struct AIReviewResult: Identifiable, Hashable, Codable {
    var id = UUID()
    let overall: Int
    let criteria: [CriterionScore]
    let strengths: [String]
    let improvements: [String]
    let summary: String
    /// How confident the AI Editor is in its own verdict, 0–100. Drives whether
    /// it will act autonomously.
    let confidence: Int
    /// Plain-language explanation of the autonomous publishing decision.
    let autonomousRationale: String

    // MARK: - New honest sub-scores

    /// 0…100. Measured against actual content bytes (text/audio/video). Hard
    /// floor for AI Autopilot.
    var contentQuality: Int = 0
    /// 0…1. Highest semantic-or-Hamming similarity to any catalogue title.
    /// Higher = more derivative; copycats are rejected at the threshold.
    var copycatSimilarity: Double = 0
    /// Title of the closest existing work (or "" if none above the floor).
    var copycatNeighbour: String = ""
    /// 0…100. Aggregated copyright-risk signal (famous IP names, lorem-ipsum
    /// overlap, attestation gaps, perceptual-hash collisions). 0 is best.
    var copyrightRisk: Int = 0

    /// Tolerant decode so reviews persisted before the sub-scores existed
    /// still load (the missing fields default to 0 / empty).
    init(id: UUID = UUID(), overall: Int, criteria: [CriterionScore],
         strengths: [String], improvements: [String], summary: String,
         confidence: Int, autonomousRationale: String,
         contentQuality: Int = 0, copycatSimilarity: Double = 0,
         copycatNeighbour: String = "", copyrightRisk: Int = 0) {
        self.id = id
        self.overall = overall
        self.criteria = criteria
        self.strengths = strengths
        self.improvements = improvements
        self.summary = summary
        self.confidence = confidence
        self.autonomousRationale = autonomousRationale
        self.contentQuality = contentQuality
        self.copycatSimilarity = copycatSimilarity
        self.copycatNeighbour = copycatNeighbour
        self.copyrightRisk = copyrightRisk
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        overall = try c.decode(Int.self, forKey: .overall)
        criteria = try c.decodeIfPresent([CriterionScore].self, forKey: .criteria) ?? []
        strengths = try c.decodeIfPresent([String].self, forKey: .strengths) ?? []
        improvements = try c.decodeIfPresent([String].self, forKey: .improvements) ?? []
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        confidence = try c.decodeIfPresent(Int.self, forKey: .confidence) ?? 0
        autonomousRationale = try c.decodeIfPresent(String.self, forKey: .autonomousRationale) ?? ""
        contentQuality = try c.decodeIfPresent(Int.self, forKey: .contentQuality) ?? 0
        copycatSimilarity = try c.decodeIfPresent(Double.self, forKey: .copycatSimilarity) ?? 0
        copycatNeighbour = try c.decodeIfPresent(String.self, forKey: .copycatNeighbour) ?? ""
        copyrightRisk = try c.decodeIfPresent(Int.self, forKey: .copyrightRisk) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, overall, criteria, strengths, improvements, summary, confidence, autonomousRationale
        case contentQuality, copycatSimilarity, copycatNeighbour, copyrightRisk
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(overall, forKey: .overall)
        try c.encode(criteria, forKey: .criteria)
        try c.encode(strengths, forKey: .strengths)
        try c.encode(improvements, forKey: .improvements)
        try c.encode(summary, forKey: .summary)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(autonomousRationale, forKey: .autonomousRationale)
        try c.encode(contentQuality, forKey: .contentQuality)
        try c.encode(copycatSimilarity, forKey: .copycatSimilarity)
        try c.encode(copycatNeighbour, forKey: .copycatNeighbour)
        try c.encode(copyrightRisk, forKey: .copyrightRisk)
    }

    static let threshold = 85
    /// Minimum self-confidence before the AI Editor will publish on its own.
    static let autoPublishConfidence = 80

    // MARK: - Autopilot guards

    /// Hard floor on the *content* signal before Autopilot can publish on its
    /// own. A polished synopsis + great cover can no longer carry a thin
    /// manuscript over the line autonomously.
    static let autoPublishContentFloor = 80
    /// Maximum allowed catalogue similarity for Autopilot to publish.
    static let autoPublishCopycatCeiling = 0.32
    /// Maximum allowed copyright_risk for Autopilot to publish.
    static let autoPublishCopyrightCeiling = 35

    /// Threshold above which a submission is rejected as a copycat. Tighter
    /// than the old setting: semantic matching is more sensitive than Jaccard.
    static let copycatRejectionThreshold = 0.35

    var passed: Bool { overall >= AIReviewResult.threshold }

    /// Whether the AI Editor, acting on its own judgement, elects to publish.
    /// All of the following must hold:
    ///   * Overall passes the 85% bar.
    ///   * Confidence is high enough to stand behind unaided.
    ///   * **Content quality** clears the autopilot floor (real bytes!).
    ///   * Catalogue similarity is below the autopilot ceiling.
    ///   * Copyright risk is below the autopilot ceiling.
    /// Any single failure forces the verdict back to the human, regardless of
    /// the overall score.
    var aiChoosesToPublish: Bool {
        passed
        && confidence >= AIReviewResult.autoPublishConfidence
        && contentQuality >= AIReviewResult.autoPublishContentFloor
        && copycatSimilarity <= AIReviewResult.autoPublishCopycatCeiling
        && copyrightRisk <= AIReviewResult.autoPublishCopyrightCeiling
    }
}

enum SubmissionStatus: String, Codable {
    case draft = "Draft"
    case reviewing = "In Review"
    case accepted = "Live"
    case rejected = "Needs Work"
}

/// A creator's title as it moves through the publishing pipeline.
struct Submission: Identifiable, Codable {
    var id = UUID()
    var draft: DraftWork
    var status: SubmissionStatus
    var review: AIReviewResult?
    /// The live `MediaItem.id` once accepted and pushed to the marketplace.
    var publishedItemID: UUID?
    var submittedAt: Date = .now

    var title: String { draft.title.isEmpty ? "Untitled \(draft.type.title)" : draft.title }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
