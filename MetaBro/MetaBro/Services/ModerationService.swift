import Foundation

/// Community-mod tooling: triage the report queue, remove/approve flagged
/// content, pin/lock posts, and ban repeat offenders. Gated in the UI by
/// `Community.isModerator`.
protocol ModerationService: Sendable {
    /// Pending reports across every Bro-hood the current user moderates.
    func queue() async throws -> [Report]
    func approve(_ report: Report) async throws
    func remove(_ report: Report) async throws
    func pin(postID: UUID) async throws
    func unpin(postID: UUID) async throws
    func lock(postID: UUID) async throws
    func unlock(postID: UUID) async throws
    func ban(_ user: User, from community: Community) async throws
}

/// Deterministic in-memory mod queue for previews, tests, and offline demo.
actor MockModerationService: ModerationService {
    private var reports: [Report]
    private(set) var bannedUsers: Set<UUID> = []
    private(set) var pinnedPostIDs: Set<UUID> = []
    private(set) var lockedPostIDs: Set<UUID> = []

    init(reports: [Report] = MockModerationService.seed()) {
        self.reports = reports
    }

    func queue() async throws -> [Report] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return reports.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    func approve(_ report: Report) async throws {
        guard let idx = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[idx].status = .approved
    }

    func remove(_ report: Report) async throws {
        guard let idx = reports.firstIndex(where: { $0.id == report.id }) else { return }
        reports[idx].status = .removed
    }

    func pin(postID: UUID) async throws { pinnedPostIDs.insert(postID) }
    func unpin(postID: UUID) async throws { pinnedPostIDs.remove(postID) }
    func lock(postID: UUID) async throws { lockedPostIDs.insert(postID) }
    func unlock(postID: UUID) async throws { lockedPostIDs.remove(postID) }

    func ban(_ user: User, from community: Community) async throws {
        bannedUsers.insert(user.id)
    }

    /// A simple keyword automod: anything matching this list arrives in the
    /// queue pre-flagged as spam, the way a real automod rule would file it
    /// before a human ever sees it.
    private static let bannedKeywords = ["buy followers", "click here", "free crypto"]

    static func automodFlag(for text: String) -> Bool {
        let lowered = text.lowercased()
        return bannedKeywords.contains { lowered.contains($0) }
    }

    static func seed() -> [Report] {
        let fitness = Community(id: UUID(), name: "Iron Bro-hood", slug: "fitness",
                                memberCount: 182_000, iconURL: nil, isJoined: true, isModerator: true)
        let spammer = User(id: UUID(), handle: "@gainz_bot", displayName: "GainzBot",
                           avatarURL: nil, broCred: 2)
        let heated = User(id: UUID(), handle: "@hotmic", displayName: "Hot Mic",
                          avatarURL: nil, broCred: 410)
        return [
            Report(id: UUID(), kind: .post, targetID: UUID(),
                   preview: "Buy followers fast, link in bio 🔥",
                   reportedUser: spammer, community: fitness,
                   reason: .spam, details: nil,
                   createdAt: .now.addingTimeInterval(-900), status: .pending),
            Report(id: UUID(), kind: .comment, targetID: UUID(),
                   preview: "You don't even lift, get out of this Bro-hood",
                   reportedUser: heated, community: fitness,
                   reason: .harassment, details: "Targeting a new member repeatedly.",
                   createdAt: .now.addingTimeInterval(-3_600), status: .pending),
        ]
    }
}
