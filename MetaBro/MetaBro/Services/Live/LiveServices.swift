import Foundation
import UserNotifications

// Backend-backed implementations of the remaining services. The Comment,
// Community, Message, Conversation, and Story models are already clean Codable
// types, so these decode straight into the domain — no DTO layer required.

struct LiveAuthService: AuthService {
    let client: APIClient

    func restoreSession() async -> User? {
        try? await client.send(API.session, as: User.self)
    }

    func completeOnboarding(_ draft: OnboardingDraft) async throws -> User {
        let req = OnboardRequest(handle: draft.handle, displayName: draft.displayName)
        return try await client.send(API.onboard(req), as: User.self)
    }

    func signOut() async {
        try? await client.send(API.signOut)
    }
}

struct LiveCommentService: CommentService {
    let client: APIClient

    func comments(for postID: UUID) async throws -> [Comment] {
        try await client.send(API.comments(postID: postID), as: [Comment].self)
    }

    func vote(commentID: UUID, value: VoteValue) async throws {
        try await client.send(API.voteComment(id: commentID, .init(value: value.rawValue)))
    }

    func reply(to postID: UUID, parentID: UUID?, body: String) async throws -> Comment {
        let req = ReplyRequest(postID: postID, parentID: parentID, body: body)
        return try await client.send(API.reply(req), as: Comment.self)
    }
}

struct LiveCommunityService: CommunityService {
    let client: APIClient

    func discover() async throws -> [Community] {
        try await client.send(API.discover, as: [Community].self)
    }

    func setMembership(communityID: UUID, joined: Bool) async throws {
        try await client.send(API.membership(communityID: communityID, joined: joined))
    }
}

struct LiveMessagingService: MessagingService {
    let client: APIClient

    func conversations() async throws -> [Conversation] {
        try await client.send(API.conversations, as: [Conversation].self)
    }

    func messages(in conversationID: UUID) async throws -> [Message] {
        try await client.send(API.messages(conversationID: conversationID), as: [Message].self)
    }

    func send(_ message: Message, to conversationID: UUID) async throws {
        let req = SendMessageRequest(id: message.id, text: message.text, voiceNoteDuration: message.voiceNoteDuration)
        try await client.send(API.sendMessage(conversationID: conversationID, req))
    }

    func autoReply(to conversationID: UUID) async throws -> Message? {
        // Real replies arrive over the wire (push/websocket); nothing to fake.
        nil
    }

    func markRead(_ conversationID: UUID) async throws {
        try await client.send(API.readConversation(id: conversationID))
    }
}

struct LiveStoryService: StoryService {
    let client: APIClient

    func stories() async throws -> [Story] {
        try await client.send(API.stories, as: [Story].self)
    }

    func markSeen(_ id: UUID) async throws {
        try await client.send(API.seenStory(id: id))
    }
}

struct LiveFriendsService: FriendsService {
    let client: APIClient

    func friends() async throws -> [User] {
        try await client.send(API.friends, as: [User].self)
    }

    func incomingRequests() async throws -> [User] {
        try await client.send(API.friendRequests(direction: .incoming), as: [User].self)
    }

    func outgoingRequests() async throws -> [User] {
        try await client.send(API.friendRequests(direction: .outgoing), as: [User].self)
    }

    func suggestions() async throws -> [User] {
        try await client.send(API.friendSuggestions, as: [User].self)
    }

    func sendRequest(to user: User) async throws {
        try await client.send(API.sendFriendRequest(userID: user.id))
    }

    func acceptRequest(from user: User) async throws {
        try await client.send(API.respondFriendRequest(userID: user.id, accept: true))
    }

    func declineRequest(from user: User) async throws {
        try await client.send(API.respondFriendRequest(userID: user.id, accept: false))
    }

    func unfriend(_ user: User) async throws {
        try await client.send(API.unfriend(userID: user.id))
    }
}

struct LiveNotificationsService: NotificationsService {
    let client: APIClient

    func notifications() async throws -> [AppNotification] {
        try await client.send(API.notifications, as: [AppNotification].self)
    }

    func markRead(_ id: UUID) async throws {
        try await client.send(API.markNotificationRead(id: id))
    }

    func markAllRead() async throws {
        try await client.send(API.markAllNotificationsRead())
    }
}

struct LiveSafetyService: SafetyService {
    let client: APIClient

    func report(kind: ReportedContentKind, targetID: UUID, preview: String,
                reportedUser: User, community: Community?,
                reason: ReportReason, details: String?) async throws {
        let req = ReportRequest(kind: kind.rawValue, targetID: targetID,
                                 reason: reason.rawValue, details: details)
        try await client.send(API.report(req))
    }

    func block(_ user: User) async throws {
        try await client.send(API.block(userID: user.id))
    }

    func unblock(_ user: User) async throws {
        try await client.send(API.unblock(userID: user.id))
    }

    func blockedUsers() async throws -> [User] {
        try await client.send(API.blockedUsers, as: [User].self)
    }

    func mute(_ user: User) async throws {
        try await client.send(API.mute(userID: user.id))
    }

    func unmute(_ user: User) async throws {
        try await client.send(API.unmute(userID: user.id))
    }

    func mutedUsers() async throws -> [User] {
        try await client.send(API.mutedUsers, as: [User].self)
    }
}

struct LiveModerationService: ModerationService {
    let client: APIClient

    func queue() async throws -> [Report] {
        try await client.send(API.modQueue, as: [Report].self)
    }

    func approve(_ report: Report) async throws {
        try await client.send(API.approveReport(id: report.id))
    }

    func remove(_ report: Report) async throws {
        try await client.send(API.removeReport(id: report.id))
    }

    func pin(postID: UUID) async throws {
        try await client.send(API.pinPost(id: postID))
    }

    func unpin(postID: UUID) async throws {
        try await client.send(API.unpinPost(id: postID))
    }

    func lock(postID: UUID) async throws {
        try await client.send(API.lockPost(id: postID))
    }

    func unlock(postID: UUID) async throws {
        try await client.send(API.unlockPost(id: postID))
    }

    func ban(_ user: User, from community: Community) async throws {
        try await client.send(API.banUser(BanRequest(userID: user.id, communityID: community.id)))
    }
}

struct LivePushNotificationService: PushNotificationService {
    let client: APIClient

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            BroLog.error(error, category: "push")
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func registerDeviceToken(_ token: String) async throws {
        try await client.send(API.registerDeviceToken(DeviceTokenRequest(token: token)))
    }
}

struct LiveBugReportService: BugReportService {
    let client: APIClient

    func diagnostics() async -> DeviceDiagnostics {
        await Self.currentDiagnostics()
    }

    func submit(_ draft: BugReportDraft) async throws {
        let diag = await diagnostics()
        let req = BugReportRequest(
            summary: draft.summary,
            details: draft.details,
            severity: draft.severity.rawValue,
            appVersion: diag.appVersion,
            buildNumber: diag.buildNumber,
            osVersion: diag.osVersion,
            deviceModel: diag.deviceModel,
            locale: diag.locale,
            logs: draft.includeDiagnostics ? diag.recentLogs : nil
        )
        try await client.send(API.bugReport(req))
    }
}
