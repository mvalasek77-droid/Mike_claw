import SwiftUI

/// Owns one chat thread: load history, optimistic send with delivery/read
/// status, and a simulated typing-then-reply from the other side so the demo
/// feels alive.
@MainActor
@Observable
final class ChatViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case error(String)
    }

    let conversation: Conversation
    private(set) var state: State = .loading
    private(set) var messages: [Message] = []
    private(set) var partnerTyping = false

    private let service: MessagingService

    init(conversation: Conversation, service: MessagingService) {
        self.conversation = conversation
        self.service = service
    }

    /// Only meaningful for 1:1 threads — groups don't show a single presence dot.
    var partnerOnline: Bool {
        !conversation.isGroup && conversation.participants.first?.isOnline == true
    }

    func load() async {
        state = .loading
        do {
            messages = try await service.messages(in: conversation.id)
            state = .loaded
            try? await service.markRead(conversation.id)
        } catch {
            BroLog.error(error, category: "messages")
            state = .error("Couldn't load this conversation.")
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Optimistic: show the message immediately as "sending".
        let optimistic = Message(
            id: UUID(), conversationID: conversation.id, sender: Session.me,
            text: trimmed, sentAt: .now, status: .sending
        )
        messages.append(optimistic)
        state = .loaded
        HapticsEngine.shared.play(.reaction)

        do {
            try await service.send(optimistic, to: conversation.id)
            updateStatus(of: optimistic.id, to: .sent)
        } catch {
            BroLog.error(error, category: "messages")
            messages.removeAll { $0.id == optimistic.id }
            HapticsEngine.shared.play(.error)
            return
        }

        await simulateReply()
    }

    func sendVoiceNote(duration: TimeInterval) async {
        let optimistic = Message(
            id: UUID(), conversationID: conversation.id, sender: Session.me,
            text: "Voice note", sentAt: .now, status: .sending, voiceNoteDuration: duration
        )
        messages.append(optimistic)
        state = .loaded
        HapticsEngine.shared.play(.reaction)

        do {
            try await service.send(optimistic, to: conversation.id)
            updateStatus(of: optimistic.id, to: .sent)
        } catch {
            BroLog.error(error, category: "messages")
            messages.removeAll { $0.id == optimistic.id }
            HapticsEngine.shared.play(.error)
            return
        }

        await simulateReply()
    }

    /// Typing indicator → canned reply, mirroring a real back-and-forth.
    private func simulateReply() async {
        partnerTyping = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        partnerTyping = false
        if let reply = try? await service.autoReply(to: conversation.id) {
            messages.append(reply)
            // Their reply implies they read ours.
            messages = messages.map {
                var m = $0; if m.isMine { m.status = .read }; return m
            }
            HapticsEngine.shared.play(.refreshDone)
        }
    }

    private func updateStatus(of id: UUID, to status: MessageStatus) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].status = status
    }
}
