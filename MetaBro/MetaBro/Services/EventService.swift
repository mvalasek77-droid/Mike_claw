import Foundation

protocol EventService: Sendable {
    /// Upcoming events first (soonest first), then past events.
    func events() async throws -> [Event]
    /// Creates an event hosted by the current user and returns it.
    func create(_ draft: EventDraft) async throws -> Event
    func setRSVP(eventID: UUID, status: RSVPStatus) async throws
}

/// Deterministic in-memory events for previews, tests, and offline demo.
actor MockEventService: EventService {
    private var events: [Event]

    init(events: [Event] = MockEventService.seed()) {
        self.events = events
    }

    func events() async throws -> [Event] {
        try await Task.sleep(nanoseconds: 200_000_000)
        let upcoming = events.filter { !$0.isPast }.sorted { $0.startDate < $1.startDate }
        let past = events.filter(\.isPast).sorted { $0.startDate > $1.startDate }
        return upcoming + past
    }

    func create(_ draft: EventDraft) async throws -> Event {
        guard draft.isValid else { throw APIError.server(status: 422) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let event = Event(
            id: UUID(),
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
            community: draft.community,
            host: Session.me,
            location: draft.location.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: draft.startDate,
            attendeeCount: 1,
            myRSVP: .going
        )
        events.insert(event, at: 0)
        return event
    }

    func setRSVP(eventID: UUID, status: RSVPStatus) async throws {
        guard let idx = events.firstIndex(where: { $0.id == eventID }) else { return }
        let wasGoing = events[idx].myRSVP == .going
        let isGoing = status == .going
        if wasGoing != isGoing {
            events[idx].attendeeCount += isGoing ? 1 : -1
        }
        events[idx].myRSVP = status
    }

    static func seed() -> [Event] {
        let bros = MockCommunityService.seed()
        let host = User(id: UUID(), handle: "@coachmike", displayName: "Coach Mike", avatarURL: nil, broCred: 4_200)
        return [
            Event(id: UUID(), title: "Saturday Morning Lift", details: "Heavy squat day, bring a spotter.",
                  community: bros.first, host: host, location: "Iron Bro-hood Gym, Dallas TX",
                  startDate: .now.addingTimeInterval(86_400 * 2), attendeeCount: 41, myRSVP: .going),
            Event(id: UUID(), title: "Grill-Off Watch Party", details: "Cowboys game + brisket cook-off.",
                  community: bros[1], host: host, location: "Riverside Park, Austin TX",
                  startDate: .now.addingTimeInterval(86_400 * 5), attendeeCount: 18, myRSVP: .interested),
            Event(id: UUID(), title: "Garage Build Night", details: "Bring your project, swap parts and stories.",
                  community: bros[2], host: host, location: "Gearhead Garage, Houston TX",
                  startDate: .now.addingTimeInterval(86_400 * 9), attendeeCount: 9),
            Event(id: UUID(), title: "Last Month's Cookout", details: "Already happened — wrapped photos.",
                  community: bros[1], host: host, location: "Riverside Park, Austin TX",
                  startDate: .now.addingTimeInterval(-86_400 * 20), attendeeCount: 24, myRSVP: .going),
        ]
    }
}
