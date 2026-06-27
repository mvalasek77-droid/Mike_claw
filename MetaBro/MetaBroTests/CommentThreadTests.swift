import Testing
import Foundation
@testable import MetaBro

/// Tests the pure tree-flattening logic and the post-detail view model.
@MainActor
struct CommentThreadTests {

    private let postID = UUID()

    // `Comment` is qualified because Swift Testing also exports a `Comment`
    // type, which would otherwise be ambiguous under `import Testing`.
    private func comment(_ id: UUID, parent: UUID?, score: Int = 0) -> MetaBro.Comment {
        MetaBro.Comment(id: id, postID: postID, parentID: parent,
                        author: MockCommentService.defaultMe, body: "x",
                        score: score, createdAt: .now, myVote: .none, isOP: false)
    }

    @Test func flattenOrdersByDepthThenScore() {
        let root = UUID(), childA = UUID(), childB = UUID()
        let comments = [
            comment(root, parent: nil, score: 10),
            comment(childA, parent: root, score: 5),
            comment(childB, parent: root, score: 9), // higher score sorts first
        ]
        let flat = CommentTree.flatten(comments)
        // `map` is rethrows; binding outside #expect avoids the macro treating
        // the call as throwing.
        let ids = flat.map(\.id)
        let depths = flat.map(\.depth)
        #expect(ids == [root, childB, childA])
        #expect(depths == [0, 1, 1])
    }

    @Test func collapsingHidesDescendants() {
        let root = UUID(), child = UUID(), grandchild = UUID()
        let comments = [
            comment(root, parent: nil),
            comment(child, parent: root),
            comment(grandchild, parent: child),
        ]
        let flat = CommentTree.flatten(comments, collapsed: [root])
        let ids = flat.map(\.id)
        #expect(ids == [root])   // child + grandchild hidden
    }

    @Test func loadPopulatesVisibleThread() async {
        let model = PostDetailViewModel(post: MockFeedService.seed()[0],
                                        service: MockCommentService(),
                                        moderationService: MockModerationService())
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.visible.count == 3)
    }

    @Test func replyAppendsComment() async {
        let post = MockFeedService.seed()[0]
        let model = PostDetailViewModel(post: post, service: MockCommentService(),
                                        moderationService: MockModerationService())
        await model.load()
        let before = model.visible.count
        await model.reply(to: nil, body: "Solid advice, bro.")
        #expect(model.visible.count == before + 1)
    }

    @Test func commentVoteIsOptimistic() async {
        let post = MockFeedService.seed()[0]
        let model = PostDetailViewModel(post: post, service: MockCommentService(),
                                        moderationService: MockModerationService())
        await model.load()
        guard let target = model.visible.first?.comment else { Issue.record("no comment"); return }
        let before = target.score
        await model.vote(on: target, value: .up)
        let after = model.visible.first { $0.id == target.id }?.comment.score
        #expect(after == before + 1)
    }
}
