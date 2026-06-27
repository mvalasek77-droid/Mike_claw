import Testing
import Foundation
@testable import MetaBro

@MainActor
struct StoriesAndAwardsTests {

    // MARK: Stories

    @Test func storiesLoadUnseenFirst() async {
        let model = StoriesViewModel(service: MockStoryService())
        await model.load()
        #expect(model.stories.count == 3)
        // Unseen stories sort ahead of seen ones.
        let firstSeenIndex = model.stories.firstIndex(where: \.seen) ?? model.stories.count
        let lastUnseenIndex = model.stories.lastIndex(where: { !$0.seen }) ?? -1
        #expect(lastUnseenIndex < firstSeenIndex)
    }

    @Test func markSeenFlipsTheFlag() async {
        let model = StoriesViewModel(service: MockStoryService())
        await model.load()
        guard let unseen = model.stories.first(where: { !$0.seen }) else {
            Issue.record("no unseen story"); return
        }
        await model.markSeen(unseen.id)
        let updated = model.stories.first { $0.id == unseen.id }
        #expect(updated?.seen == true)
    }

    // MARK: Awards

    @Test func awardCountSumsAllKinds() {
        var post = MockFeedService.seed().first { $0.origin == .community }!
        post.awards = [.champ: 1, .bigBrain: 2]
        #expect(post.awardCount == 3)
    }

    @Test func feedGiveAwardIsOptimistic() async {
        let service = MockFeedService()
        let model = FeedViewModel(service: service,
                                  savedService: MockSavedService(feedService: service),
                                  historyService: MockHistoryService())
        await model.load()
        guard case .loaded(let posts) = model.state, let target = posts.first else {
            Issue.record("no posts"); return
        }
        let before = target.awardCount
        await model.giveAward(on: target, award: .solid)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == target.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.awardCount == before + 1)
        #expect(updated.awards[.solid] == (target.awards[.solid] ?? 0) + 1)
    }

    @Test func awardKindsHaveDistinctCosts() {
        let costs = Set(AwardKind.allCases.map(\.cost))
        #expect(costs.count == AwardKind.allCases.count)
    }
}
