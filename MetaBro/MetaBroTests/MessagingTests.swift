import Testing
import Foundation
@testable import MetaBro

@MainActor
struct MessagingTests {

    private func firstConversation() async -> Conversation {
        let service = MockMessagingService()
        let convos = (try? await service.conversations()) ?? []
        return convos.first!
    }

    @Test func conversationListLoads() async {
        let model = ConversationListViewModel(service: MockMessagingService())
        await model.load()
        guard case .loaded(let convos) = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
        #expect(convos.count == 2)
        // Sorted by most recent activity.
        #expect(convos == convos.sorted { $0.lastActivity > $1.lastActivity })
    }

    @Test func chatLoadsHistory() async {
        let service = MockMessagingService()
        let convo = (try? await service.conversations())!.first { !$0.isGroup }!
        let model = ChatViewModel(conversation: convo, service: service)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.messages.count == 3)
        // History is chronological.
        #expect(model.messages == model.messages.sorted { $0.sentAt < $1.sentAt })
    }

    @Test func sendAppendsMineThenAutoReply() async {
        let service = MockMessagingService()
        let convo = (try? await service.conversations())!.first!
        let model = ChatViewModel(conversation: convo, service: service)
        await model.load()
        let before = model.messages.count

        await model.send("Gym at 6 works")

        // My message + the simulated reply.
        #expect(model.messages.count == before + 2)
        let mine = model.messages.first { $0.text == "Gym at 6 works" }
        #expect(mine?.isMine == true)
        // After the reply lands, my message reads as Read.
        #expect(mine?.status == .read)
        #expect(model.partnerTyping == false)
    }

    @Test func emptyTextDoesNotSend() async {
        let service = MockMessagingService()
        let convo = (try? await service.conversations())!.first!
        let model = ChatViewModel(conversation: convo, service: service)
        await model.load()
        let before = model.messages.count
        await model.send("   ")
        #expect(model.messages.count == before)
    }
}
