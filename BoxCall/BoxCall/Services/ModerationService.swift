import Foundation
import Combine

/// User-facing report reasons — matches Apple's guidance for
/// user-generated content apps (spam, hate, harassment, self-harm,
/// illegal, other). Report + block are mandatory for App Store
/// approval on any app with a social feed.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, hate, sexual, violence, misinformation, other
    var id: String { rawValue }
    var display: String {
        switch self {
        case .spam:           return "Spam or scam"
        case .harassment:     return "Harassment or bullying"
        case .hate:           return "Hate speech"
        case .sexual:         return "Sexual content"
        case .violence:       return "Violence or threats"
        case .misinformation: return "False or misleading"
        case .other:          return "Something else"
        }
    }
}

/// Report record. In production, this goes to a moderation queue on
/// the backend; here it's persisted locally + suppressed from the feed.
struct ContentReport: Identifiable, Codable, Hashable {
    let id: UUID
    let targetKind: TargetKind
    let targetId: String
    let reason: String     // ReportReason.rawValue
    let note: String?
    let reportedAt: Date

    enum TargetKind: String, Codable, Hashable { case post, comment, review }
}

@MainActor
final class ModerationService: ObservableObject {
    static let shared = ModerationService()

    @Published private(set) var reports: [ContentReport] = []
    @Published private(set) var blockedHandles: Set<String> = []
    @Published private(set) var hiddenPostIds: Set<UUID> = []
    @Published private(set) var hiddenReviewIds: Set<UUID> = []
    @Published private(set) var hiddenCommentIds: Set<UUID> = []

    private let blockedKey = "moderation.blockedHandles"
    private let hiddenPostsKey    = "moderation.hiddenPostIds"
    private let hiddenReviewsKey  = "moderation.hiddenReviewIds"
    private let hiddenCommentsKey = "moderation.hiddenCommentIds"

    private init() {
        blockedHandles = Set((UserDefaults.standard.array(forKey: blockedKey) as? [String]) ?? [])
        hiddenPostIds    = loadUUIDs(hiddenPostsKey)
        hiddenReviewIds  = loadUUIDs(hiddenReviewsKey)
        hiddenCommentIds = loadUUIDs(hiddenCommentsKey)
    }

    // MARK: - Report

    func report(kind: ContentReport.TargetKind, id: String,
                reason: ReportReason, note: String? = nil) {
        let r = ContentReport(id: UUID(), targetKind: kind, targetId: id,
                              reason: reason.rawValue, note: note,
                              reportedAt: Date())
        reports.append(r)
        // Hide from THIS user's view immediately — moderation queue
        // decides whether it stays hidden for everyone.
        switch kind {
        case .post:
            if let uuid = UUID(uuidString: id) { hide(postId: uuid) }
        case .comment:
            if let uuid = UUID(uuidString: id) { hide(commentId: uuid) }
        case .review:
            if let uuid = UUID(uuidString: id) { hide(reviewId: uuid) }
        }
        // TODO: POST to /moderate/report on the backend.
    }

    // MARK: - Block

    func block(handle: String) {
        blockedHandles.insert(handle.lowercased())
        UserDefaults.standard.set(Array(blockedHandles), forKey: blockedKey)
    }

    func unblock(handle: String) {
        blockedHandles.remove(handle.lowercased())
        UserDefaults.standard.set(Array(blockedHandles), forKey: blockedKey)
    }

    func isBlocked(_ handle: String) -> Bool {
        blockedHandles.contains(handle.lowercased())
    }

    // MARK: - Hide (called by report + also usable standalone as "Not interested")

    func hide(postId: UUID) {
        hiddenPostIds.insert(postId)
        saveUUIDs(hiddenPostIds, key: hiddenPostsKey)
    }
    func hide(reviewId: UUID) {
        hiddenReviewIds.insert(reviewId)
        saveUUIDs(hiddenReviewIds, key: hiddenReviewsKey)
    }
    func hide(commentId: UUID) {
        hiddenCommentIds.insert(commentId)
        saveUUIDs(hiddenCommentIds, key: hiddenCommentsKey)
    }

    // MARK: - Filter helpers used by the views

    func filter(feed: [SocialPost]) -> [SocialPost] {
        feed.filter { !isBlocked($0.authorHandle) && !hiddenPostIds.contains($0.id) }
    }
    func filter(reviews: [Review]) -> [Review] {
        reviews.filter { !isBlocked($0.authorHandle) && !hiddenReviewIds.contains($0.id) }
    }
    func filter(comments: [Comment]) -> [Comment] {
        comments.filter { !isBlocked($0.authorHandle) && !hiddenCommentIds.contains($0.id) }
    }

    // MARK: - UserDefaults helpers

    private func loadUUIDs(_ key: String) -> Set<UUID> {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }
    private func saveUUIDs(_ set: Set<UUID>, key: String) {
        UserDefaults.standard.set(set.map(\.uuidString), forKey: key)
    }
}
