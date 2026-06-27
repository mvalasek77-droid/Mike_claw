import Testing
import Foundation
@testable import MetaBro

/// Coverage for this slice: event RSVP/attendee-count bookkeeping, the
/// upcoming-then-past ordering, optimistic RSVP with rollback, and event
/// creation flowing into the list.
@MainActor
struct MockEventServiceTests {

    @Test func upcomingEventsComeBeforePastOnes() async throws {
        let service = MockEventService()
        let events = try await service.events()
        let firstPastIndex = events.firstIndex { $0.isPast }
        let lastUpcomingIndex = events.lastIndex { !$0.isPast }
        if let firstPastIndex, let lastUpcomingIndex {
            #expect(lastUpcomingIndex < firstPastIndex)
        }
    }

    @Test func rsvpGoingIncrementsAttendeeCount() async throws {
        let service = MockEventService()
        let before = try await service.events()
        let target = try #require(before.first { $0.myRSVP != .going })
        let beforeCount = target.attendeeCount

        try await service.setRSVP(eventID: target.id, status: .going)
        let after = try await service.events()
        let updated = try #require(after.first { $0.id == target.id })
        #expect(updated.attendeeCount == beforeCount + 1)
        #expect(updated.myRSVP == .going)
    }

    @Test func leavingGoingDecrementsAttendeeCount() async throws {
        let service = MockEventService()
        let before = try await service.events()
        let target = try #require(before.first { $0.myRSVP == .going })
        let beforeCount = target.attendeeCount

        try await service.setRSVP(eventID: target.id, status: .interested)
        let after = try await service.events()
        let updated = try #require(after.first { $0.id == target.id })
        #expect(updated.attendeeCount == beforeCount - 1)
        #expect(updated.myRSVP == .interested)
    }

    @Test func createInsertsEventAuthoredByCurrentUser() async throws {
        let service = MockEventService(events: [])
        let draft = EventDraft(title: "Pickup Hoops", details: "Bring water",
                               community: nil, location: "City Park", startDate: .now)
        let event = try await service.create(draft)
        #expect(event.host.id == Session.me.id)
        #expect(event.myRSVP == .going)

        let all = try await service.events()
        #expect(all.contains { $0.id == event.id })
    }

    @Test func createRejectsInvalidDraft() async {
        let service = MockEventService()
        let draft = EventDraft(title: "", details: "", community: nil, location: "", startDate: .now)
        await #expect(throws: APIError.self) {
            _ = try await service.create(draft)
        }
    }
}

@MainActor
struct EventsViewModelTests {

    @Test func loadPopulatesEvents() async {
        let model = EventsViewModel(service: MockEventService())
        await model.load()
        guard case .loaded = model.state else {
            Issue.record("expected .loaded, got \(model.state)"); return
        }
    }

    @Test func emptyServiceProducesEmptyState() async {
        let model = EventsViewModel(service: MockEventService(events: []))
        await model.load()
        #expect(model.state == .empty)
    }

    @Test func rsvpRollsBackOnFailure() async {
        let model = EventsViewModel(service: FailingRSVPService())
        await model.load()
        guard case .loaded(let events) = model.state, let first = events.first else {
            Issue.record("no events"); return
        }
        let before = first.myRSVP
        await model.rsvp(first, status: .going)

        guard case .loaded(let after) = model.state,
              let updated = after.first(where: { $0.id == first.id }) else {
            Issue.record("event vanished"); return
        }
        #expect(updated.myRSVP == before) // rolled back
    }

    @Test func createdInsertsAtFront() async {
        let model = EventsViewModel(service: MockEventService())
        await model.load()
        let host = User(id: UUID(), handle: "@host", displayName: "Host", avatarURL: nil, broCred: 0)
        let fresh = Event(id: UUID(), title: "New Event", details: "", community: nil, host: host,
                           location: "Somewhere", startDate: .now.addingTimeInterval(3_600), attendeeCount: 1)
        model.created(fresh)

        guard case .loaded(let events) = model.state else {
            Issue.record("expected .loaded"); return
        }
        #expect(events.first?.id == fresh.id)
    }
}

private struct FailingRSVPService: EventService {
    func events() async throws -> [Event] {
        try await MockEventService().events()
    }
    func create(_ draft: EventDraft) async throws -> Event {
        throw APIError.server(status: 500)
    }
    func setRSVP(eventID: UUID, status: RSVPStatus) async throws {
        throw APIError.server(status: 500)
    }
}
