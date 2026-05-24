import Foundation

/// Royalty plans, mirroring KDP's 35% / 70% split choices.
enum RoyaltyPlan: String, CaseIterable, Identifiable {
    case standard = "35%"
    case premium = "70%"
    var id: String { rawValue }

    var rate: Double { self == .standard ? 0.35 : 0.70 }
    var blurb: String {
        switch self {
        case .standard: return "Available at any list price. No delivery fee."
        case .premium: return "Best for $2.99–$9.99 titles. Higher payout per sale."
        }
    }
}

/// The in-progress work a creator assembles in the KDP-style publishing flow.
struct DraftWork {
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
    var royalty: RoyaltyPlan = .premium

    /// Minimum gate before the work can even be sent to the AI Editor.
    var canSubmit: Bool {
        !title.trimmed.isEmpty
        && !creator.trimmed.isEmpty
        && !genre.trimmed.isEmpty
        && synopsis.trimmed.count >= 20
        && !aiTools.isEmpty
        && fileName != nil
    }

    var contentVerbed: String {
        switch type {
        case .novel: return "manuscript"
        case .music: return "master"
        case .movie: return "film file"
        }
    }
}

/// One scored dimension in the AI Editor's report.
struct CriterionScore: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let score: Int
    let note: String
}

/// The AI Editor's verdict on a submission.
struct AIReviewResult: Identifiable, Hashable {
    let id = UUID()
    let overall: Int
    let criteria: [CriterionScore]
    let strengths: [String]
    let improvements: [String]
    let summary: String

    static let threshold = 85
    var passed: Bool { overall >= AIReviewResult.threshold }
}

enum SubmissionStatus: String {
    case draft = "Draft"
    case reviewing = "In Review"
    case accepted = "Live"
    case rejected = "Needs Work"
}

/// A creator's title as it moves through the publishing pipeline.
struct Submission: Identifiable {
    let id = UUID()
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
