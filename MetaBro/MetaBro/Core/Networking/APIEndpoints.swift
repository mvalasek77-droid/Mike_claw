import Foundation

/// Single place that documents and builds every backend route MetaBro calls.
/// Keeping these here (rather than inline in services) makes the API contract
/// reviewable in one file and trivial to repoint.
enum API {

    // MARK: Auth
    static let session = Endpoint.get("auth/session")
    static func onboard(_ body: OnboardRequest) throws -> Endpoint {
        try .post("auth/onboard", body: body)
    }
    static let signOut = Endpoint.delete("auth/session")

    // MARK: Feed & posts
    static func feed(sort: FeedSort, cursor: String?) -> Endpoint {
        var q = [URLQueryItem(name: "sort", value: sort.rawValue)]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        return .get("feed", query: q)
    }
    static func createPost(_ body: CreatePostRequest) throws -> Endpoint {
        try .post("posts", body: body)
    }
    static func postsByUser(_ userID: UUID) -> Endpoint {
        .get("users/\(userID.uuidString)/posts")
    }
    static func vote(postID: UUID, _ body: VoteRequest) throws -> Endpoint {
        try .post("posts/\(postID.uuidString)/vote", body: body)
    }
    static func react(postID: UUID, _ body: ReactRequest) throws -> Endpoint {
        try .post("posts/\(postID.uuidString)/reaction", body: body)
    }
    static func award(postID: UUID, _ body: AwardRequest) throws -> Endpoint {
        try .post("posts/\(postID.uuidString)/awards", body: body)
    }

    // MARK: Comments
    static func comments(postID: UUID) -> Endpoint {
        .get("posts/\(postID.uuidString)/comments")
    }
    static func voteComment(id: UUID, _ body: VoteRequest) throws -> Endpoint {
        try .post("comments/\(id.uuidString)/vote", body: body)
    }
    static func reply(_ body: ReplyRequest) throws -> Endpoint {
        try .post("comments", body: body)
    }

    // MARK: Communities
    static let discover = Endpoint.get("communities")
    static func membership(communityID: UUID, joined: Bool) throws -> Endpoint {
        let path = "communities/\(communityID.uuidString)/membership"
        return joined ? try .post(path) : .delete(path)
    }

    // MARK: Messaging
    static let conversations = Endpoint.get("conversations")
    static func messages(conversationID: UUID) -> Endpoint {
        .get("conversations/\(conversationID.uuidString)/messages")
    }
    static func sendMessage(conversationID: UUID, _ body: SendMessageRequest) throws -> Endpoint {
        try .post("conversations/\(conversationID.uuidString)/messages", body: body)
    }
    static func readConversation(id: UUID) throws -> Endpoint {
        try .post("conversations/\(id.uuidString)/read")
    }

    // MARK: Stories
    static let stories = Endpoint.get("stories")
    static func seenStory(id: UUID) throws -> Endpoint {
        try .post("stories/\(id.uuidString)/seen")
    }

    // MARK: Bug reports
    static func bugReport(_ body: BugReportRequest) throws -> Endpoint {
        try .post("bug-reports", body: body)
    }

    // MARK: Friends
    enum FriendRequestDirection: String { case incoming, outgoing }
    static let friends = Endpoint.get("friends")
    static func friendRequests(direction: FriendRequestDirection) -> Endpoint {
        .get("friends/requests", query: [URLQueryItem(name: "direction", value: direction.rawValue)])
    }
    static let friendSuggestions = Endpoint.get("friends/suggestions")
    static func sendFriendRequest(userID: UUID) throws -> Endpoint {
        try .post("friends/requests/\(userID.uuidString)")
    }
    static func respondFriendRequest(userID: UUID, accept: Bool) throws -> Endpoint {
        try .post("friends/requests/\(userID.uuidString)/respond", body: RespondFriendRequest(accept: accept))
    }
    static func unfriend(userID: UUID) -> Endpoint {
        .delete("friends/\(userID.uuidString)")
    }

    // MARK: Notifications
    static let notifications = Endpoint.get("notifications")
    static func markNotificationRead(id: UUID) throws -> Endpoint {
        try .post("notifications/\(id.uuidString)/read")
    }
    static func markAllNotificationsRead() throws -> Endpoint {
        try .post("notifications/read-all")
    }

    // MARK: Push
    static func registerDeviceToken(_ body: DeviceTokenRequest) throws -> Endpoint {
        try .post("push/device-tokens", body: body)
    }

    // MARK: Safety
    static func report(_ body: ReportRequest) throws -> Endpoint {
        try .post("reports", body: body)
    }
    static func block(userID: UUID) throws -> Endpoint {
        try .post("safety/blocks/\(userID.uuidString)")
    }
    static func unblock(userID: UUID) -> Endpoint {
        .delete("safety/blocks/\(userID.uuidString)")
    }
    static let blockedUsers = Endpoint.get("safety/blocks")
    static func mute(userID: UUID) throws -> Endpoint {
        try .post("safety/mutes/\(userID.uuidString)")
    }
    static func unmute(userID: UUID) -> Endpoint {
        .delete("safety/mutes/\(userID.uuidString)")
    }
    static let mutedUsers = Endpoint.get("safety/mutes")

    // MARK: Moderation
    static let modQueue = Endpoint.get("moderation/queue")
    static func approveReport(id: UUID) throws -> Endpoint {
        try .post("moderation/reports/\(id.uuidString)/approve")
    }
    static func removeReport(id: UUID) throws -> Endpoint {
        try .post("moderation/reports/\(id.uuidString)/remove")
    }
    static func pinPost(id: UUID) throws -> Endpoint {
        try .post("posts/\(id.uuidString)/pin")
    }
    static func unpinPost(id: UUID) -> Endpoint {
        .delete("posts/\(id.uuidString)/pin")
    }
    static func lockPost(id: UUID) throws -> Endpoint {
        try .post("posts/\(id.uuidString)/lock")
    }
    static func unlockPost(id: UUID) -> Endpoint {
        .delete("posts/\(id.uuidString)/lock")
    }
    static func banUser(_ body: BanRequest) throws -> Endpoint {
        try .post("moderation/bans", body: body)
    }

    // MARK: Saved posts & view history
    static func saved(postID: UUID, saved: Bool) throws -> Endpoint {
        let path = "saved/\(postID.uuidString)"
        return saved ? try .post(path) : .delete(path)
    }
    static let savedPosts = Endpoint.get("saved")
    static func recordView(postID: UUID) throws -> Endpoint {
        try .post("history/\(postID.uuidString)")
    }
    static let viewHistory = Endpoint.get("history")

    // MARK: Events
    static let events = Endpoint.get("events")
    static func createEvent(_ body: CreateEventRequest) throws -> Endpoint {
        try .post("events", body: body)
    }
    static func rsvp(eventID: UUID, _ body: RSVPRequest) throws -> Endpoint {
        try .post("events/\(eventID.uuidString)/rsvp", body: body)
    }
}

// MARK: - Request bodies

struct OnboardRequest: Encodable { var handle: String; var displayName: String }
struct RespondFriendRequest: Encodable { var accept: Bool }
struct CreatePostRequest: Encodable {
    var title: String?
    var body: String
    var communityID: UUID?
}
struct VoteRequest: Encodable { var value: Int }
struct ReactRequest: Encodable { var reaction: String? }   // nil clears
struct AwardRequest: Encodable { var award: String }
struct ReplyRequest: Encodable {
    var postID: UUID
    var parentID: UUID?
    var body: String
}
struct SendMessageRequest: Encodable { var id: UUID; var text: String; var voiceNoteDuration: TimeInterval? }
struct DeviceTokenRequest: Encodable { var token: String }
struct ReportRequest: Encodable {
    var kind: String
    var targetID: UUID
    var reason: String
    var details: String?
}
struct BanRequest: Encodable { var userID: UUID; var communityID: UUID }
struct CreateEventRequest: Encodable {
    var title: String
    var details: String
    var communityID: UUID?
    var location: String
    var startDate: Date
}
struct RSVPRequest: Encodable { var status: String }
struct BugReportRequest: Encodable {
    var summary: String
    var details: String
    var severity: String
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceModel: String
    var locale: String
    var logs: String?
}
