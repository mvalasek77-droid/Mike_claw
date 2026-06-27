import SwiftUI

/// Drives the events list: upcoming Bro-hood meetups first, then past ones,
/// with an optimistic RSVP toggle.
@MainActor
@Observable
final class EventsViewModel {
    enum State: Equatable {
        case loading
        case loaded([Event])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading
    private let service: EventService

    init(service: EventService) {
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let events = try await service.events()
            state = events.isEmpty ? .empty : .loaded(events)
        } catch {
            BroLog.error(error, category: "events")
            state = .error("Couldn't load events.")
        }
    }

    /// Optimistic RSVP, rolled back on failure.
    func rsvp(_ event: Event, status: RSVPStatus) async {
        guard case .loaded(var events) = state,
              let idx = events.firstIndex(where: { $0.id == event.id }) else { return }

        let previous = events[idx]
        let wasGoing = previous.myRSVP == .going
        let isGoing = status == .going
        events[idx].myRSVP = status
        if wasGoing != isGoing {
            events[idx].attendeeCount += isGoing ? 1 : -1
        }
        state = .loaded(events)
        HapticsEngine.shared.play(.selectionChanged)

        do {
            try await service.setRSVP(eventID: event.id, status: status)
        } catch {
            BroLog.error(error, category: "events")
            if case .loaded(var current) = state,
               let i = current.firstIndex(where: { $0.id == event.id }) {
                current[i] = previous
                state = .loaded(current)
            }
            HapticsEngine.shared.play(.error)
        }
    }

    /// Inserts a freshly-created event at the front of the loaded list.
    func created(_ event: Event) {
        guard case .loaded(var events) = state else {
            state = .loaded([event])
            return
        }
        events.insert(event, at: 0)
        state = .loaded(events)
    }
}
