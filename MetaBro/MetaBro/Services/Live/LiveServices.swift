import Foundation

// Backend-backed implementations of the remaining services. The Comment,
// Community, Message, Conversation, and Story models are already clean Codable
// types, so these decode straight into the domain — no DTO layer required.

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
        let req = SendMessageRequest(id: message.id, text: message.text)
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
