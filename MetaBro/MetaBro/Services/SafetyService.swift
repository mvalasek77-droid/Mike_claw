import Foundation

/// Cross-cutting safety actions available on every post, comment, profile, and
/// DM: report into the mod queue, block (hides their content + ends DMs), and
/// mute (hides their content without them knowing). Distinct from
/// `ModerationService`, which is what community mods use to triage reports.
protocol SafetyService: Sendable {
    func report(kind: ReportedContentKind, targetID: UUID, preview: String,
                reportedUser: User, community: Community?,
                reason: ReportReason, details: String?) async throws
    func block(_ user: User) async throws
    func unblock(_ user: User) async throws
    func blockedUsers() async throws -> [User]
    func mute(_ user: User) async throws
    func unmute(_ user: User) async throws
    func mutedUsers() async throws -> [User]
}

extension SafetyService {
    func isBlocked(_ user: User) async -> Bool {
        (try? await blockedUsers().contains(user)) ?? false
    }

    func isMuted(_ user: User) async -> Bool {
        (try? await mutedUsers().contains(user)) ?? false
    }
}

/// Deterministic in-memory safety state for previews, tests, and offline demo.
actor MockSafetyService: SafetyService {
    private var reports: [Report] = []
    private var blocked: Set<UUID> = []
    private var muted: Set<UUID> = []
    private var blockedUsersByID: [UUID: User] = [:]
    private var mutedUsersByID: [UUID: User] = [:]

    func report(kind: ReportedContentKind, targetID: UUID, preview: String,
                reportedUser: User, community: Community?,
                reason: ReportReason, details: String?) async throws {
        let report = Report(
            id: UUID(), kind: kind, targetID: targetID, preview: preview,
            reportedUser: reportedUser, community: community, reason: reason,
            details: details, createdAt: .now, status: .pending
        )
        reports.append(report)
    }

    func block(_ user: User) async throws {
        blocked.insert(user.id)
        blockedUsersByID[user.id] = user
    }

    func unblock(_ user: User) async throws {
        blocked.remove(user.id)
        blockedUsersByID[user.id] = nil
    }

    func blockedUsers() async throws -> [User] {
        blocked.compactMap { blockedUsersByID[$0] }
    }

    func mute(_ user: User) async throws {
        muted.insert(user.id)
        mutedUsersByID[user.id] = user
    }

    func unmute(_ user: User) async throws {
        muted.remove(user.id)
        mutedUsersByID[user.id] = nil
    }

    func mutedUsers() async throws -> [User] {
        muted.compactMap { mutedUsersByID[$0] }
    }

    /// Test/inspection hook — the queue a `ModerationService` would read from
    /// in a backend where reports flow straight into mod tooling.
    func allReports() -> [Report] { reports }
}
