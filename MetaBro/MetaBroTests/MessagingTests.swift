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
        // Sorted by most recent activity. `sorted` is rethrows — bind first.
        let byActivity = convos.sorted { $0.lastActivity > $1.lastActivity }
        #expect(convos == byActivity)
    }

    @Test func chatLoadsHistory() async {
        let service = MockMessagingService()
        let convo = (try? await service.conversations())!.first { !$0.isGroup }!
        let model = ChatViewModel(conversation: convo, service: service)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.messages.count == 3)
        // History is chronological. `sorted` is rethrows — bind first.
        let chronological = model.messages.sorted { $0.sentAt < $1.sentAt }
        #expect(model.messages == chronological)
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

    @Test func sendVoiceNoteAppendsAMessageWithADuration() async {
        let service = MockMessagingService()
        let convo = (try? await service.conversations())!.first!
        let model = ChatViewModel(conversation: convo, service: service)
        await model.load()
        let before = model.messages.count

        await model.sendVoiceNote(duration: 12)

        let mine = model.messages.first { $0.isMine && $0.voiceNoteDuration != nil }
        #expect(mine?.voiceNoteDuration == 12)
        #expect(mine?.isVoiceNote == true)
        // My voice note + the simulated reply.
        #expect(model.messages.count == before + 2)
    }

    @Test func partnerOnlineReflectsTheOtherParticipantsPresence() async {
        let service = MockMessagingService()
        let convos = (try? await service.conversations()) ?? []
        let dm = convos.first { !$0.isGroup }!
        let model = ChatViewModel(conversation: dm, service: service)
        #expect(model.partnerOnline == (dm.participants.first?.isOnline ?? false))
    }

    @Test func groupConversationsReportNoSinglePartnerPresence() async {
        let service = MockMessagingService()
        let convos = (try? await service.conversations()) ?? []
        let group = convos.first { $0.isGroup }!
        let model = ChatViewModel(conversation: group, service: service)
        #expect(model.partnerOnline == false)
    }
}

struct PushNotificationServiceTests {

    @Test func requestingAuthorizationGrantsAndPersists() async {
        let service = MockPushNotificationService()
        #expect(await service.isAuthorized() == false)
        let granted = await service.requestAuthorization()
        #expect(granted == true)
        #expect(await service.isAuthorized() == true)
    }

    @Test func registeringADeviceTokenDoesNotThrow() async throws {
        let service = MockPushNotificationService()
        try await service.registerDeviceToken("abc123")
    }
}
