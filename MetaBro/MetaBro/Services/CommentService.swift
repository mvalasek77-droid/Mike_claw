import Foundation

protocol CommentService: Sendable {
    func comments(for postID: UUID) async throws -> [Comment]
    func vote(commentID: UUID, value: VoteValue) async throws
    func reply(to postID: UUID, parentID: UUID?, body: String) async throws -> Comment
}

/// Deterministic in-memory comments for previews, tests, and offline demo.
actor MockCommentService: CommentService {
    private var byPost: [UUID: [Comment]]
    private let me: User

    init(seed: [UUID: [Comment]] = [:], me: User = MockCommentService.defaultMe) {
        self.byPost = seed
        self.me = me
    }

    func comments(for postID: UUID) async throws -> [Comment] {
        try await Task.sleep(nanoseconds: 200_000_000)
        // Seed and persist on first access so later votes/replies are consistent.
        if let existing = byPost[postID] { return existing }
        let seeded = Self.tree(for: postID)
        byPost[postID] = seeded
        return seeded
    }

    func vote(commentID: UUID, value: VoteValue) async throws {
        for (postID, var list) in byPost {
            guard let idx = list.firstIndex(where: { $0.id == commentID }) else { continue }
            list[idx].score += value.rawValue - list[idx].myVote.rawValue
            list[idx].myVote = value
            byPost[postID] = list
            return
        }
    }

    func reply(to postID: UUID, parentID: UUID?, body: String) async throws -> Comment {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.server(status: 422) }
        let comment = Comment(
            id: UUID(), postID: postID, parentID: parentID, author: me,
            body: trimmed, score: 1, createdAt: .now, myVote: .up, isOP: false
        )
        byPost[postID, default: []].append(comment)
        return comment
    }

    static let defaultMe = User(id: UUID(), handle: "@you", displayName: "You",
                                avatarURL: nil, broCred: 12)

    /// A small sample thread: top-level comment with two nested replies.
    static func tree(for postID: UUID) -> [Comment] {
        let coach = User(id: UUID(), handle: "@coachdave", displayName: "Dave",
                         avatarURL: nil, broCred: 9_300)
        let rookie = User(id: UUID(), handle: "@newbro", displayName: "Sam",
                          avatarURL: nil, broCred: 40)
        let root = Comment(id: UUID(), postID: postID, parentID: nil, author: coach,
                           body: "Bands before barbell. Two sets of 15 and your shoulders will thank you.",
                           score: 214, createdAt: .now.addingTimeInterval(-1_800),
                           myVote: .none, isOP: false)
        let reply1 = Comment(id: UUID(), postID: postID, parentID: root.id, author: rookie,
                             body: "Which bands? Light or heavy?",
                             score: 33, createdAt: .now.addingTimeInterval(-1_500),
                             myVote: .none, isOP: false)
        let reply2 = Comment(id: UUID(), postID: postID, parentID: reply1.id, author: coach,
                             body: "Light. You're warming up, not maxing out.",
                             score: 58, createdAt: .now.addingTimeInterval(-1_200),
                             myVote: .none, isOP: false)
        return [root, reply1, reply2]
    }
}

/// Builds a display-ready, depth-annotated list from flat comments, honoring a
/// set of collapsed parent IDs (whose descendants are hidden). Pure + testable.
enum CommentTree {
    static func flatten(
        _ comments: [Comment],
        collapsed: Set<UUID> = []
    ) -> [ThreadedComment] {
        let childrenByParent = Dictionary(grouping: comments, by: { $0.parentID })
        var result: [ThreadedComment] = []

        func visit(parent: UUID?, depth: Int) {
            let children = (childrenByParent[parent] ?? [])
                .sorted { $0.score > $1.score }
            for child in children {
                result.append(ThreadedComment(comment: child, depth: depth))
                if !collapsed.contains(child.id) {
                    visit(parent: child.id, depth: depth + 1)
                }
            }
        }
        visit(parent: nil, depth: 0)
        return result
    }
}
