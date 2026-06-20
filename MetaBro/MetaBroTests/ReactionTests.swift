import Testing
import Foundation
@testable import MetaBro

/// Tests the pure reaction math and the feed view model's optimistic reacting.
@MainActor
struct ReactionTests {

    @Test func applyingReactionSetsMineAndIncrementsCount() {
        var summary = ReactionSummary.empty
        summary.apply(.strong)
        #expect(summary.mine == .strong)
        #expect(summary.counts[.strong] == 1)
        #expect(summary.total == 1)
    }

    @Test func switchingReactionMovesTheCount() {
        var summary = ReactionSummary(counts: [.respect: 5], mine: .respect)
        summary.apply(.lol)
        #expect(summary.mine == .lol)
        #expect(summary.counts[.respect] == 4)
        #expect(summary.counts[.lol] == 1)
    }

    @Test func tappingCurrentReactionClearsIt() {
        var summary = ReactionSummary(counts: [.strong: 1], mine: .strong)
        summary.apply(.strong)         // tap the one you already have
        #expect(summary.mine == nil)
        #expect(summary.counts[.strong] == nil) // count removed, not left at 0
        #expect(summary.total == 0)
    }

    @Test func topReturnsReactionsByCountDescending() {
        let summary = ReactionSummary(counts: [.respect: 9, .strong: 14, .lol: 3], mine: nil)
        #expect(summary.top == [.strong, .respect, .lol])
    }

    @Test func feedReactIsOptimisticOnSocialPost() async {
        let model = FeedViewModel(service: MockFeedService())
        await model.load()
        guard case .loaded(let posts) = model.state,
              let social = posts.first(where: { $0.origin == .social }) else {
            Issue.record("no social post"); return
        }
        let before = social.reactions.total
        await model.react(on: social, reaction: .strong)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == social.id }) else {
            Issue.record("post vanished"); return
        }
        #expect(updated.reactions.mine == .strong)
        #expect(updated.reactions.total == before + 1)
    }
}
