import Foundation

protocol MessagingService: Sendable {
    func conversations() async throws -> [Conversation]
    func messages(in conversationID: UUID) async throws -> [Message]
    /// Persists an already-composed (optimistic) message.
    func send(_ message: Message, to conversationID: UUID) async throws
    /// A canned reply from the other side, for a lively demo. nil if none.
    func autoReply(to conversationID: UUID) async throws -> Message?
    /// Marks a thread read and clears its unread badge.
    func markRead(_ conversationID: UUID) async throws
}

/// Deterministic in-memory DMs for previews, tests, and offline demo.
actor MockMessagingService: MessagingService {
    private var threads: [Conversation]
    private var messagesByConversation: [UUID: [Message]]

    init() {
        let seed = MockMessagingService.seed()
        self.threads = seed.conversations
        self.messagesByConversation = seed.messages
    }

    func conversations() async throws -> [Conversation] {
        try await Task.sleep(nanoseconds: 200_000_000)
        return threads.sorted { $0.lastActivity > $1.lastActivity }
    }

    func messages(in conversationID: UUID) async throws -> [Message] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return (messagesByConversation[conversationID] ?? [])
            .sorted { $0.sentAt < $1.sentAt }
    }

    func send(_ message: Message, to conversationID: UUID) async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
        var stored = message
        stored.status = .delivered
        messagesByConversation[conversationID, default: []].append(stored)
        bumpConversation(conversationID, preview: message.text, unread: false)
    }

    func autoReply(to conversationID: UUID) async throws -> Message? {
        guard let convo = threads.first(where: { $0.id == conversationID }),
              let partner = convo.participants.first else { return nil }
        let reply = Message(
            id: UUID(), conversationID: conversationID, sender: partner,
            text: Self.cannedReply, sentAt: .now, status: .delivered
        )
        messagesByConversation[conversationID, default: []].append(reply)
        bumpConversation(conversationID, preview: reply.text, unread: false)
        return reply
    }

    func markRead(_ conversationID: UUID) async throws {
        guard let idx = threads.firstIndex(where: { $0.id == conversationID }) else { return }
        threads[idx].unreadCount = 0
        messagesByConversation[conversationID] = (messagesByConversation[conversationID] ?? [])
            .map { var m = $0; if m.isMine { m.status = .read }; return m }
    }

    private func bumpConversation(_ id: UUID, preview: String, unread: Bool) {
        guard let idx = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[idx].lastMessage = preview
        threads[idx].lastActivity = .now
        if unread { threads[idx].unreadCount += 1 }
    }

    private static let cannedReply = "Solid. Count me in 💪"

    private static func seed() -> (conversations: [Conversation], messages: [UUID: [Message]]) {
        let marcus = User(id: UUID(), handle: "@ironbro", displayName: "Marcus",
                          avatarURL: nil, broCred: 4_820)
        let dave = User(id: UUID(), handle: "@coachdave", displayName: "Dave",
                        avatarURL: nil, broCred: 9_300)
        let sam = User(id: UUID(), handle: "@newbro", displayName: "Sam",
                       avatarURL: nil, broCred: 40)

        let dm = Conversation(
            id: UUID(), participants: [marcus], isGroup: false, title: nil,
            lastMessage: "See you at the gym at 6", lastActivity: .now.addingTimeInterval(-600),
            unreadCount: 2
        )
        let group = Conversation(
            id: UUID(), participants: [dave, sam], isGroup: true, title: "Saturday Ballers",
            lastMessage: "Riverside courts, 10am", lastActivity: .now.addingTimeInterval(-3_600),
            unreadCount: 0
        )

        let dmMessages: [Message] = [
            Message(id: UUID(), conversationID: dm.id, sender: marcus,
                    text: "Yo, you lifting today?", sentAt: .now.addingTimeInterval(-1_200), status: .read),
            Message(id: UUID(), conversationID: dm.id, sender: Session.me,
                    text: "For sure. Push day.", sentAt: .now.addingTimeInterval(-900), status: .read),
            Message(id: UUID(), conversationID: dm.id, sender: marcus,
                    text: "See you at the gym at 6", sentAt: .now.addingTimeInterval(-600), status: .delivered),
        ]
        let groupMessages: [Message] = [
            Message(id: UUID(), conversationID: group.id, sender: dave,
                    text: "Who's in for Saturday?", sentAt: .now.addingTimeInterval(-4_200), status: .read),
            Message(id: UUID(), conversationID: group.id, sender: sam,
                    text: "I'm down", sentAt: .now.addingTimeInterval(-3_900), status: .read),
            Message(id: UUID(), conversationID: group.id, sender: dave,
                    text: "Riverside courts, 10am", sentAt: .now.addingTimeInterval(-3_600), status: .read),
        ]
        return ([dm, group], [dm.id: dmMessages, group.id: groupMessages])
    }
}
