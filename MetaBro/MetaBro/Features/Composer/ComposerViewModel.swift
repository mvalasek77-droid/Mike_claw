import SwiftUI

/// Drives the post composer. Loads the Bro-hoods you can post to (your joined
/// communities, plus "Your feed" for a social post) and submits the draft.
@MainActor
@Observable
final class ComposerViewModel {
    enum Phase: Equatable {
        case editing
        case submitting
        case posted
        case failed(String)
    }

    var title: String = ""
    var body: String = ""
    /// nil target = a social post to your own feed.
    var target: Community?
    private(set) var targets: [Community] = []
    private(set) var phase: Phase = .editing

    private let feedService: FeedService
    private let communityService: CommunityService

    init(feedService: FeedService, communityService: CommunityService) {
        self.feedService = feedService
        self.communityService = communityService
    }

    var canSubmit: Bool {
        phase != .submitting &&
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadTargets() async {
        targets = (try? await communityService.discover().filter(\.isJoined)) ?? []
    }

    func submit() async {
        guard canSubmit else { return }
        phase = .submitting
        let draft = PostDraft(title: title, body: body, community: target)
        do {
            _ = try await feedService.createPost(draft)
            phase = .posted
            HapticsEngine.shared.play(.award)
        } catch {
            BroLog.error(error, category: "composer")
            phase = .failed("Couldn't post. Check your connection and try again.")
            HapticsEngine.shared.play(.error)
        }
    }

    /// Reset for another post after a successful submission.
    func reset() {
        title = ""
        body = ""
        target = nil
        phase = .editing
    }
}
