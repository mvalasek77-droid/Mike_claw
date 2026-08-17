import Testing
import Foundation
@testable import MetaBro

@MainActor
struct ComposerViewModelTests {

    private func make() -> ComposerViewModel {
        ComposerViewModel(feedService: MockFeedService(),
                          communityService: MockCommunityService())
    }

    @Test func cannotSubmitEmptyBody() {
        let model = make()
        #expect(!model.canSubmit)
        model.body = "   "
        #expect(!model.canSubmit)
        model.body = "Real content"
        #expect(model.canSubmit)
    }

    @Test func loadsOnlyJoinedCommunitiesAsTargets() async {
        let model = make()
        await model.loadTargets()
        #expect(!model.targets.isEmpty)
        let allJoined = model.targets.allSatisfy(\.isJoined)
        #expect(allJoined)
    }

    @Test func successfulSubmitMovesToPostedAndAppearsInFeed() async {
        let feed = MockFeedService()
        let model = ComposerViewModel(feedService: feed,
                                      communityService: MockCommunityService())
        model.body = "Bench PR today, bros."
        await model.submit()
        #expect(model.phase == .posted)

        // The new post is now the freshest item in the shared feed.
        let page = try? await feed.feed(sort: .new, cursor: nil)
        #expect(page?.posts.first?.body == "Bench PR today, bros.")
        #expect(page?.posts.first?.author.id == Session.me.id)
    }

    @Test func resetClearsDraft() {
        let model = make()
        model.title = "t"; model.body = "b"
        model.reset()
        #expect(model.title.isEmpty)
        #expect(model.body.isEmpty)
        #expect(model.phase == .editing)
    }
}
