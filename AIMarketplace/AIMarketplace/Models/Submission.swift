import Foundation

/// The in-progress work a creator assembles in the KDP-style publishing flow.
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

    /// Minimum gate before the work can be sent to the AI Editor.
    var canSubmit: Bool {
        !title.trimmed.isEmpty
        && !creator.trimmed.isEmpty
        && !genre.trimmed.isEmpty
        && synopsis.trimmed.count >= 20
        && !aiTools.isEmpty
        && fileName != nil
        && coverImageData != nil
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

    static let threshold = 85
    var passed: Bool { overall >= AIReviewResult.threshold }
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
