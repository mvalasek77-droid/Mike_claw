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
}

// MARK: - Request bodies

struct OnboardRequest: Encodable { var handle: String; var displayName: String }
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
struct SendMessageRequest: Encodable { var id: UUID; var text: String }
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
